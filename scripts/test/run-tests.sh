#!/usr/bin/env bash
#
# run-tests.sh - Test runner for AKS Spot optimization scripts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/.."
MOCKS_DIR="${SCRIPT_DIR}/mocks"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ==================== Assertion Helpers ====================

assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if echo "$output" | grep -qF -- "$expected"; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected to find: $expected"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if ! echo "$output" | grep -qF -- "$unexpected"; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Did not expect to find: $unexpected"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_exit_code() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$actual" -eq "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected exit code: $expected, got: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==================== Test Cases ====================

echo "============================================"
echo "  AKS Spot Optimization - Test Suite"
echo "============================================"
echo ""

# ----- Test 1: Eligibility Report - NAP Ready Cluster -----
echo -e "${YELLOW}Test Set 1: Eligibility Report - NAP Ready${NC}"

OUTPUT=$("${SCRIPTS_DIR}/eligibility-report.sh" --mock "${MOCKS_DIR}/cluster-nap-ready.json" 2>&1 || true)

assert_contains "$OUTPUT" "NAP COMPATIBLE" "Should detect NAP compatibility"
assert_contains "$OUTPUT" "Azure CNI Overlay" "Should identify overlay network"
assert_contains "$OUTPUT" "Standard_D4s_v5" "Should select first available SKU"
assert_contains "$OUTPUT" "No Spot pools found" "Should detect missing Spot pools"

echo ""

# ----- Test 2: Eligibility Report - Legacy Cluster -----
echo -e "${YELLOW}Test Set 2: Eligibility Report - Legacy Cluster${NC}"

OUTPUT=$("${SCRIPTS_DIR}/eligibility-report.sh" --mock "${MOCKS_DIR}/cluster-legacy.json" 2>&1 || true)

assert_contains "$OUTPUT" "NAP INCOMPATIBLE" "Should detect NAP incompatibility"
assert_contains "$OUTPUT" "Kubenet" "Should identify kubenet network"
assert_contains "$OUTPUT" "Cluster Autoscaler" "Should recommend CAS fallback"

echo ""

# ----- Test 3: Add Spot Pools - Command Generation -----
echo -e "${YELLOW}Test Set 3: Add Spot Pools - Command Generation${NC}"

OUTPUT=$("${SCRIPTS_DIR}/add-spot-pools.sh" --mock "${MOCKS_DIR}/cluster-nap-ready.json" 2>&1 || true)

assert_contains "$OUTPUT" "az aks nodepool add" "Should generate az nodepool add command"
assert_contains "$OUTPUT" "--priority Spot" "Should set Spot priority"
assert_contains "$OUTPUT" "--eviction-policy Delete" "Should set Delete eviction policy"
assert_contains "$OUTPUT" "--spot-max-price -1" "Should use market price"
assert_contains "$OUTPUT" "--enable-cluster-autoscaler" "Should enable autoscaler"
assert_contains "$OUTPUT" "DRY RUN" "Should be in dry-run mode by default"

echo ""

# ----- Test 4: Workload Report -----
echo -e "${YELLOW}Test Set 4: Workload Report${NC}"

OUTPUT=$("${SCRIPTS_DIR}/workload-report.sh" --mock "${MOCKS_DIR}/workloads.json" 2>&1 || true)

assert_contains "$OUTPUT" "web-frontend" "Should list web-frontend deployment"
assert_contains "$OUTPUT" "api-backend" "Should list api-backend deployment"
assert_contains "$OUTPUT" "postgres" "Should list postgres statefulset"
assert_contains "$OUTPUT" "excluded namespace" "Should mark kube-system as excluded"
assert_contains "$OUTPUT" "StatefulSet excluded" "Should exclude StatefulSets"

echo ""

# ----- Test 5: Migrate Workloads -----
echo -e "${YELLOW}Test Set 5: Migrate Workloads${NC}"

OUTPUT=$("${SCRIPTS_DIR}/migrate-workloads.sh" --mock "${MOCKS_DIR}/workloads.json" 2>&1 || true)

assert_contains "$OUTPUT" "kubectl patch deployment" "Should generate kubectl patch"
assert_contains "$OUTPUT" "web-frontend" "Should patch web-frontend"
assert_contains "$OUTPUT" "api-backend" "Should patch api-backend"
assert_contains "$OUTPUT" "topologySpreadConstraints" "Should add topology spread for high-replica workloads"
assert_contains "$OUTPUT" "excluded namespace" "Should skip kube-system"
assert_contains "$OUTPUT" "DRY RUN" "Should be in dry-run mode by default"

echo ""

# ==================== Summary ====================
echo "============================================"
echo "  Test Summary"
echo "============================================"
echo "  Tests Run:    $TESTS_RUN"
echo -e "  ${GREEN}Passed:       $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed:       $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "  ${GREEN}All tests passed!${NC}"
fi
