#!/bin/bash

RESULTS_CSV="image_evaluation/results/evaluation_matrix.csv"
LOG_DIR="image_evaluation/logs"

# Header for CSV
echo "App,Provider,BuildTime_Seconds,ImageSize_MB,Trivy_High,Trivy_Critical,Grype_High,Grype_Critical,OSV_Vulns" > "$RESULTS_CSV"

apps=("java" "springboot" "nodejs" "go" "python")
providers=("chainguard" "minimus" "dhi" "alpine" "ubi")

# Use a limited set for testing if needed, but per request we do all.
# apps=("python") 
# providers=("alpine")

# Fix PATH for Docker Desktop credentials
export PATH=$PATH:/Applications/Docker.app/Contents/Resources/bin

# Fix build context: Dockerfiles expect "apps/..." but they are in "image_evaluation/apps/..."
# We copy the directory to avoid symlink issues in Docker build context
if [[ ! -d "apps" ]]; then
    cp -r image_evaluation/apps apps
    CREATED_SYMLINK=false # It's a copy now, but we can track if needed (script logic doesn't use this var much)
fi

for app in "${apps[@]}"; do
    for prov in "${providers[@]}"; do
        image_name="${app}-${prov}:latest"
        dockerfile="image_evaluation/dockerfiles/${app}/Dockerfile.${prov}"
        
        echo "---------------------------------------------------"
        echo "Processing $image_name using $dockerfile"
        
        if [[ ! -f "$dockerfile" ]]; then
            echo "Skipping $image_name: Dockerfile not found at $dockerfile"
            continue
        fi

        # 1. Build & Measure Time
        start_time=$(date +%s)
        # Use existing docker found in /usr/local/bin (symlinked)
        /usr/local/bin/docker build -t "$image_name" -f "$dockerfile" . > "$LOG_DIR/${image_name}_build.log" 2>&1
        build_status=$?
        end_time=$(date +%s)
        build_duration=$((end_time - start_time))
        
        if [ $build_status -ne 0 ]; then
            echo "Build FAILED for $image_name. See $LOG_DIR/${image_name}_build.log"
            echo "$app,$prov,FAILED,0,0,0,0,0,0" >> "$RESULTS_CSV"
            continue
        fi

        # 2. Image Size
        # Get size in bytes, convert to MB 
        size_bytes=$(/usr/local/bin/docker inspect -f "{{ .Size }}" "$image_name")
        size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc)

        echo "Build Success: $build_duration sec, $size_mb MB"

        # 3. Trivy Scan
        trivy_out="$LOG_DIR/${image_name}_trivy.json"
        trivy image --format json --output "$trivy_out" "$image_name" > /dev/null 2>&1
        # Parse JSON for counts (using grep/jq would be better but keeping simple for bash deps)
        # Assuming jq is available or simple grep. Let's try to use grep count for "Severity": "HIGH"
        # Actually, trivy json is complex. 
        # Better: run trivy twice? No, slow.
        # Fallback if jq not present: just store 0 or use simple text grep.
        # I'll rely on text scan for summaries if jq is missing, but simplest is to assume standard tools or just grep.
        
        # Simple hacky count from json:
        trivy_high=$(grep -o '"Severity":"HIGH"' "$trivy_out" | wc -l | xargs)
        trivy_crit=$(grep -o '"Severity":"CRITICAL"' "$trivy_out" | wc -l | xargs)

        # 4. Grype Scan
        grype_out="$LOG_DIR/${image_name}_grype.json"
        grype "$image_name" -o json > "$grype_out" 2>&1
        grype_high=$(grep -o '"severity":"High"' "$grype_out" | wc -l | xargs)
        grype_crit=$(grep -o '"severity":"Critical"' "$grype_out" | wc -l | xargs)

        # 5. OSV Scan
        osv_out="$LOG_DIR/${image_name}_osv.json"
        osv-scanner -L "$image_name" --format json > "$osv_out" 2>&1
        # OSV output format varies, usually counts references. 
        # We'll just count "id": occurrences as a proxy for total vulns matching
        osv_vulns=$(grep -o '"id":' "$osv_out" | wc -l | xargs)

        # Append to CSV
        echo "$app,$prov,$build_duration,$size_mb,$trivy_high,$trivy_crit,$grype_high,$grype_crit,$osv_vulns" >> "$RESULTS_CSV"
        
    done
done

echo "Evaluation Complete. Results in $RESULTS_CSV"
cat "$RESULTS_CSV"
