#!/usr/bin/env bash
# validate-scripts.sh - Validate all shell scripts follow coding standards
#
# Usage:
#   ./validate-scripts.sh
#
# Checks:
#   - Shebang is #!/usr/bin/env bash (not #!/bin/bash)
#   - Safety flags: set -euo pipefail
#   - No hardcoded cluster names, resource groups, etc.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Shell Script Standards Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find all .sh scripts
SCRIPTS=$(find . -name "*.sh" -type f | sort)
TOTAL=$(echo "$SCRIPTS" | wc -l)

echo "Found $TOTAL shell scripts"
echo ""

# Check 1: Shebang line
echo "━━━ Check 1: Shebang Line ━━━"
WRONG_SHEBANG=()
while IFS= read -r script; do
  FIRST_LINE=$(head -n 1 "$script")
  if [[ "$FIRST_LINE" != "#!/usr/bin/env bash" ]]; then
    WRONG_SHEBANG+=("$script: $FIRST_LINE")
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$SCRIPTS"

if [[ ${#WRONG_SHEBANG[@]} -eq 0 ]]; then
  echo -e "${GREEN}✓${NC} All scripts use correct shebang: #!/usr/bin/env bash"
else
  echo -e "${RED}✗${NC} Scripts with incorrect shebang:"
  for item in "${WRONG_SHEBANG[@]}"; do
    echo "  $item"
  done
fi
echo ""

# Check 2: Safety flags (set -euo pipefail)
echo "━━━ Check 2: Safety Flags ━━━"
MISSING_SAFETY=()
while IFS= read -r script; do
  if ! grep -q "set -euo pipefail" "$script"; then
    MISSING_SAFETY+=("$script")
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$SCRIPTS"

if [[ ${#MISSING_SAFETY[@]} -eq 0 ]]; then
  echo -e "${GREEN}✓${NC} All scripts include: set -euo pipefail"
else
  echo -e "${RED}✗${NC} Scripts missing safety flags:"
  for script in "${MISSING_SAFETY[@]}"; do
    echo "  $script"
  done
fi
echo ""

# Check 3: Hardcoded cluster names
echo "━━━ Check 3: Hardcoded Values ━━━"
HARDCODED_ISSUES=()
PATTERNS=(
  'CLUSTER_NAME="aks-.*"'
  'RESOURCE_GROUP="rg-.*"'
  'NAMESPACE="[a-z-]*"'
  'LOCATION="[a-z]*"'
)
while IFS= read -r script; do
  # Skip if it's a config file (allowed to have defaults)
  if [[ "$script" =~ config\.sh$ ]]; then
    continue
  fi

  for pattern in "${PATTERNS[@]}"; do
    if grep -qE "$pattern" "$script" 2>/dev/null; then
      # Check if it uses the ${VAR:-default} pattern
      if ! grep -qE '\$\{[A-Z_]+:-' "$script"; then
        HARDCODED_ISSUES+=("$script: Found pattern $pattern without env var fallback")
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done
done <<< "$SCRIPTS"

if [[ ${#HARDCODED_ISSUES[@]} -eq 0 ]]; then
  echo -e "${GREEN}✓${NC} No hardcoded values found (or using proper env var pattern)"
else
  echo -e "${YELLOW}⚠${NC} Potential hardcoded values (review manually):"
  for issue in "${HARDCODED_ISSUES[@]}"; do
    echo "  $issue"
  done
fi
echo ""

# Check 4: Executable permissions
echo "━━━ Check 4: Executable Permissions ━━━"
NON_EXECUTABLE=()
while IFS= read -r script; do
  if [[ ! -x "$script" ]]; then
    NON_EXECUTABLE+=("$script")
    WARNINGS=$((WARNINGS + 1))
  fi
done <<< "$SCRIPTS"

if [[ ${#NON_EXECUTABLE[@]} -eq 0 ]]; then
  echo -e "${GREEN}✓${NC} All scripts are executable"
else
  echo -e "${YELLOW}⚠${NC} Scripts missing executable permission:"
  for script in "${NON_EXECUTABLE[@]}"; do
    echo "  $script (fix with: chmod +x $script)"
  done
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total scripts: $TOTAL"
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
  echo -e "${GREEN}✓ All checks passed!${NC}"
  exit 0
elif [[ $ERRORS -eq 0 ]]; then
  echo -e "${YELLOW}⚠ No errors, but $WARNINGS warnings found${NC}"
  exit 0
else
  echo -e "${RED}✗ $ERRORS errors must be fixed${NC}"
  exit 1
fi
