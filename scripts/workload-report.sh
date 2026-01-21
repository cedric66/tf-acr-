#!/usr/bin/env bash
#
# workload-report.sh - Generate report of all workloads and Spot eligibility
#
# Usage:
#   ./workload-report.sh [--namespace <NS>] [--output json|markdown]
#   ./workload-report.sh --mock <mock-file.json>   # For testing
#

set -euo pipefail

# ==================== Configuration ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/spot-config.yaml"

# ==================== Argument Parsing ====================
NAMESPACE=""
OUTPUT_FORMAT="markdown"
MOCK_FILE=""

usage() {
    echo "Usage: $0 [--namespace <NS>] [--output json|markdown] [--mock <file>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace|-n)
            NAMESPACE="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --mock)
            MOCK_FILE="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# ==================== Helper Functions ====================

parse_yaml_value() {
    local file=$1
    local key=$2
    # Extract value and strip inline comments
    grep -E "^  ${key}:" "$file" | head -1 | sed "s/^  ${key}: *//" | sed 's/#.*//' | tr -d "'" | xargs
}

parse_yaml_list() {
    local file=$1
    local key=$2
    grep -A 100 "^${key}:" "$file" | grep -E "^  - " | sed 's/^  - //' | head -20
}

get_workloads_json() {
    if [[ -n "$MOCK_FILE" ]]; then
        cat "$MOCK_FILE"
    else
        local ns_flag=""
        if [[ -n "$NAMESPACE" ]]; then
            ns_flag="-n $NAMESPACE"
        else
            ns_flag="-A"
        fi
        kubectl get deploy,sts,cronjob $ns_flag -o json
    fi
}

# Check if workload has Spot toleration
has_spot_toleration() {
    local tolerations=$1
    echo "$tolerations" | jq -r '
        if . == null then false
        else [.[] | select(.key == "kubernetes.azure.com/scalesetpriority" and .value == "spot")] | length > 0
        end
    '
}

# Check if workload has Spot affinity
has_spot_affinity() {
    local affinity=$1
    echo "$affinity" | jq -r '
        if . == null then false
        else .nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution // [] |
             [.[] | select(.preference.matchExpressions[]?.key == "kubernetes.azure.com/scalesetpriority")] | length > 0
        end
    '
}

# ==================== Main Logic ====================

# Read config
EXCLUDED_NAMESPACES=$(parse_yaml_list "$CONFIG_FILE" "excluded_namespaces")
STATELESS_PCT=$(parse_yaml_value "$CONFIG_FILE" "stateless_deployments")
STATEFULSET_PCT=$(parse_yaml_value "$CONFIG_FILE" "statefulsets")
BATCH_PCT=$(parse_yaml_value "$CONFIG_FILE" "batch_jobs")

# Get workloads
WORKLOADS_JSON=$(get_workloads_json)

# Process workloads
RESULTS=()

while IFS= read -r item; do
    NAME=$(echo "$item" | jq -r '.metadata.name')
    NS=$(echo "$item" | jq -r '.metadata.namespace')
    KIND=$(echo "$item" | jq -r '.kind')
    REPLICAS=$(echo "$item" | jq -r '.spec.replicas // 1')
    
    # Get tolerations and affinity from pod template
    TOLERATIONS=$(echo "$item" | jq '.spec.template.spec.tolerations // []')
    AFFINITY=$(echo "$item" | jq '.spec.template.spec.affinity // {}')
    
    HAS_TOLERATION=$(has_spot_toleration "$TOLERATIONS")
    HAS_AFFINITY=$(has_spot_affinity "$AFFINITY")
    
    # Determine eligibility
    ELIGIBLE="Yes"
    ELIGIBLE_PCT=0
    REASON=""
    
    # Check excluded namespaces
    if echo "$EXCLUDED_NAMESPACES" | grep -qx "$NS"; then
        ELIGIBLE="No"
        REASON="excluded namespace"
    elif [[ "$KIND" == "Deployment" ]]; then
        ELIGIBLE_PCT=$STATELESS_PCT
        REASON="${STATELESS_PCT}%"
    elif [[ "$KIND" == "StatefulSet" ]]; then
        ELIGIBLE_PCT=$STATEFULSET_PCT
        if [[ "$STATEFULSET_PCT" -eq 0 ]]; then
            ELIGIBLE="No"
            REASON="StatefulSet excluded"
        else
            REASON="${STATEFULSET_PCT}%"
        fi
    elif [[ "$KIND" == "CronJob" ]]; then
        ELIGIBLE_PCT=$BATCH_PCT
        REASON="${BATCH_PCT}%"
    fi
    
    TOLERATION_ICON="❌"
    AFFINITY_ICON="❌"
    ELIGIBLE_ICON="❌"
    
    [[ "$HAS_TOLERATION" == "true" ]] && TOLERATION_ICON="✅"
    [[ "$HAS_AFFINITY" == "true" ]] && AFFINITY_ICON="✅"
    [[ "$ELIGIBLE" == "Yes" ]] && ELIGIBLE_ICON="✅ ($REASON)"
    [[ "$ELIGIBLE" == "No" ]] && ELIGIBLE_ICON="❌ ($REASON)"
    
    RESULTS+=("$NS|$NAME|$KIND|$REPLICAS|$TOLERATION_ICON|$AFFINITY_ICON|$ELIGIBLE_ICON")
    
done < <(echo "$WORKLOADS_JSON" | jq -c '.items[]')

# Output
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo "["
    first=true
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r ns name kind replicas tol aff elig <<< "$row"
        $first || echo ","
        first=false
        echo "  {\"namespace\": \"$ns\", \"name\": \"$name\", \"kind\": \"$kind\", \"replicas\": $replicas, \"hasToleration\": \"$tol\", \"hasAffinity\": \"$aff\", \"eligible\": \"$elig\"}"
    done
    echo "]"
else
    echo "# Workload Spot Eligibility Report"
    echo ""
    echo "| Namespace | Name | Kind | Replicas | Has Toleration? | Has Affinity? | Spot Eligible? |"
    echo "|-----------|------|------|----------|-----------------|---------------|----------------|"
    for row in "${RESULTS[@]}"; do
        IFS='|' read -r ns name kind replicas tol aff elig <<< "$row"
        echo "| $ns | $name | $kind | $replicas | $tol | $aff | $elig |"
    done
fi

echo ""
echo "---"
echo "Total workloads analyzed: ${#RESULTS[@]}"
