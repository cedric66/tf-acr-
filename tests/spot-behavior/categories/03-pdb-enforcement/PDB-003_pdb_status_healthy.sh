#!/usr/bin/env bash
# PDB-003: PDB status shows disruptionsAllowed > 0
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "PDB-003" "PDB status healthy - disruptions allowed" "pdb-enforcement"

pdbs=$(kubectl get pdb -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')

for pdb_name in $(echo "$pdbs" | jq -r '.items[].metadata.name'); do
  allowed=$(echo "$pdbs" | jq -r --arg n "$pdb_name" '.items[] | select(.metadata.name == $n) | .status.disruptionsAllowed // 0')
  current_healthy=$(echo "$pdbs" | jq -r --arg n "$pdb_name" '.items[] | select(.metadata.name == $n) | .status.currentHealthy // 0')

  assert_gt "$pdb_name disruptionsAllowed > 0" "$allowed" 0
  assert_gt "$pdb_name currentHealthy > 0" "$current_healthy" 0
done

finish_test
