# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2025-01-03

### Added

- Status badges for code quality tools (Ruff, Black)
- Status badges for security scanners (Trivy, Grype, Gitleaks, Hadolint, Docker)
- Monitoring requirements validation in governance policies
- Explainability requirements validation in governance policies
- Semantic versioning validation for model versions
- Disk space cleanup step before container scanning
- Python version matrix testing (3.10, 3.11, 3.12)

### Changed

- Black and isort checks are now non-blocking (warnings instead of failures)
- Container build uses CPU-only PyTorch for significantly smaller images (~500MB vs ~2GB)
- Pinned Trivy action to v0.28.0 for stability
- Container build timeout increased to 30 minutes
- Prometheus metrics standardized to `inference_request_duration_seconds` histogram

### Fixed

- Security-events permission for SARIF upload in zero-touch-deploy workflow
- Trivy image reference format (single tag instead of multiline)
- Hadolint warnings in Dockerfile (DL3008, DL3013)
- ServiceMonitor namespace selector alignment
- Terraform security defaults (encryption, public access blocks)
- Policy tests aligned with governance requirements
- pytest PYTHONPATH configuration for test discovery
- Ruff linting errors (unused imports)

### Security

- Added `security-events: write` permission for vulnerability reporting
- Enhanced container scanning with proper SARIF upload
- Improved secret scanning with Gitleaks integration

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

[Unreleased]: https://github.com/adamatdevops/mlifecycle-orchestrator/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/adamatdevops/mlifecycle-orchestrator/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/adamatdevops/mlifecycle-orchestrator/releases/tag/v1.0.0
