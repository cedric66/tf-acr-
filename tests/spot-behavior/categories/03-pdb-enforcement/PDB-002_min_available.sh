#!/usr/bin/env bash
# PDB-002: All PDBs have minAvailable=1
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "PDB-002" "All PDBs have minAvailable=1" "pdb-enforcement"

pdbs=$(kubectl get pdb -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')

for pdb_name in $(echo "$pdbs" | jq -r '.items[].metadata.name'); do
  min_avail=$(echo "$pdbs" | jq -r --arg n "$pdb_name" '.items[] | select(.metadata.name == $n) | .spec.minAvailable // "unset"')
  assert_eq "$pdb_name minAvailable" "$min_avail" "1"
done

finish_test
