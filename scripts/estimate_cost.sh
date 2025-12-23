#!/bin/bash
set -e

# Define Terraform directory
TF_DIR="terraform/env/dev"

echo "Cost Estimation Script"
echo "======================"
echo "Checking for Infracost..."

if ! command -v infracost &> /dev/null; then
    echo "Infracost not found. Attempting to install..."
    # Note: In a real environment, you might use brew or direct download.
    # Here we simulate or use curl if allowed.
    curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
else
    echo "Infracost is installed."
fi

# Check for API Key
if [ -z "$INFRACOST_API_KEY" ]; then
    echo "Warning: INFRACOST_API_KEY is not set."
    echo "Infracost requires an API key to fetch pricing data."
    echo "Please set INFRACOST_API_KEY and run this script again."
    echo "Skipping cost estimation."
else
    echo "Running Infracost..."
    infracost breakdown --path "$TF_DIR" --format table
fi
