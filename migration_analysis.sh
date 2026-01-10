#!/bin/bash

# Complete SBOM and Migration Analysis Script
# Covers all languages: Java, Spring Boot, Node.js, Go, Python

RESULTS_DIR="image_evaluation/results"
LOG_DIR="image_evaluation/logs/migration"
mkdir -p "$LOG_DIR"

# CSVs
SBOM_ALL_CSV="$RESULTS_DIR/sbom_all_languages.csv"
MIGRATION_CSV="$RESULTS_DIR/migration_analysis.csv"
BUILD_TIMES_CSV="$RESULTS_DIR/build_times_summary.csv"

export PATH=$PATH:/Applications/Docker.app/Contents/Resources/bin

# Headers
echo "App,Provider,ImageName,SBOM_Packages,LibC_Type,Has_Shell,Has_PkgMgr,Size_MB" > "$SBOM_ALL_CSV"
echo "App,SourceProvider,TargetProvider,Migration_Method,Success,Notes" > "$MIGRATION_CSV"
echo "App,Provider,BuildTime_Seconds,ImageSize_MB,Grype_High,Grype_Critical" > "$BUILD_TIMES_CSV"

analyze_image() {
    local app=$1
    local provider=$2
    local image=$3
    
    echo "Analyzing: $app / $provider / $image"
    
    # Check if image exists
    if ! docker image inspect "$image" > /dev/null 2>&1; then
        echo "$app,$provider,$image,IMAGE_NOT_FOUND,unknown,unknown,unknown,0" >> "$SBOM_ALL_CSV"
        return
    fi
    
    # Get size
    size_bytes=$(docker inspect -f "{{ .Size }}" "$image" 2>/dev/null || echo "0")
    size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc)
    
    # SBOM generation
    sbom_out="$LOG_DIR/${app}-${provider}_sbom.json"
    docker sbom "$image" --format spdx-json > "$sbom_out" 2>/dev/null
    pkg_count=$(grep -o '"SPDX' "$sbom_out" 2>/dev/null | wc -l | xargs)
    
    # Check for libc type (musl vs glibc)
    libc_type="unknown"
    if docker run --rm --entrypoint="" "$image" ldd --version 2>/dev/null | grep -q "musl"; then
        libc_type="musl"
    elif docker run --rm --entrypoint="" "$image" ldd --version 2>/dev/null | grep -q "GLIBC\|glibc"; then
        libc_type="glibc"
    fi
    
    # Check for shell
    has_shell="no"
    if docker run --rm --entrypoint="" "$image" sh -c "echo test" > /dev/null 2>&1; then
        has_shell="yes"
    fi
    
    # Check for package manager
    has_pkgmgr="no"
    if docker run --rm --entrypoint="" "$image" sh -c "which apk || which apt-get || which microdnf || which yum" > /dev/null 2>&1; then
        has_pkgmgr="yes"
    fi
    
    echo "$app,$provider,$image,$pkg_count,$libc_type,$has_shell,$has_pkgmgr,$size_mb" >> "$SBOM_ALL_CSV"
}

# Collect build times from previous evaluation
echo "=== Collecting Build Times ==="
if [ -f "$RESULTS_DIR/evaluation_matrix.csv" ]; then
    tail -n +2 "$RESULTS_DIR/evaluation_matrix.csv" | while IFS=, read -r app provider build_time size trivy_h trivy_c grype_h grype_c osv; do
        if [ "$build_time" != "FAILED" ]; then
            echo "$app,$provider,$build_time,$size,$grype_h,$grype_c" >> "$BUILD_TIMES_CSV"
        fi
    done
fi

# Analyze all built images
echo "=== SBOM Analysis for All Languages ==="
for app in java springboot nodejs go python; do
    for provider in chainguard minimus dhi alpine ubi; do
        image="${app}-${provider}:latest"
        analyze_image "$app" "$provider" "$image"
    done
done

# Test Chainguard DFC migration tool
echo "=== Testing DFC Migration Tool ==="
for app in nodejs springboot go python; do
    dockerfile="image_evaluation/dockerfiles/${app}/Dockerfile.alpine"
    if [ -f "$dockerfile" ]; then
        echo "Running dfc on: $dockerfile"
        dfc_out="$LOG_DIR/dfc_${app}_alpine.txt"
        timeout 30 dfc "$dockerfile" > "$dfc_out" 2>&1 || echo "DFC timeout/error"
        
        if [ -s "$dfc_out" ]; then
            echo "$app,alpine,chainguard,dfc_tool,SUCCESS,See $dfc_out" >> "$MIGRATION_CSV"
        else
            echo "$app,alpine,chainguard,dfc_tool,FAILED,Tool output empty" >> "$MIGRATION_CSV"
        fi
    fi
done

echo "=== Analysis Complete ==="
echo ""
echo "=== SBOM Results ==="
cat "$SBOM_ALL_CSV"
echo ""
echo "=== Build Times ==="
cat "$BUILD_TIMES_CSV"
echo ""
echo "=== Migration Analysis ==="
cat "$MIGRATION_CSV"
