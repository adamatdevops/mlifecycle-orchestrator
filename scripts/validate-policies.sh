#!/bin/bash
# =============================================================================
# Policy Validation Script
# =============================================================================
# Validates model manifests against governance policies.
#
# Usage: ./scripts/validate-policies.sh [manifest-path]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check OPA is installed
if ! command -v opa &> /dev/null; then
    echo -e "${RED}Error: OPA is not installed${NC}"
    echo "Install OPA: https://www.openpolicyagent.org/docs/latest/#1-download-opa"
    exit 1
fi

# Get manifest path
MANIFEST="${1:-$PROJECT_ROOT/examples/valid/model-manifest.yaml}"

if [ ! -f "$MANIFEST" ]; then
    echo -e "${RED}Error: Manifest not found: $MANIFEST${NC}"
    exit 1
fi

echo "Validating: $MANIFEST"
echo ""

# Run OPA evaluation
RESULT=$(opa eval \
    --input "$MANIFEST" \
    --data "$PROJECT_ROOT/src/policies/model-governance.rego" \
    --format json \
    'data.model.governance.deny')

VIOLATIONS=$(echo "$RESULT" | jq -r '.result[0].expressions[0].value')
VIOLATION_COUNT=$(echo "$VIOLATIONS" | jq '. | length')

if [ "$VIOLATION_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ Model passed all governance policies${NC}"
    exit 0
else
    echo -e "${RED}✗ Model failed governance check${NC}"
    echo ""
    echo "Violations:"
    echo "$VIOLATIONS" | jq -r '.[]' | while read -r msg; do
        echo -e "  ${RED}•${NC} $msg"
    done
    exit 1
fi
