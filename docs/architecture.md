# Architecture Overview

This document describes the architecture of the Zero-Touch ML Deployment Platform.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Zero-Touch ML Deployment                           │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Data       │     │   Policy     │     │   Build &    │     │   Deploy &   │
│   Scientist  │────▶│   Gate       │────▶│   Scan       │────▶│   Register   │
│   Push Model │     │   (OPA)      │     │   (Container)│     │   (K8s)      │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       │                    │                    │                    │
       ▼                    ▼                    ▼                    ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Model        │     │ Governance   │     │ Container    │     │ Inference    │
│ Manifest     │     │ Policies     │     │ Image        │     │ Service      │
│ (YAML)       │     │ (Rego)       │     │ (OCI)        │     │ (FastAPI)    │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

## Core Components

### 1. Model Manifest

The model manifest is a YAML file that describes a trained ML model:

```yaml
apiVersion: mlifecycle.io/v1
kind: ModelDeployment
spec:
  model:
    name: fraud-detector
    version: "2.1.0"
    framework: pytorch
  metrics:
    accuracy: 0.94
    f1_score: 0.90
  fairness:
    demographic_parity: 0.02
  drift:
    score: 0.05
```

### 2. Policy Gate (OPA/Rego)

Open Policy Agent evaluates model manifests against governance policies:

| Policy | Threshold | Purpose |
|--------|-----------|---------|
| Accuracy | >= 0.85 | Minimum model quality |
| F1 Score | >= 0.80 | Balanced precision/recall |
| Fairness | Required | Bias evaluation present |
| Drift | < 0.30 | Model stability |
| Dependencies | Allowlist | Supply chain security |

### 3. Inference Service (FastAPI)

A containerized inference service deployed automatically:

```
┌─────────────────────────────────────────┐
│           Inference Service             │
├─────────────────────────────────────────┤
│  GET  /health      Liveness check       │
│  GET  /ready       Model loaded check   │
│  POST /predict     Run inference        │
│  GET  /model/info  Model metadata       │
│  GET  /metrics     Prometheus metrics   │
└─────────────────────────────────────────┘
```

### 4. Kubernetes Infrastructure

```
┌─────────────────────────────────────────────────────────────────┐
│                        EKS Cluster                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    ml-inference namespace                 │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐          │   │
│  │  │ Deployment │  │  Service   │  │    HPA     │          │   │
│  │  │ (Pods)     │  │ (ClusterIP)│  │ (Autoscale)│          │   │
│  │  └────────────┘  └────────────┘  └────────────┘          │   │
│  │                                                           │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐          │   │
│  │  │ ConfigMap  │  │  Ingress   │  │ NetworkPol │          │   │
│  │  │ (Config)   │  │ (External) │  │ (Security) │          │   │
│  │  └────────────┘  └────────────┘  └────────────┘          │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Model Registration Flow

```
1. Data Scientist trains model
         │
         ▼
2. Generates model manifest with metrics
         │
         ▼
3. Pushes to repository (Git)
         │
         ▼
4. GitHub Actions triggered
         │
         ▼
5. OPA validates against policies
         │
         ├── FAIL: Block deployment, notify
         │
         └── PASS: Continue ──────────────┐
                                          │
6. Build container image ◀────────────────┘
         │
         ▼
7. Security scan (Trivy, Grype)
         │
         ├── Critical CVE: Block
         │
         └── Clean: Continue ─────────────┐
                                          │
8. Deploy to Kubernetes ◀─────────────────┘
         │
         ▼
9. Register in model registry
         │
         ▼
10. Notify success
```

### Inference Flow

```
Client Request                    Kubernetes Service
      │                                  │
      ▼                                  ▼
┌──────────┐    ┌──────────┐    ┌──────────────────┐
│  Client  │───▶│  Ingress │───▶│ Inference Pod(s) │
└──────────┘    └──────────┘    └──────────────────┘
                                         │
                     ┌───────────────────┴───────────────────┐
                     │                                       │
                     ▼                                       ▼
              ┌─────────────┐                       ┌─────────────┐
              │ Model Loaded│                       │  Metrics    │
              │ (PyTorch)   │                       │ (Prometheus)│
              └─────────────┘                       └─────────────┘
```

## Security Model

### Defense in Depth

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 1: Policy Gate                                            │
│   - Model quality validation                                    │
│   - Dependency allowlist                                        │
│   - Fairness requirements                                       │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: Container Security                                     │
│   - Multi-stage builds                                          │
│   - Non-root user                                               │
│   - Read-only filesystem                                        │
│   - Vulnerability scanning                                      │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3: Kubernetes Security                                    │
│   - Network policies                                            │
│   - Pod security context                                        │
│   - IRSA for AWS access                                         │
│   - Resource limits                                             │
├─────────────────────────────────────────────────────────────────┤
│ Layer 4: Infrastructure Security                                │
│   - Private subnets                                             │
│   - Encrypted storage (S3, EBS)                                 │
│   - VPC endpoints                                               │
│   - IAM least privilege                                         │
└─────────────────────────────────────────────────────────────────┘
```

### Supply Chain Security

```
Code/Model ──▶ Policy Check ──▶ SBOM Generated ──▶ Scan ──▶ Sign ──▶ Deploy
     │              │                │              │         │
     ▼              ▼                ▼              ▼         ▼
  Git Commit   OPA/Rego        Anchore/Syft    Trivy     Cosign
```

## Observability

### Metrics Pipeline

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Inference  │────▶│  Prometheus  │────▶│   Grafana    │
│   /metrics   │     │   Scrape     │     │   Dashboard  │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │ AlertManager │
                     │   Alerts     │
                     └──────────────┘
```

### Key Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `inference_requests_total` | Counter | Total inference requests |
| `inference_predictions_total` | Counter | Successful predictions |
| `inference_errors_total` | Counter | Failed predictions |
| `inference_latency_seconds` | Gauge | Average inference latency |

## Scaling Strategy

### Horizontal Pod Autoscaling

```yaml
Trigger: CPU > 70% or Memory > 80%
Min Replicas: 2 (production)
Max Replicas: 50 (production)
Scale Up: +4 pods per minute (max 100% increase)
Scale Down: -1 pod per 2 minutes
```

### Node Autoscaling

```
Cluster Autoscaler monitors pending pods
         │
         ▼
Pending pods detected (GPU workload)
         │
         ▼
Scale up inference node group (g4dn.xlarge)
         │
         ▼
Pods scheduled on new nodes
```

## Environment Strategy

| Environment | Replicas | Resources | Purpose |
|-------------|----------|-----------|---------|
| Development | 1 | 500m/512Mi | Local testing |
| Staging | 2 | 1000m/1Gi | Integration testing |
| Production | 3+ | 2000m/4Gi | Live traffic |

## Technology Stack

| Layer | Technology |
|-------|------------|
| Policy Engine | Open Policy Agent (OPA), Rego |
| ML Framework | PyTorch |
| API Framework | FastAPI, Uvicorn |
| Container | Docker, OCI |
| Orchestration | Kubernetes, Kustomize |
| Infrastructure | Terraform, AWS EKS |
| CI/CD | GitHub Actions |
| Observability | Prometheus, Grafana |
| Security | Trivy, Grype, Gitleaks |
