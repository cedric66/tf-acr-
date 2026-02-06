#!/bin/bash
###############################################################################
# AKS Spot-Optimized Deployment Script (Bicep)
# Purpose: Deploy or update AKS cluster using Bicep templates
###############################################################################

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../../main.bicep"
PARAM_FILE="${SCRIPT_DIR}/main.bicepparam"

# Default values - override with environment variables
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-prod}"
LOCATION="${LOCATION:-australiaeast}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  deploy     Deploy or update the AKS cluster"
    echo "  validate   Validate the Bicep template without deploying"
    echo "  what-if    Preview changes without deploying"
    echo "  help       Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  RESOURCE_GROUP   Target resource group (default: rg-aks-prod)"
    echo "  LOCATION         Azure region (default: australiaeast)"
}

validate() {
    log_info "Validating Bicep template..."
    az bicep build --file "$TEMPLATE_FILE" --stdout > /dev/null
    log_info "✓ Template validation successful"
}

what_if() {
    log_info "Running what-if deployment..."
    az deployment group what-if \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "$PARAM_FILE"
}

deploy() {
    log_info "Deploying to resource group: $RESOURCE_GROUP"
    log_info "Using template: $TEMPLATE_FILE"
    log_info "Using parameters: $PARAM_FILE"
    
    # Ensure resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Creating resource group: $RESOURCE_GROUP"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
    fi
    
    # Deploy
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "$PARAM_FILE" \
        --name "aks-spot-$(date +%Y%m%d-%H%M%S)"
    
    log_info "✓ Deployment completed successfully"
}

# Main
case "${1:-help}" in
    deploy)
        validate
        deploy
        ;;
    validate)
        validate
        ;;
    what-if)
        validate
        what_if
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
