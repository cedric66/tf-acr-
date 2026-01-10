#!/bin/bash
set -e

# Configuration
TF_DIR="terraform/env/dev"
BUILD_CTX="build_ctx"
ZIP_FILE="app.zip"
LOCAL_REPORT_DIR="azure_reports"

echo "=== Azure Build & Scan Pipeline ==="

# 1. Retrieve Terraform Outputs
echo "--> Reading Terraform Outputs..."
if [ ! -d "$TF_DIR" ]; then
    echo "Error: Directory $TF_DIR not found."
    exit 1
fi

pushd "$TF_DIR" > /dev/null
# Check if TF is initialized/applied
if [ ! -f "terraform.tfstate" ]; then
    echo "Warning: terraform.tfstate not found. Please run 'terraform apply' first."
    popd > /dev/null
    exit 1
fi
RG_NAME=$(terraform output -raw resource_group_name)
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
SHARE_NAME=$(terraform output -raw share_name)
popd > /dev/null

echo "    RG: $RG_NAME"
echo "    Storage: $STORAGE_ACCOUNT"
echo "    Share: $SHARE_NAME"

# 2. Prepare Source Code
echo "--> Preparing Build Context..."
rm -rf "$BUILD_CTX"
mkdir -p "$BUILD_CTX"

copy_app() {
    local src_dir=$1
    local dest_dir=$2
    local dockerfile=$3
    
    # Create destination directly in build_ctx (no nested folder)
    mkdir -p "$BUILD_CTX/$dest_dir"
    cp -r app/$src_dir/* "$BUILD_CTX/$dest_dir/"
    if [ -f "$dockerfile" ]; then
        echo "    Using optimized Dockerfile for $dest_dir"
        cp "$dockerfile" "$BUILD_CTX/$dest_dir/Dockerfile"
    else
        echo "    Warning: Optimized Dockerfile not found for $dest_dir ($dockerfile)"
        echo "    Falling back to app/$src_dir/Dockerfile"
    fi
}

copy_app "python" "python-app" "image_evaluation/dockerfiles/python/Dockerfile.chainguard-migrated"
copy_app "node" "nodejs-app" "image_evaluation/dockerfiles/nodejs/Dockerfile.chainguard-migrated"
copy_app "java" "java-app" "image_evaluation/dockerfiles/java/Dockerfile.chainguard"
copy_app "go" "go-app" "image_evaluation/dockerfiles/go/Dockerfile.chainguard-migrated"

# Zip contents directly (NOT the build_ctx folder itself)
# This ensures unzip creates /workspace/app/{python-app,nodejs-app,...} directly
echo "--> Zipping source..."
cd "$BUILD_CTX"
zip -r -q "../$ZIP_FILE" .
cd ..

# 3. Upload to Azure Storage
echo "--> Uploading to Azure Storage..."
az storage file upload \
    --account-name "$STORAGE_ACCOUNT" \
    --share-name "$SHARE_NAME" \
    --source "$ZIP_FILE" \
    --path "$ZIP_FILE" \
    --only-show-errors

# 4. Trigger Builds
APPS=("python" "node" "java" "go")
echo "--> Triggering Build Jobs..."
for app in "${APPS[@]}"; do
    job="build-$app"
    echo "    Starting $job..."
    az containerapp job start --name "$job" --resource-group "$RG_NAME" --no-wait
done

# Wait function
wait_for_jobs() {
    local prefix=$1
    echo "    Waiting for $prefix jobs to complete (timeout 20m)..."
    for i in {1..40}; do
        pending=0
        for app in "${APPS[@]}"; do
            job="$prefix-$app"
            # Get the latest execution status
            status=$(az containerapp job execution list \
                --name "$job" \
                --resource-group "$RG_NAME" \
                --query "[0].properties.status" \
                -o tsv 2>/dev/null || echo "Unknown")
            
            if [[ "$status" == "Running" || "$status" == "Unknown" || "$status" == "Pending" ]]; then
                pending=$((pending+1))
            elif [[ "$status" == "Failed" ]]; then
                echo "    ERROR: Job $job failed!"
            fi
        done
        if [ $pending -eq 0 ]; then
            echo "    All $prefix jobs finished."
            return 0
        fi
        echo "    $pending jobs still running... (Attempt $i/40)"
        sleep 30
    done
    echo "    Timeout waiting for jobs."
    return 1
}

wait_for_jobs "build"

# 5. Trigger Scans
echo "--> Triggering Scan Jobs..."
for app in "${APPS[@]}"; do
    job="scan-$app"
    echo "    Starting $job..."
    az containerapp job start --name "$job" --resource-group "$RG_NAME" --no-wait
done

wait_for_jobs "scan"

# 6. Retrieve Reports
echo "--> Downloading Scan Reports..."
mkdir -p "$LOCAL_REPORT_DIR"

# Download scan reports (path updated to match scanner job output)
for app in "${APPS[@]}"; do
    report_file="scan-$app.json"
    az storage file download \
        --account-name "$STORAGE_ACCOUNT" \
        --share-name "$SHARE_NAME" \
        --path "$report_file" \
        --dest "$LOCAL_REPORT_DIR/$report_file" \
        --only-show-errors 2>/dev/null || echo "    Warning: Report for $app not found."
done

echo "=== Pipeline Complete ==="
echo "Reports available in $LOCAL_REPORT_DIR/"
ls -lh "$LOCAL_REPORT_DIR/"
