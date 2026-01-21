#!/usr/bin/env bash
#
# export-cluster.sh - Export AKS cluster configuration to ARM template
#
# Usage:
#   ./export-cluster.sh --resource-group <RG> --name <CLUSTER> [--output-file <file>]
#   ./export-cluster.sh --mock <mock-file.json>
#

set -euo pipefail

# ==================== Argument Parsing ====================
RESOURCE_GROUP=""
CLUSTER_NAME=""
OUTPUT_FILE=""
MOCK_FILE=""

usage() {
    echo "Usage: $0 --resource-group <RG> --name <CLUSTER> [--output-file <file>] [--mock <file>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group|-g)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --name|-n)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --output-file|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --mock)
            MOCK_FILE="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# Validate required args if not mocking
if [[ -z "$MOCK_FILE" ]]; then
    if [[ -z "$RESOURCE_GROUP" || -z "$CLUSTER_NAME" ]]; then
        echo "Error: --resource-group and --name are required."
        usage
    fi
fi

# ==================== Main Logic ====================

get_export() {
    if [[ -n "$MOCK_FILE" ]]; then
        cat "$MOCK_FILE"
    else
        # 1. Get AKS Resource ID
        local aks_id
        aks_id=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query id -o tsv)

        # 2. Export Resource (outputs to stdout by default)
        az group export --resource-ids "$aks_id"
    fi
}

# Run export
if [[ -n "$OUTPUT_FILE" ]]; then
    get_export > "$OUTPUT_FILE"
    echo "✓ Exported cluster configuration to $OUTPUT_FILE"
else
    get_export
fi
