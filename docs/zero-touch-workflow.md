# Zero-Touch Deployment Workflow

This document describes how models are automatically deployed without DevOps intervention.

## Overview

The zero-touch workflow enables data scientists to deploy ML models by simply pushing a model manifest. The platform handles:

1. Policy validation
2. Container building
3. Security scanning
4. Kubernetes deployment
5. Model registration
6. Observability wiring

## Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Zero-Touch Deployment Flow                            │
└─────────────────────────────────────────────────────────────────────────────┘

    Data Scientist                    Platform                        Kubernetes
         │                               │                                │
         │  1. Push Model Manifest       │                                │
         │──────────────────────────────▶│                                │
         │                               │                                │
         │                               │  2. Detect Change              │
         │                               │  ─────────────────             │
         │                               │                                │
         │                               │  3. Policy Validation          │
         │                               │  ─────────────────────         │
         │                               │                                │
         │  4. Notify (if failed)        │                                │
         │◀──────────────────────────────│                                │
         │                               │                                │
         │                               │  5. Build Container            │
         │                               │  ─────────────────             │
         │                               │                                │
         │                               │  6. Security Scan              │
         │                               │  ───────────────               │
         │                               │                                │
         │                               │  7. Push Image                 │
         │                               │  ─────────────                 │
         │                               │                                │
         │                               │  8. Deploy                     │
         │                               │────────────────────────────────▶│
         │                               │                                │
         │                               │  9. Health Check               │
         │                               │◀────────────────────────────────│
         │                               │                                │
         │  10. Notify Success           │                                │
         │◀──────────────────────────────│                                │
         │                               │                                │
```

## Step-by-Step Process

### Step 1: Create Model Manifest

Data scientist creates a YAML manifest describing the model:

```yaml
# examples/valid/model-manifest.yaml
apiVersion: mlifecycle.io/v1
kind: ModelDeployment
metadata:
  name: fraud-detector
  namespace: ml-inference
spec:
  model:
    name: fraud-detector
    version: "2.1.0"
    uri: s3://mlifecycle-models/fraud-detector/v2.1.0
    framework: pytorch
    experiment_id: exp-fraud-2025-001
  metrics:
    accuracy: 0.94
    f1_score: 0.90
    precision: 0.92
    recall: 0.88
  fairness:
    demographic_parity: 0.02
    equalized_odds: 0.03
  drift:
    score: 0.05
    reference_date: "2025-01-01"
  dependencies:
    - torch>=2.0.0
    - numpy>=1.24.0
  data_sources:
    - source: transactions-prod
      approved: true
```

### Step 2: Push to Repository

```bash
git add examples/valid/model-manifest.yaml
git commit -m "Deploy fraud-detector v2.1.0"
git push origin main
```

### Step 3: Automatic Pipeline Trigger

GitHub Actions detects the change and starts the pipeline:

```yaml
# Triggered by
on:
  push:
    branches: [main]
    paths:
      - 'examples/valid/**'
```

### Step 4: Policy Validation

OPA evaluates the manifest against governance policies:

```bash
# Policy checks performed
✓ Accuracy >= 0.85
✓ F1 Score >= 0.80
✓ Fairness metrics present
✓ Demographic parity < 0.10
✓ Drift score < 0.30
✓ Framework approved
✓ Dependencies on allowlist
✓ Experiment tracking linked
✓ Data sources approved
```

### Step 5: Container Build

Multi-stage Docker build creates minimal production image:

```dockerfile
FROM python:3.11-slim as production
# Non-root user, read-only filesystem
USER inference
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Step 6: Security Scanning

Multiple scanners check for vulnerabilities:

| Scanner | Target | Severity |
|---------|--------|----------|
| Trivy | Container image | CRITICAL, HIGH |
| Grype | Dependencies | CRITICAL, HIGH |
| Gitleaks | Repository | Any secrets |
| Bandit | Python code | Security issues |

### Step 7: Kubernetes Deployment

Kustomize applies environment-specific configuration:

```bash
# Production deployment
kustomize build infrastructure/kubernetes/overlays/prod | kubectl apply -f -
```

Deployment includes:
- Rolling update strategy
- Health checks (liveness, readiness, startup)
- Resource limits
- HPA for autoscaling
- PDB for availability
- Network policies

### Step 8: Health Verification

Pipeline verifies deployment health:

```bash
# Health check
curl https://inference.example.com/health
# Expected: {"status": "healthy"}

# Readiness check
curl https://inference.example.com/ready
# Expected: {"status": "ready", "model": "fraud-detector", "version": "2.1.0"}
```

### Step 9: Model Registration

Model is registered in the tracking system:

```json
{
  "model_name": "fraud-detector",
  "version": "2.1.0",
  "framework": "pytorch",
  "environment": "production",
  "deployed_at": "2025-01-02T12:00:00Z",
  "endpoints": {
    "health": "/health",
    "ready": "/ready",
    "predict": "/predict",
    "metrics": "/metrics"
  }
}
```

### Step 10: Notification

Success notification sent to data scientist:

```
Model fraud-detector v2.1.0 deployed successfully

Endpoints:
- Predict: POST https://inference.example.com/predict
- Metrics: GET https://inference.example.com/metrics

Deployment Details:
- Environment: production
- Replicas: 3
- Image: ghcr.io/.../inference-service:2.1.0
```

## Failure Scenarios

### Policy Violation

```
❌ Model failed governance check

Violations:
- Model accuracy 0.78 is below minimum threshold 0.85
- Model must include fairness/bias evaluation metrics

Action Required:
1. Retrain model to improve accuracy
2. Add fairness evaluation to training pipeline
3. Update manifest with new metrics
```

### Security Vulnerability

```
❌ Security scan failed

Critical CVE detected:
- CVE-2024-XXXX in torch==1.9.0
  Severity: CRITICAL
  Fix: Upgrade to torch>=2.0.0

Action Required:
1. Update requirements.txt
2. Rebuild container
3. Re-submit deployment
```

### Deployment Failure

```
❌ Deployment health check failed

Pod Status: CrashLoopBackOff
Error: Model file not found at s3://...

Action Required:
1. Verify model URI in manifest
2. Check S3 bucket permissions
3. Ensure model artifact exists
```

## Manual Intervention Points

The workflow is zero-touch by default, but allows manual intervention:

| Trigger | Action |
|---------|--------|
| `workflow_dispatch` | Manual pipeline trigger |
| Pull Request | Validation only (no deploy) |
| Environment approval | Production gate |

## Rollback Procedure

If issues are detected post-deployment:

```bash
# Automatic rollback on health check failure
# Or manual rollback:
kubectl rollout undo deployment/inference-service -n ml-inference

# Or deploy previous version:
kubectl set image deployment/inference-service \
  inference=ghcr.io/.../inference-service:2.0.0
```

## Monitoring Post-Deployment

Grafana dashboards track:

- Request rate
- Error rate
- Latency percentiles
- Resource utilization
- Model drift (if enabled)

Alerts trigger on:
- Error rate > 5%
- Latency > 1 second
- Service unavailable > 2 minutes
- Replicas < minimum
