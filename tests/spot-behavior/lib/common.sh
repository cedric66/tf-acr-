#!/usr/bin/env bash
# common.sh - Core test library: logging, assertions, kubectl/az wrappers, JSON output
# Source this file in every test script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config.sh
source "${SCRIPT_DIR}/../config.sh"

# ── Global test state ────────────────────────────────────────────
_TEST_ID=""
_TEST_NAME=""
_TEST_CATEGORY=""
_TEST_STATUS="error"
_TEST_START=""
_TEST_ASSERTIONS='[]'
_TEST_EVIDENCE='{}'
_TEST_ERROR=""
_CLEANUP_NODES=()

# ── Logging ──────────────────────────────────────────────────────
log_info()  { echo "[INFO]  $(date +%H:%M:%S) $*"; }
log_warn()  { echo "[WARN]  $(date +%H:%M:%S) $*" >&2; }
log_error() { echo "[ERROR] $(date +%H:%M:%S) $*" >&2; }
log_step()  { echo "  ➤ $*"; }

# ── Test lifecycle ───────────────────────────────────────────────

init_test() {
  local test_id="$1" test_name="$2" category="$3"
  _TEST_ID="$test_id"
  _TEST_NAME="$test_name"
  _TEST_CATEGORY="$category"
  _TEST_STATUS="error"
  _TEST_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  _TEST_ASSERTIONS='[]'
  _TEST_EVIDENCE='{}'
  _TEST_ERROR=""
  _CLEANUP_NODES=()

  log_info "━━━ ${_TEST_ID}: ${_TEST_NAME} ━━━"

  # Verify cluster connectivity
  if ! kubectl cluster-info &>/dev/null; then
    _TEST_ERROR="Cannot connect to cluster"
    _TEST_STATUS="error"
    finish_test
    exit 1
  fi
}

finish_test() {
  local end_time
  end_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local duration
  duration=$(( $(date -d "$end_time" +%s) - $(date -d "$_TEST_START" +%s) ))

  # Auto-determine pass/fail from assertions if not set explicitly
  if [[ "$_TEST_STATUS" == "error" && -z "$_TEST_ERROR" ]]; then
    local failed
    failed=$(echo "$_TEST_ASSERTIONS" | jq '[.[] | select(.passed == false)] | length')
    if [[ "$failed" -eq 0 ]]; then
      _TEST_STATUS="pass"
    else
      _TEST_STATUS="fail"
    fi
  fi

  # Build environment object
  local env_json
  env_json=$(jq -n \
    --arg cn "$CLUSTER_NAME" \
    --arg rg "$RESOURCE_GROUP" \
    --arg kv "$(kubectl version --short 2>/dev/null | head -1 || echo 'unknown')" \
    '{cluster_name: $cn, resource_group: $rg, kubernetes_version: $kv}')

  # Build result JSON
  local result
  result=$(jq -n \
    --arg tid "$_TEST_ID" \
    --arg tname "$_TEST_NAME" \
    --arg cat "$_TEST_CATEGORY" \
    --arg status "$_TEST_STATUS" \
    --arg start "$_TEST_START" \
    --arg end "$end_time" \
    --argjson dur "$duration" \
    --argjson assertions "$_TEST_ASSERTIONS" \
    --argjson evidence "$_TEST_EVIDENCE" \
    --arg err "$_TEST_ERROR" \
    --argjson env "$env_json" \
    '{
      test_id: $tid,
      test_name: $tname,
      category: $cat,
      status: $status,
      start_time: $start,
      end_time: $end,
      duration_seconds: $dur,
      assertions: $assertions,
      evidence: $evidence,
      error_message: $err,
      environment: $env
    }')

  # Write result file
  mkdir -p "$RESULTS_DIR"
  local outfile="${RESULTS_DIR}/${_TEST_ID}.json"
  echo "$result" | jq . > "$outfile"

  if [[ "$_TEST_STATUS" == "pass" ]]; then
    log_info "✓ ${_TEST_ID} PASSED (${duration}s)"
  elif [[ "$_TEST_STATUS" == "fail" ]]; then
    log_error "✗ ${_TEST_ID} FAILED (${duration}s)"
  elif [[ "$_TEST_STATUS" == "skip" ]]; then
    log_warn "⊘ ${_TEST_ID} SKIPPED: ${_TEST_ERROR}"
  else
    log_error "! ${_TEST_ID} ERROR: ${_TEST_ERROR}"
  fi
}

