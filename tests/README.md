# Tests

This directory contains test configurations for the MLLifecycle Orchestrator platform.

## Test Structure

```
tests/
├── README.md           # This file
└── pipeline/           # Reserved for future pipeline tests
```

## Running Tests

### Policy Tests

```bash
# Unit tests for OPA policies
opa test src/policies/ -v
```

### Inference Service Tests

```bash
# Python unit tests
cd src/inference-service
pytest tests/ -v
```

### Local Integration

```bash
# Run local demo and policy validation
./scripts/local-demo.sh
./scripts/validate-policies.sh
```

## CI/CD Testing

Tests run automatically in GitHub Actions:

1. **CI Workflow** (`ci.yml`)
   - Python tests across versions 3.10, 3.11, 3.12
   - Linting with Ruff and Black
   - Type checking with mypy
   - OPA policy tests

2. **Model Governance** (`model-governance.yml`)
   - Policy unit tests
   - Manifest validation matrix
   - Expected pass/fail verification

3. **Security Scan** (`security-scan.yml`)
   - Dependency scanning
   - Container scanning
   - Secret detection
   - SAST analysis
