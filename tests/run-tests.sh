#!/usr/bin/env bash
# run-tests.sh - Convenient test runner with configuration loading
#
# Usage:
#   ./run-tests.sh                    # Run unit tests only
#   ./run-tests.sh integration        # Run all tests including integration
#   ./run-tests.sh TestAksSpotModule* # Run specific test pattern

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load .env file if it exists
if [ -f .env ]; then
    echo -e "${GREEN}✓${NC} Loading configuration from .env"
    set -a  # Export all variables
    source .env
    set +a
else
    echo -e "${YELLOW}⚠${NC} No .env file found. Using defaults."
    echo -e "  Create one from: cp .env.example .env"
fi

# Ensure dependencies are up to date
echo -e "${GREEN}✓${NC} Updating Go dependencies"
go mod tidy

# Determine test pattern and timeout
if [ $# -eq 0 ]; then
    # No arguments - run unit tests only
    echo -e "${GREEN}✓${NC} Running unit tests (no Azure deployment)"
    TEST_PATTERN="./..."
    TIMEOUT="10m"
    export RUN_INTEGRATION_TESTS=false
elif [ "$1" = "integration" ]; then
    # Integration flag - run all tests
    echo -e "${GREEN}✓${NC} Running ALL tests (including integration - will deploy to Azure)"
    TEST_PATTERN="./..."
    TIMEOUT="60m"
    export RUN_INTEGRATION_TESTS=true
else
    # Specific test pattern
    echo -e "${GREEN}✓${NC} Running tests matching: $1"
    TEST_PATTERN="-run $1"
    TIMEOUT="30m"
fi

# Show configuration
echo ""
echo "Configuration:"
echo "  Azure Location:    ${TEST_AZURE_LOCATION:-australiaeast (default)}"
echo "  Terraform Dir:     ${TEST_TERRAFORM_DIR:-../terraform/environments/prod (default)}"
echo "  Integration Tests: ${RUN_INTEGRATION_TESTS:-false}"
echo "  Timeout:           $TIMEOUT"
echo ""

# Run tests
echo -e "${GREEN}▶${NC} Running tests..."
echo ""

if go test -v $TEST_PATTERN -timeout "$TIMEOUT" ./...; then
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}✗ Tests failed${NC}"
    exit 1
fi
