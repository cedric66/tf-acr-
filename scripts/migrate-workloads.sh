#!/usr/bin/env bash
#
# migrate-workloads.sh - Generate kubectl patches to migrate workloads to Spot
#
# Usage:
#   ./migrate-workloads.sh [--namespace <NS>] [--execute]
#   ./migrate-workloads.sh --mock <mock-file.json>   # For testing
#

set -euo pipefail

# ==================== Configuration ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/spot-config.yaml"

# ==================== Argument Parsing ====================
NAMESPACE=""
MOCK_FILE=""
EXECUTE=false

usage() {
    echo "Usage: $0 [--namespace <NS>] [--execute] [--mock <file>]"
    echo "  --execute    Actually apply the patches (default: dry-run)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace|-n)
            NAMESPACE="$2"
            shift 2
            ;;
        --mock)
            MOCK_FILE="$2"
            shift 2
            ;;
        --execute)
            EXECUTE=true
            shift
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
        kubectl get deploy $ns_flag -o json
    fi
}

has_spot_toleration() {
    local tolerations=$1
    echo "$tolerations" | jq -r '
        if . == null then false
        else [.[] | select(.key == "kubernetes.azure.com/scalesetpriority" and .value == "spot")] | length > 0
        end
    '
}

# ==================== Main Logic ====================

echo "============ MIGRATE WORKLOADS TO SPOT ============"
echo ""

# Read config
EXCLUDED_NAMESPACES=$(parse_yaml_list "$CONFIG_FILE" "excluded_namespaces")
STATELESS_PCT=$(parse_yaml_value "$CONFIG_FILE" "stateless_deployments")

# Get workloads
WORKLOADS_JSON=$(get_workloads_json)

# Patch template
SPOT_PATCH='{
  "spec": {
    "template": {
      "spec": {
        "tolerations": [
          {
            "key": "kubernetes.azure.com/scalesetpriority",
            "operator": "Equal",
            "value": "spot",
            "effect": "NoSchedule"
          }
        ],
        "affinity": {
          "nodeAffinity": {
            "preferredDuringSchedulingIgnoredDuringExecution": [
              {
                "weight": 100,
                "preference": {
                  "matchExpressions": [
                    {
                      "key": "kubernetes.azure.com/scalesetpriority",
                      "operator": "In",
                      "values": ["spot"]
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    }
  }
}'

# Topology spread patch (for replicas >= 3)
TOPOLOGY_PATCH='{
  "spec": {
    "template": {
      "spec": {
        "topologySpreadConstraints": [
          {
            "maxSkew": 1,
            "topologyKey": "topology.kubernetes.io/zone",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {}
            }
          }
        ]
      }
    }
  }
}'

COMMANDS=()
SKIPPED=()

while IFS= read -r item; do
    NAME=$(echo "$item" | jq -r '.metadata.name')
    NS=$(echo "$item" | jq -r '.metadata.namespace')
    KIND=$(echo "$item" | jq -r '.kind')
    REPLICAS=$(echo "$item" | jq -r '.spec.replicas // 1')
    LABELS=$(echo "$item" | jq -r '.spec.selector.matchLabels // {}')
    
    TOLERATIONS=$(echo "$item" | jq '.spec.template.spec.tolerations // []')
    HAS_TOLERATION=$(has_spot_toleration "$TOLERATIONS")
    
    # Check exclusions
    if echo "$EXCLUDED_NAMESPACES" | grep -qx "$NS"; then
        SKIPPED+=("$NS/$NAME: excluded namespace")
        continue
    fi
    
    if [[ "$HAS_TOLERATION" == "true" ]]; then
        SKIPPED+=("$NS/$NAME: already has Spot toleration")
        continue
    fi
    
    if [[ "$KIND" != "Deployment" ]]; then
        SKIPPED+=("$NS/$NAME: not a Deployment")
        continue
    fi
    
    # Generate patch command
    CMD="kubectl patch deployment $NAME -n $NS --type=strategic -p '$SPOT_PATCH'"
    COMMANDS+=("$CMD")
    
    # Add topology spread if replicas >= 3
    if [[ "$REPLICAS" -ge 3 ]]; then
        # Inject matchLabels dynamically
        TOPO_PATCH_WITH_LABELS=$(echo "$TOPOLOGY_PATCH" | jq --argjson labels "$LABELS" '.spec.template.spec.topologySpreadConstraints[0].labelSelector.matchLabels = $labels')
        TOPO_CMD="kubectl patch deployment $NAME -n $NS --type=strategic -p '$TOPO_PATCH_WITH_LABELS'"
        COMMANDS+=("$TOPO_CMD")
    fi
    
done < <(echo "$WORKLOADS_JSON" | jq -c '.items[]')

# Output skipped
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "Skipped workloads:"
    for s in "${SKIPPED[@]}"; do
        echo "  - $s"
    done
    echo ""
fi

# Output commands
echo "============ GENERATED PATCH COMMANDS ============"
for cmd in "${COMMANDS[@]}"; do
    echo "$cmd"
    echo ""
done

# Execute if requested
if $EXECUTE; then
    echo ""
    echo "============ EXECUTING ============"
    for cmd in "${COMMANDS[@]}"; do
        echo "Running: $cmd"
        eval "$cmd"
    done
else
    echo "============================================"
    echo "DRY RUN: Commands not executed."
    echo "Add --execute flag to apply these patches."
    echo "============================================"
fi
