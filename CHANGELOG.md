# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-01-02

### Added

#### Core Platform
- Zero-touch ML model deployment pipeline
- Policy-as-code governance with OPA/Rego
- FastAPI inference service template
- Multi-environment Kubernetes deployment

#### Governance Policies
- Model accuracy threshold (>= 0.85)
- F1 score threshold (>= 0.80)
- Fairness metrics requirement
- Demographic parity check (< 0.10)
- Drift score validation (< 0.30)
- Dependency allowlist enforcement
- Experiment tracking requirement
- Data source approval

#### GitHub Actions Workflows
- `zero-touch-deploy.yml` - Main deployment pipeline
- `model-governance.yml` - Policy validation
- `security-scan.yml` - Container and dependency scanning
- `ci.yml` - Testing and linting

#### Inference Service
- FastAPI-based prediction endpoint
- Health and readiness probes
- Prometheus metrics endpoint
- Model metadata endpoint
- PyTorch model wrapper

#### Infrastructure
- Terraform modules for AWS EKS
- Kubernetes base manifests with Kustomize
- Environment overlays (dev, staging, prod)
- Horizontal Pod Autoscaler
- Pod Disruption Budget
- Network policies
- ServiceMonitor for Prometheus

#### Security
- Multi-stage Docker builds
- Non-root container user
- Read-only filesystem
- Container vulnerability scanning (Trivy, Grype)
- Dependency scanning (pip-audit, Safety)
- Secret detection (Gitleaks)
- SAST scanning (Bandit, Semgrep)
- SBOM generation

#### Documentation
- Architecture overview
- Zero-touch workflow guide
- Model governance documentation
- Architecture Decision Records (ADRs)

### Security

- All containers run as non-root user
- Network policies restrict pod communication
- IRSA for AWS service access
- Encrypted storage (S3, EBS)

[Unreleased]: https://github.com/adamatdevops/mlifecycle-orchestrator/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/adamatdevops/mlifecycle-orchestrator/releases/tag/v1.0.0
