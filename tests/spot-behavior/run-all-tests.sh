#!/usr/bin/env bash
# run-all-tests.sh - Entry point for AKS spot behavior tests
#
# SETUP:
#   1. Copy .env.example to .env
#   2. Edit .env with your cluster details (CLUSTER_NAME, RESOURCE_GROUP, NAMESPACE)
#   3. Load configuration: source .env OR export $(cat .env | xargs)
#   4. Run tests (see usage below)
#   See README.md for detailed setup instructions
#
# Usage:
#   ./run-all-tests.sh                          # Run all tests
#   ./run-all-tests.sh --category pod-dist      # Run one category
#   ./run-all-tests.sh --test DIST-001          # Run one test
#   ./run-all-tests.sh --dry-run                # List tests without executing
#   ./run-all-tests.sh --category eviction --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/test_runner.sh"

CATEGORY=""
TEST=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category) CATEGORY="$2"; shift 2 ;;
    --test)     TEST="$2"; shift 2 ;;
    --dry-run)  DRY_RUN="true"; shift ;;
    -h|--help)
      echo "Usage: $0 [--category <name>] [--test <TEST-ID>] [--dry-run]"
      echo ""
      echo "Categories:"
      echo "  01-pod-distribution    DIST-001..010  (read-only)"
      echo "  02-eviction-behavior   EVICT-001..010 (destructive)"
      echo "  03-pdb-enforcement     PDB-001..006   (destructive)"
      echo "  04-topology-spread     TOPO-001..005  (destructive)"
      echo "  05-recovery-rescheduling RECV-001..006 (destructive)"
      echo "  06-sticky-fallback     STICK-001..005 (destructive)"
      echo "  07-vmss-node-pool      VMSS-001..006  (read-only az CLI)"
      echo "  08-autoscaler          AUTO-001..005  (mixed)"
      echo "  09-cross-service       DEP-001..005   (destructive)"
      echo "  10-edge-cases          EDGE-001..005  (destructive)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Clear previous results (unless running a single test)
if [[ -z "$TEST" && "$DRY_RUN" == "false" ]]; then
  rm -f "${RESULTS_DIR}"/*.json 2>/dev/null || true
fi

# Discover and run
mapfile -t TESTS < <(discover_tests "$CATEGORY" "$TEST")

if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "No tests found matching filters (category=$CATEGORY, test=$TEST)"
  exit 1
fi

echo "Found ${#TESTS[@]} test(s) to execute"
echo ""

for script in "${TESTS[@]}"; do
  run_test "$script" "$DRY_RUN"
done

# Aggregate if we actually ran tests
if [[ "$DRY_RUN" == "false" ]]; then
  aggregate_results
fi
