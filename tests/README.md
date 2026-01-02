# Tests

This directory contains integration and end-to-end tests for the MLLifecycle Orchestrator platform.

## Test Structure

```
tests/
├── README.md
├── pipeline/           # Pipeline integration tests
│   ├── test_policy_validation.sh
│   └── test_workflow_execution.sh
└── integration/        # End-to-end tests
    └── test_deployment.sh
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
# Run local demo
./scripts/local-demo.sh
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
