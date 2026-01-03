# Contributing to ML Lifecycle Orchestrator

This document outlines the development workflow, standards, and expectations for contributing to this repository.

---

## Development Workflow

### Branch Strategy

This repository uses **trunk-based development**:

```
main (protected)
  └── feature/description
  └── fix/description
  └── docs/description
```

- `main` is always deployable
- All changes go through pull requests
- Branch lifetime should be < 1 day when possible

### Branch Naming

```
<type>/<short-description>

Examples:
  feature/add-model-versioning
  fix/trivy-scan-timeout
  docs/update-governance-policies
```

Types: `feature`, `fix`, `docs`, `refactor`, `test`

---

## Commit Message Guidelines

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Examples

```
feat(inference): add batch prediction endpoint

Adds /predict/batch endpoint for processing multiple instances.
Includes request validation and async processing support.

Refs: #42
```

```
fix(governance): update accuracy threshold validation

Corrects policy to properly validate accuracy >= 0.85
```

```
docs(adr): add decision record for PyTorch selection
```

### Type Reference

| Type | Description |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes nor adds |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks |
| `security` | Security-related changes |

---

## Pull Request Expectations

### Before Opening PR

- [ ] All pipelines pass locally
- [ ] No secrets or credentials in code
- [ ] Documentation updated if needed
- [ ] ADR created for significant decisions
- [ ] Code formatted with Black and isort

### PR Description Template

```markdown
## Summary
Brief description of what this PR does.

## Type of Change
- [ ] Feature
- [ ] Bug fix
- [ ] Documentation
- [ ] Refactor

## Security Considerations
Describe any security implications of this change.

## Testing
How was this tested?

## Checklist
- [ ] Pipelines pass
- [ ] No secrets in code
- [ ] Docs updated
```

### Review Process

1. Automated checks must pass
2. At least one approval required
3. Security-sensitive changes require security review
4. Squash merge preferred

---

## Code Style Expectations

### Python (Inference Service)

- Format with Black
- Sort imports with isort
- Lint with Ruff
- Type hints encouraged

```python
# Good
from typing import List

from fastapi import FastAPI
from pydantic import BaseModel


class PredictRequest(BaseModel):
    """Request model for predictions."""

    instances: List[List[float]]
```

### YAML (Workflows)

- 2-space indentation
- Explicit quotes for strings that could be interpreted as other types
- Comments for non-obvious steps

```yaml
# Good
name: Zero-Touch Deploy
on:
  push:
    branches: ["main"]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
```

### Rego (Policies)

- One rule per concern
- Clear deny messages
- Unit tests for all policies

```rego
# Good - clear and testable
package model.governance

deny[msg] {
    input.spec.metrics.accuracy < 0.85
    msg := "Model accuracy must be >= 0.85"
}
```

---

## Security & Confidentiality Rules

### Never Commit

- Secrets, tokens, or API keys
- Real model weights or training data
- Internal company configurations
- Production domain names or IPs
- Customer or user data

### Always Use

- Generic placeholder values (`example.com`)
- Synthetic test data
- Anonymized examples

### If Unsure

Ask before committing. When in doubt, leave it out.

---

## Testing & Validation

### Local Testing

Before pushing, run:

```bash
# Python tests
cd src/inference-service
pytest tests/ -v

# Lint Python code
ruff check src/inference-service/app/
black --check src/inference-service/app/

# Test Rego policies
opa test src/policies/ -v

# Build container
docker build -t inference-service:local src/inference-service/
```

### CI Validation

All PRs automatically run:

- Python tests (3.10, 3.11, 3.12)
- Ruff linting
- Black formatting check
- isort import check
- mypy type checking
- OPA policy tests

---

## Documentation Standards

### When to Update Docs

- Any new feature or capability
- Changed behavior
- New configuration options
- Architecture decisions (ADR)

### Documentation Locations

| Content | Location |
|---------|----------|
| High-level overview | `README.md` |
| Architecture details | `docs/architecture.md` |
| Decisions | `docs/adr/` |
| Governance policies | `docs/model-governance.md` |
| Zero-touch workflow | `docs/zero-touch-workflow.md` |

---

## Architecture Decision Records (ADRs)

For significant decisions, create an ADR:

```
docs/adr/
  0001-github-actions-orchestration.md
  0002-opa-model-governance.md
  0003-fastapi-inference-service.md
  0004-kubernetes-deployment.md
```

### ADR Template

```markdown
# ADR-XXXX: Title

## Status
Proposed | Accepted | Deprecated | Superseded

## Context
What is the issue we're addressing?

## Decision
What did we decide?

## Alternatives Considered
What else did we evaluate?

## Consequences
What are the implications?
```

---

## Project Structure

```
mlifecycle-orchestrator/
├── .github/workflows/       # CI/CD pipelines
├── src/
│   ├── policies/            # OPA/Rego governance
│   └── inference-service/   # FastAPI inference
├── infrastructure/
│   ├── terraform/           # AWS EKS infrastructure
│   └── kubernetes/          # K8s manifests
├── examples/                # Model manifest examples
└── docs/                    # Documentation
```

---

## Questions?

Open an issue for:

- Clarification on standards
- Suggestions for improvement
- Security concerns
