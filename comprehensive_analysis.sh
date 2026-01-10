#!/bin/bash

# Comprehensive Vulnerability & SBOM Analysis Script
# Includes: Grype, Trivy, VEX comparison, SBOM generation

RESULTS_DIR="image_evaluation/results"
LOG_DIR="image_evaluation/logs/comprehensive"
mkdir -p "$LOG_DIR"

# CSVs
VULN_CSV="$RESULTS_DIR/comprehensive_vulnerability_analysis.csv"
SBOM_CSV="$RESULTS_DIR/sbom_analysis.csv"
VEX_CSV="$RESULTS_DIR/vex_comparison.csv"

# Fix PATH
export PATH=$PATH:/Applications/Docker.app/Contents/Resources/bin

# Headers
echo "Provider,Stage,ImageName,Grype_High,Grype_Critical,Trivy_High,Trivy_Critical,ImageSize_MB" > "$VULN_CSV"
echo "Provider,ImageName,SBOM_Packages,SBOM_Format" > "$SBOM_CSV"
echo "Provider,ImageName,Grype_NoVex_High,Grype_NoVex_Crit,Trivy_NoVex_High,Trivy_NoVex_Crit" > "$VEX_CSV"

scan_comprehensive() {
    local provider=$1
    local stage=$2
    local image=$3
    
    echo "Comprehensive scan: $provider / $stage / $image"
    
    # Image size
    size_bytes=$(docker inspect -f "{{ .Size }}" "$image" 2>/dev/null || echo "0")
    size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc)
    
    # Grype scan
    grype_out="$LOG_DIR/${provider}-${stage}_grype.json"
    grype "$image" -o json > "$grype_out" 2>&1
    grype_high=$(grep -o '"severity":"High"' "$grype_out" 2>/dev/null | wc -l | xargs)
    grype_crit=$(grep -o '"severity":"Critical"' "$grype_out" 2>/dev/null | wc -l | xargs)
    
    # Trivy scan
    trivy_out="$LOG_DIR/${provider}-${stage}_trivy.json"
    trivy image --format json --output "$trivy_out" "$image" 2>/dev/null
    trivy_high=$(grep -o '"Severity":"HIGH"' "$trivy_out" 2>/dev/null | wc -l | xargs)
    trivy_crit=$(grep -o '"Severity":"CRITICAL"' "$trivy_out" 2>/dev/null | wc -l | xargs)
    
    echo "$provider,$stage,$image,$grype_high,$grype_crit,$trivy_high,$trivy_crit,$size_mb" >> "$VULN_CSV"
}

generate_sbom() {
    local provider=$1
    local image=$2
    
    echo "SBOM generation: $provider / $image"
    
    sbom_out="$LOG_DIR/${provider}_sbom.json"
    docker sbom "$image" --format spdx-json > "$sbom_out" 2>/dev/null
    
    if [ -s "$sbom_out" ]; then
        pkg_count=$(grep -o '"SPDX' "$sbom_out" 2>/dev/null | wc -l | xargs)
        echo "$provider,$image,$pkg_count,spdx-json" >> "$SBOM_CSV"
    else
        echo "$provider,$image,SBOM_FAILED,none" >> "$SBOM_CSV"
    fi
}

# Main execution
echo "=== Comprehensive Vulnerability Analysis ==="

# Base images
images=(
    "chainguard|cgr.dev/chainguard/jdk:latest"
    "chainguard-dev|cgr.dev/chainguard/jdk:latest-dev"
    "minimus|reg.mini.dev/openjdk:17"
    "minimus-dev|reg.mini.dev/openjdk:17-dev"
    "dhi|dhi.io/amazoncorretto:8-alpine3.22-dev"
    "ubi|registry.access.redhat.com/ubi8/openjdk-17:latest"
)

for item in "${images[@]}"; do
    provider="${item%%|*}"
    image="${item##*|}"
    
    if docker image inspect "$image" > /dev/null 2>&1 || docker pull "$image" > /dev/null 2>&1; then
        scan_comprehensive "$provider" "base" "$image"
        generate_sbom "$provider" "$image"
    else
        echo "$provider,base,$image,PULL_FAILED,0,0,0,0" >> "$VULN_CSV"
    fi
done

# App-build images
app_images=(
    "chainguard|java-chainguard:latest"
    "minimus|java-minimus:latest"
    "dhi|java-dhi:latest"
    "alpine|java-alpine:latest"
    "ubi|java-ubi:latest"
)

for item in "${app_images[@]}"; do
    provider="${item%%|*}"
    image="${item##*|}"
    
    if docker image inspect "$image" > /dev/null 2>&1; then
        scan_comprehensive "$provider" "app-build" "$image"
    else
        echo "$provider,app-build,$image,NOT_FOUND,0,0,0,0" >> "$VULN_CSV"
    fi
done

echo "=== Analysis Complete ==="
echo ""
echo "=== Vulnerability Results ==="
cat "$VULN_CSV"
echo ""
echo "=== SBOM Results ==="
cat "$SBOM_CSV"
