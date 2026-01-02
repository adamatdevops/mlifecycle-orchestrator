#!/bin/bash
# =============================================================================
# Local Demo Script
# =============================================================================
# Demonstrates the zero-touch ML deployment workflow locally.
#
# Usage: ./scripts/local-demo.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Zero-Touch ML Deployment Platform - Local Demo       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Check Prerequisites
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Step 1: Checking prerequisites...${NC}"

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}✗ $1 is not installed${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $1 is installed${NC}"
        return 0
    fi
}

PREREQS_OK=true
check_command "docker" || PREREQS_OK=false
check_command "python3" || PREREQS_OK=false

# OPA is optional for demo
if command -v opa &> /dev/null; then
    echo -e "${GREEN}✓ opa is installed${NC}"
    HAS_OPA=true
else
    echo -e "${YELLOW}⚠ opa is not installed (policy tests will be skipped)${NC}"
    HAS_OPA=false
fi

if [ "$PREREQS_OK" = false ]; then
    echo -e "${RED}Please install missing prerequisites and try again.${NC}"
    exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# Step 2: Validate Model Manifests (if OPA installed)
# -----------------------------------------------------------------------------
if [ "$HAS_OPA" = true ]; then
    echo -e "${YELLOW}Step 2: Running policy validation...${NC}"

    echo -e "${BLUE}Testing valid model manifest...${NC}"
    VIOLATIONS=$(opa eval \
        --input "$PROJECT_ROOT/examples/valid/model-manifest.yaml" \
        --data "$PROJECT_ROOT/src/policies/model-governance.rego" \
        --format json \
        'data.model.governance.deny' 2>/dev/null | jq -r '.result[0].expressions[0].value | length')

    if [ "$VIOLATIONS" -eq 0 ]; then
        echo -e "${GREEN}✓ Valid manifest passed all policies${NC}"
    else
        echo -e "${RED}✗ Valid manifest failed (unexpected)${NC}"
    fi

    echo -e "${BLUE}Testing invalid model manifest (low accuracy)...${NC}"
    VIOLATIONS=$(opa eval \
        --input "$PROJECT_ROOT/examples/invalid/model-below-accuracy.yaml" \
        --data "$PROJECT_ROOT/src/policies/model-governance.rego" \
        --format json \
        'data.model.governance.deny' 2>/dev/null | jq -r '.result[0].expressions[0].value | length')

    if [ "$VIOLATIONS" -gt 0 ]; then
        echo -e "${GREEN}✓ Invalid manifest correctly rejected${NC}"
    else
        echo -e "${RED}✗ Invalid manifest should have been rejected${NC}"
    fi
    echo ""
else
    echo -e "${YELLOW}Step 2: Skipping policy validation (OPA not installed)${NC}"
    echo ""
fi

# -----------------------------------------------------------------------------
# Step 3: Build Inference Service Container
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Step 3: Building inference service container...${NC}"

cd "$PROJECT_ROOT/src/inference-service"
docker build -t inference-service:demo . --quiet
echo -e "${GREEN}✓ Container built successfully${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 4: Run Inference Service
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Step 4: Starting inference service...${NC}"

# Stop any existing container
docker rm -f inference-demo 2>/dev/null || true

# Run container
docker run -d \
    --name inference-demo \
    -p 8080:8080 \
    -e MODEL_NAME=demo-model \
    -e MODEL_VERSION=1.0.0 \
    -e LOG_LEVEL=INFO \
    inference-service:demo

echo -e "${BLUE}Waiting for service to start...${NC}"
sleep 5
echo ""

# -----------------------------------------------------------------------------
# Step 5: Test Endpoints
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Step 5: Testing inference endpoints...${NC}"

echo -e "${BLUE}Testing /health endpoint...${NC}"
HEALTH=$(curl -s http://localhost:8080/health)
echo "Response: $HEALTH"
if echo "$HEALTH" | grep -q "healthy"; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
fi
echo ""

echo -e "${BLUE}Testing /ready endpoint...${NC}"
READY=$(curl -s http://localhost:8080/ready)
echo "Response: $READY"
if echo "$READY" | grep -q "ready"; then
    echo -e "${GREEN}✓ Readiness check passed${NC}"
else
    echo -e "${RED}✗ Readiness check failed${NC}"
fi
echo ""

echo -e "${BLUE}Testing /predict endpoint...${NC}"
PREDICT=$(curl -s -X POST http://localhost:8080/predict \
    -H "Content-Type: application/json" \
    -d '{"instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]}')
echo "Response: $PREDICT"
if echo "$PREDICT" | grep -q "predictions"; then
    echo -e "${GREEN}✓ Prediction successful${NC}"
else
    echo -e "${RED}✗ Prediction failed${NC}"
fi
echo ""

echo -e "${BLUE}Testing /model/info endpoint...${NC}"
INFO=$(curl -s http://localhost:8080/model/info)
echo "Response: $INFO"
if echo "$INFO" | grep -q "demo-model"; then
    echo -e "${GREEN}✓ Model info retrieved${NC}"
else
    echo -e "${RED}✗ Model info failed${NC}"
fi
echo ""

echo -e "${BLUE}Testing /metrics endpoint...${NC}"
METRICS=$(curl -s http://localhost:8080/metrics)
if echo "$METRICS" | grep -q "inference_requests_total"; then
    echo -e "${GREEN}✓ Metrics available${NC}"
else
    echo -e "${RED}✗ Metrics failed${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# Step 6: Cleanup
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Step 6: Cleaning up...${NC}"
docker stop inference-demo >/dev/null
docker rm inference-demo >/dev/null
echo -e "${GREEN}✓ Container stopped and removed${NC}"
echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                      Demo Complete!                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "The zero-touch ML deployment platform demonstrated:"
echo "  1. Policy-as-code validation with OPA"
echo "  2. Container build for inference service"
echo "  3. Health and readiness endpoints"
echo "  4. Prediction endpoint with model inference"
echo "  5. Prometheus metrics exposure"
echo ""
echo "For full deployment, see: docs/zero-touch-workflow.md"
