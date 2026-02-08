#!/usr/bin/env bash
# PDB-006: PDB label selectors match actual pods
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "PDB-006" "PDB selectors match pods" "pdb-enforcement"

pdbs=$(kubectl get pdb -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')

for pdb_name in $(echo "$pdbs" | jq -r '.items[].metadata.name'); do
  # Get the matchLabels selector
  selector=$(echo "$pdbs" | jq -r --arg n "$pdb_name" '
    .items[] | select(.metadata.name == $n) |
    .spec.selector.matchLabels // {} | to_entries | map(.key + "=" + .value) | join(",")')

  [[ -z "$selector" ]] && { assert_not_empty "$pdb_name has selector" ""; continue; }

  # Find pods matching the selector
  matched_pods=$(kubectl get pods -n "$NAMESPACE" -l "$selector" --no-headers 2>/dev/null | wc -l)
  assert_gt "$pdb_name selector matches pods" "$matched_pods" 0
done

finish_test
