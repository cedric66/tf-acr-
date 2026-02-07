#!/usr/bin/env bash
# test_runner.sh - Discovers test scripts, runs them, aggregates JSON results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../config.sh
source "${BASE_DIR}/config.sh"

CATEGORIES_DIR="${BASE_DIR}/categories"

# ── Discovery ────────────────────────────────────────────────────

discover_tests() {
  local category_filter="${1:-}"
  local test_filter="${2:-}"

  local scripts=()
  for cat_dir in "$CATEGORIES_DIR"/*/; do
    [[ -d "$cat_dir" ]] || continue
    local cat_name
    cat_name="$(basename "$cat_dir")"

    if [[ -n "$category_filter" && "$cat_name" != *"$category_filter"* ]]; then
      continue
    fi

    for script in "$cat_dir"/*.sh; do
      [[ -f "$script" ]] || continue
      local script_name
      script_name="$(basename "$script" .sh)"

      if [[ -n "$test_filter" ]]; then
        local test_id
        test_id=$(echo "$script_name" | grep -oP '^[A-Z]+-\d+' || echo "$script_name")
        if [[ "$test_id" != "$test_filter" && "$script_name" != *"$test_filter"* ]]; then
          continue
        fi
      fi

      scripts+=("$script")
    done
  done

  printf '%s\n' "${scripts[@]}"
}

# ── Execution ────────────────────────────────────────────────────

run_test() {
  local script="$1" dry_run="${2:-false}"
  local script_name
  script_name="$(basename "$script")"

  if [[ "$dry_run" == "true" ]]; then
    echo "[DRY-RUN] Would execute: $script"
    return 0
  fi

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Executing: $script_name"
  echo "═══════════════════════════════════════════════════"

  if bash "$script"; then
    return 0
  else
    echo "[WARN] Script $script_name exited with non-zero status"
    return 0  # Don't abort the run
  fi
}

# ── Aggregation ──────────────────────────────────────────────────

aggregate_results() {
  local run_id="run-$(date +%Y%m%d-%H%M%S)"
  local total=0 passed=0 failed=0 skipped=0 errors=0
  local results='[]'
  local categories='{}'
  local failed_tests='[]'

  for result_file in "$RESULTS_DIR"/*.json; do
    [[ -f "$result_file" ]] || continue

    local result
    result=$(cat "$result_file")
    results=$(echo "$results" | jq --argjson r "$result" '. + [$r]')

    local status cat_name
    status=$(echo "$result" | jq -r '.status')
    cat_name=$(echo "$result" | jq -r '.category')

    total=$((total + 1))
    case "$status" in
      pass)    passed=$((passed + 1)) ;;
      fail)    failed=$((failed + 1))
               failed_tests=$(echo "$failed_tests" | jq --argjson r "$result" \
                 '. + [{test_id: $r.test_id, error_message: $r.error_message}]') ;;
      skip)    skipped=$((skipped + 1)) ;;
      *)       errors=$((errors + 1)) ;;
    esac

    # Update category counts
    categories=$(echo "$categories" | jq --arg c "$cat_name" --arg s "$status" '
      if .[$c] == null then .[$c] = {total: 0, passed: 0, failed: 0, skipped: 0} else . end
      | .[$c].total += 1
      | if $s == "pass" then .[$c].passed += 1
        elif $s == "fail" then .[$c].failed += 1
        elif $s == "skip" then .[$c].skipped += 1
        else . end')
  done

  local pass_rate="0.0%"
  if [[ "$total" -gt 0 ]]; then
    pass_rate=$(awk "BEGIN {printf \"%.1f%%\", ($passed/$total)*100}")
  fi

  # Convert categories to array format
  local cat_array
  cat_array=$(echo "$categories" | jq '[to_entries[] | {name: .key, total: .value.total, passed: .value.passed, failed: .value.failed, skipped: .value.skipped}]')

  local summary
  summary=$(jq -n \
    --arg rid "$run_id" \
    --argjson total "$total" \
    --argjson passed "$passed" \
    --argjson failed "$failed" \
    --argjson skipped "$skipped" \
    --arg rate "$pass_rate" \
    --argjson cats "$cat_array" \
    --argjson ft "$failed_tests" \
    --argjson res "$results" \
    '{
      run_id: $rid,
      total_tests: $total,
      passed: $passed,
      failed: $failed,
      skipped: $skipped,
      pass_rate: $rate,
      categories: $cats,
      failed_tests: $ft,
      results: $res
    }')

  mkdir -p "$RESULTS_DIR"
  echo "$summary" | jq . > "${RESULTS_DIR}/summary-${run_id}.json"
  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Run Summary: $run_id"
  echo "  Total: $total  Pass: $passed  Fail: $failed  Skip: $skipped"
  echo "  Pass Rate: $pass_rate"
  echo "═══════════════════════════════════════════════════"

  if [[ "$failed" -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    echo "$failed_tests" | jq -r '.[] | "  ✗ \(.test_id): \(.error_message)"'
  fi

  echo ""
  echo "Results saved to: ${RESULTS_DIR}/summary-${run_id}.json"
}