skip_test() {
  _TEST_STATUS="skip"
  _TEST_ERROR="$1"
  finish_test
  exit 0
}

# ── Assertion helpers ────────────────────────────────────────────

_add_assertion() {
  local desc="$1" expected="$2" actual="$3" passed="$4"
  _TEST_ASSERTIONS=$(echo "$_TEST_ASSERTIONS" | jq \
    --arg d "$desc" \
    --arg e "$expected" \
    --arg a "$actual" \
    --argjson p "$passed" \
    '. + [{description: $d, expected: $e, actual: $a, passed: $p}]')
  if [[ "$passed" == "true" ]]; then
    log_step "✓ $desc (expected: $expected, actual: $actual)"
  else
    log_step "✗ $desc (expected: $expected, actual: $actual)"
  fi
}

assert_gt() {
  local desc="$1" actual="$2" threshold="$3"
  if (( actual > threshold )); then
    _add_assertion "$desc" ">$threshold" "$actual" "true"
  else
    _add_assertion "$desc" ">$threshold" "$actual" "false"
  fi
}

assert_gte() {
  local desc="$1" actual="$2" threshold="$3"
  if (( actual >= threshold )); then
    _add_assertion "$desc" ">=$threshold" "$actual" "true"
  else
    _add_assertion "$desc" ">=$threshold" "$actual" "false"
  fi
}

assert_eq() {
  local desc="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    _add_assertion "$desc" "$expected" "$actual" "true"
  else
    _add_assertion "$desc" "$expected" "$actual" "false"
  fi
}

assert_lt() {
  local desc="$1" actual="$2" threshold="$3"
  if (( actual < threshold )); then
    _add_assertion "$desc" "<$threshold" "$actual" "true"
  else
    _add_assertion "$desc" "<$threshold" "$actual" "false"
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    _add_assertion "$desc" "contains $needle" "found" "true"
  else
    _add_assertion "$desc" "contains $needle" "not found" "false"
  fi
}

assert_not_empty() {
  local desc="$1" value="$2"
  if [[ -n "$value" ]]; then
    _add_assertion "$desc" "non-empty" "${#value} chars" "true"
  else
    _add_assertion "$desc" "non-empty" "empty" "false"
  fi
}

assert_json_gt() {
  local desc="$1" json="$2" jq_expr="$3" threshold="$4"
  local actual
  actual=$(echo "$json" | jq -r "$jq_expr" 2>/dev/null || echo "0")
  assert_gt "$desc" "$actual" "$threshold"
}

# ── Evidence helpers ─────────────────────────────────────────────

add_evidence() {
  local key="$1" value="$2"
  _TEST_EVIDENCE=$(echo "$_TEST_EVIDENCE" | jq --arg k "$key" --argjson v "$value" '. + {($k): $v}')
}

add_evidence_str() {
  local key="$1" value="$2"
  _TEST_EVIDENCE=$(echo "$_TEST_EVIDENCE" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
}

# ── kubectl wrappers ─────────────────────────────────────────────

kubectl_json() {
  kubectl "$@" -o json 2>/dev/null
}

get_pods_on_node() {
  local node="$1"
  kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" -o json 2>/dev/null
}

get_pods_for_service() {
  local service="$1"
  kubectl get pods -n "$NAMESPACE" -l "app=$service" -o json 2>/dev/null || \
  kubectl get pods -n "$NAMESPACE" -l "service=$service" -o json 2>/dev/null || \
  echo '{"items":[]}'
}

get_node_pool_for_node() {
  local node="$1"
  kubectl get node "$node" -o jsonpath='{.metadata.labels.agentpool}' 2>/dev/null
}

get_node_zone() {
  local node="$1"
  kubectl get node "$node" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null
}

is_spot_node() {
  local node="$1"
  local priority
  priority=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}' 2>/dev/null)
  [[ "$priority" == "spot" ]]
}

