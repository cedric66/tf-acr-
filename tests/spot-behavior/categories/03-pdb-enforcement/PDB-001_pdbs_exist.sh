#!/usr/bin/env bash
# PDB-001: Verify PDBs exist for all protected services
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "PDB-001" "PDBs exist for protected services" "pdb-enforcement"

pdbs=$(kubectl get pdb -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
pdb_count=$(echo "$pdbs" | jq '.items | length')
assert_gte "At least ${#PDB_SERVICES[@]} PDBs exist" "$pdb_count" "${#PDB_SERVICES[@]}"

for svc in "${PDB_SERVICES[@]}"; do
  found=$(echo "$pdbs" | jq --arg s "$svc" '[.items[] | select(.metadata.name | contains($s))] | length')
  assert_gt "PDB exists for $svc" "$found" 0
done

add_evidence "pdb_names" "$(echo "$pdbs" | jq '[.items[].metadata.name]')"
finish_test
