# ML Lifecycle Orchestrator

Zero-touch ML model deployment platform with policy-as-code governance.

[![CI](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/ci.yml/badge.svg)](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/ci.yml)
[![Model Governance](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/model-governance.yml/badge.svg)](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/model-governance.yml)
[![Security Scan](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/security-scan.yml/badge.svg)](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/security-scan.yml)
[![Zero-Touch Deploy](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/zero-touch-deploy.yml/badge.svg)](https://github.com/adamatdevops/mlifecycle-orchestrator/actions/workflows/zero-touch-deploy.yml)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![OPA](https://img.shields.io/badge/OPA-Policy--as--Code-blue)](https://www.openpolicyagent.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?logo=pytorch&logoColor=white)](https://pytorch.org/)

## Overview

Data scientists push a model manifest. The platform deploys it to production automatically.

```
Model Manifest → Policy Gate → Build → Scan → Deploy → Register
     │               │           │       │       │         │
     ▼               ▼           ▼       ▼       ▼         ▼
   YAML           OPA/Rego    Docker   Trivy   K8s     Registry
```

No DevOps tickets. No manual intervention. Full governance and auditability.

## Key Features

| Feature | Description |
|---------|-------------|
| **Zero-Touch Deploy** | Push manifest, get production endpoint |
| **Policy-as-Code** | OPA/Rego governance for quality, fairness, drift |
| **Auto-Scaling** | Kubernetes HPA based on load |
| **Security First** | Container scanning, SBOM, non-root |
| **Observability** | Prometheus metrics, Grafana dashboards |

## Quick Start

### 1. Create Model Manifest

```yaml
# examples/valid/model-manifest.yaml
apiVersion: mlifecycle.io/v1
kind: ModelDeployment
spec:
  model:
    name: fraud-detector
    version: "2.1.0"
    framework: pytorch
    experiment_id: exp-001
  metrics:
    accuracy: 0.94
    f1_score: 0.90
  fairness:
    demographic_parity: 0.02
  drift:
    score: 0.05
  dependencies:
    - torch>=2.0.0
  data_sources:
    - source: transactions-prod
      approved: true
  inference:
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2"
        memory: "4Gi"
  monitoring:
    enabled: true
```

### 2. Push to Repository

```bash
git add examples/valid/model-manifest.yaml
git commit -m "Deploy fraud-detector v2.1.0"
git push origin main
```

### 3. Automatic Deployment

The platform:
1. Validates against governance policies
2. Builds container image
3. Scans for vulnerabilities
4. Deploys to Kubernetes
5. Registers in model catalog

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   Zero-Touch ML Platform                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │
│   │   GitHub    │   │    OPA      │   │  Container  │           │
│   │   Actions   │──▶│  Policies   │──▶│   Build     │           │
│   └─────────────┘   └─────────────┘   └─────────────┘           │
│          │                                    │                  │
│          ▼                                    ▼                  │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │
│   │  Security   │   │ Kubernetes  │   │ Prometheus  │           │
│   │   Scan      │──▶│  Deploy     │──▶│  Metrics    │           │
│   └─────────────┘   └─────────────┘   └─────────────┘           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Governance Policies

Models must pass all policies before deployment:

| Policy | Threshold | Purpose |
|--------|-----------|---------|
| Accuracy | >= 0.85 | Minimum model quality |
| F1 Score | >= 0.80 | Balanced precision/recall |
| Fairness | Required | Bias evaluation present |
| Demographic Parity | < 0.10 | Fair across groups |
| Drift Score | < 0.30 | Model stability |
| Dependencies | Allowlist | Supply chain security |

### Policy Validation

```bash
# Validate model manifest
opa eval \
  --input examples/valid/model-manifest.yaml \
  --data src/policies/model-governance.rego \
  'data.model.governance.deny'
```

## Inference Service

FastAPI-based inference endpoint:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness probe |
| `/ready` | GET | Model loaded check |
| `/predict` | POST | Run inference |
| `/model/info` | GET | Model metadata |
| `/metrics` | GET | Prometheus metrics |

### Example Request

```bash
curl -X POST https://inference.example.com/predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]}'
```

### Response

```json
{
  "predictions": [
    {
      "prediction": 1,
      "confidence": 0.92,
      "probabilities": [0.08, 0.92]
    }
  ],
  "model_name": "fraud-detector",
  "model_version": "2.1.0",
  "inference_time_ms": 12.5
}
```

## Project Structure

```
mlifecycle-orchestrator/
├── .github/workflows/       # CI/CD pipelines
│   ├── zero-touch-deploy.yml
│   ├── model-governance.yml
│   ├── security-scan.yml
│   └── ci.yml
├── src/
│   ├── policies/            # OPA/Rego governance
│   │   ├── model-governance.rego
│   │   └── deployment-policy.rego
│   └── inference-service/   # FastAPI inference
│       ├── app/main.py
│       ├── Dockerfile
│       └── tests/
├── infrastructure/
│   ├── terraform/           # AWS EKS infrastructure
│   └── kubernetes/          # K8s manifests
│       ├── base/
│       └── overlays/
├── examples/
│   ├── valid/               # Valid model manifests
│   └── invalid/             # Policy violation examples
└── docs/
    ├── architecture.md
    ├── zero-touch-workflow.md
    ├── model-governance.md
    └── adr/
```

## Local Development

### Prerequisites

- Python 3.11+
- Docker
- OPA CLI
- kubectl (optional)

### Run Inference Service

```bash
cd src/inference-service
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### Run Policy Tests

```bash
# Install OPA
brew install opa  # macOS
# or download from https://www.openpolicyagent.org/

# Run tests
opa test src/policies/ -v
```

### Build Container

```bash
cd src/inference-service
docker build -t inference-service:local .
docker run -p 8080:8080 inference-service:local
```

## Infrastructure

### Terraform

```bash
cd infrastructure/terraform
terraform init
terraform plan -var="environment=dev"
terraform apply -var="environment=dev"
```

### Kubernetes

```bash
# Deploy to staging
kustomize build infrastructure/kubernetes/overlays/staging | kubectl apply -f -

# Deploy to production
kustomize build infrastructure/kubernetes/overlays/prod | kubectl apply -f -
```

## Security

- **Container**: Multi-stage build, non-root user, read-only filesystem
- **Scanning**: Trivy, Grype, Gitleaks, Bandit
- **Network**: Kubernetes NetworkPolicy
- **Access**: IRSA for AWS, minimal permissions
- **Supply Chain**: SBOM generation, dependency allowlist

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Zero-Touch Workflow](docs/zero-touch-workflow.md)
- [Model Governance](docs/model-governance.md)
- [ADR: GitHub Actions](docs/adr/0001-github-actions-orchestration.md)
- [ADR: OPA Governance](docs/adr/0002-opa-model-governance.md)
- [ADR: FastAPI Service](docs/adr/0003-fastapi-inference-service.md)
- [ADR: Kubernetes](docs/adr/0004-kubernetes-deployment.md)

## Technology Stack

| Layer | Technology |
|-------|------------|
| Policy Engine | Open Policy Agent, Rego |
| ML Framework | PyTorch |
| API Framework | FastAPI, Uvicorn |
| Container | Docker, OCI |
| Orchestration | Kubernetes, Kustomize |
| Infrastructure | Terraform, AWS EKS |
| CI/CD | GitHub Actions |
| Observability | Prometheus, Grafana |
| Security | Trivy, Grype, Gitleaks |

## License

MIT License - see [LICENSE](LICENSE) for details.