get_spot_nodes() {
  kubectl get nodes -l "kubernetes.azure.com/scalesetpriority=spot" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null
}

get_standard_nodes() {
  kubectl get nodes -l "agentpool=$STANDARD_POOL" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null
}

get_system_nodes() {
  kubectl get nodes -l "agentpool=$SYSTEM_POOL" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null
}

count_ready_nodes_in_pool() {
  local pool="$1"
  kubectl get nodes -l "agentpool=$pool" --no-headers 2>/dev/null | grep -c " Ready " || echo 0
}

# ── Node manipulation (destructive) ─────────────────────────────

drain_node() {
  local node="$1"
  log_step "Draining node $node ..."
  _CLEANUP_NODES+=("$node")
  kubectl drain "$node" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --grace-period="$DRAIN_TIMEOUT" \
    --timeout="${DRAIN_TIMEOUT}s" \
    --force 2>&1 || true
}

cordon_node() {
  local node="$1"
  log_step "Cordoning node $node ..."
  _CLEANUP_NODES+=("$node")
  kubectl cordon "$node" 2>&1
}

uncordon_node() {
  local node="$1"
  log_step "Uncordoning node $node ..."
  kubectl uncordon "$node" 2>&1 || true
}

# ── Cleanup trap ─────────────────────────────────────────────────

cleanup_nodes() {
  if [[ ${#_CLEANUP_NODES[@]} -gt 0 ]]; then
    log_info "Cleaning up: uncordoning ${#_CLEANUP_NODES[@]} node(s)..."
    for node in "${_CLEANUP_NODES[@]}"; do
      uncordon_node "$node"
    done
  fi
}

# ── Wait helpers ─────────────────────────────────────────────────

wait_for_pods_ready() {
  local label="$1" timeout="${2:-$POD_READY_TIMEOUT}"
  log_step "Waiting up to ${timeout}s for pods ($label) to be ready..."
  local end_time=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < end_time )); do
    local not_ready
    not_ready=$(kubectl get pods -n "$NAMESPACE" -l "$label" --no-headers 2>/dev/null \
      | grep -cv "Running\|Completed" || echo 0)
    if [[ "$not_ready" -eq 0 ]]; then
      log_step "All pods ready"
      return 0
    fi
    sleep 5
  done
  log_warn "Timeout waiting for pods ($label)"
  return 1
}

wait_for_node_count() {
  local pool="$1" min_count="$2" timeout="${3:-$NODE_READY_TIMEOUT}"
  log_step "Waiting up to ${timeout}s for pool $pool to have >=$min_count ready nodes..."
  local end_time=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < end_time )); do
    local count
    count=$(count_ready_nodes_in_pool "$pool")
    if (( count >= min_count )); then
      log_step "Pool $pool has $count nodes (>= $min_count)"
      return 0
    fi
    sleep 10
  done
  log_warn "Timeout: pool $pool has $(count_ready_nodes_in_pool "$pool") nodes (wanted >= $min_count)"
  return 1
}

# ── az CLI wrappers ──────────────────────────────────────────────

az_json() {
  az "$@" -o json 2>/dev/null
}

get_vmss_for_pool() {
  local pool="$1"
  az vmss list -g "MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION:-eastus}" \
    --query "[?tags.\"aks-managed-poolName\"=='$pool']" -o json 2>/dev/null || echo '[]'
}

get_vmss_instances() {
  local vmss_name="$1" vmss_rg="$2"
  az vmss list-instances -n "$vmss_name" -g "$vmss_rg" -o json 2>/dev/null || echo '[]'
}
