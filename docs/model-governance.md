# Model Governance

Policy-as-Code governance for ML model deployments using Open Policy Agent (OPA) and Rego.

## Overview

Model governance ensures all deployed models meet organizational standards for:

- **Quality**: Minimum accuracy and performance thresholds
- **Fairness**: Bias evaluation and demographic parity
- **Stability**: Drift detection and monitoring
- **Security**: Approved dependencies and data sources
- **Auditability**: Experiment tracking and lineage

## Policy Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Model Governance Layer                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Quality   │  │  Fairness   │  │  Stability  │              │
│  │   Policies  │  │  Policies   │  │  Policies   │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Security   │  │ Auditability│  │ Deployment  │              │
│  │  Policies   │  │  Policies   │  │  Policies   │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │   OPA Engine    │
                     │   (Rego Rules)  │
                     └─────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │  Allow / Deny   │
                     │   Decision      │
                     └─────────────────┘
```

## Policy Definitions

### Quality Policies

**Accuracy Threshold**
```rego
min_accuracy := 0.85

deny contains msg if {
    input.spec.metrics.accuracy < min_accuracy
    msg := sprintf(
        "Model accuracy %.2f is below minimum threshold %.2f",
        [input.spec.metrics.accuracy, min_accuracy]
    )
}
```

**F1 Score Threshold**
```rego
min_f1_score := 0.80

deny contains msg if {
    input.spec.metrics.f1_score < min_f1_score
    msg := sprintf(
        "Model F1 score %.2f is below minimum threshold %.2f",
        [input.spec.metrics.f1_score, min_f1_score]
    )
}
```

### Fairness Policies

**Fairness Metrics Required**
```rego
deny contains msg if {
    not input.spec.fairness
    msg := "Model must include fairness/bias evaluation metrics"
}
```

**Demographic Parity**
```rego
max_bias_threshold := 0.10

deny contains msg if {
    input.spec.fairness.demographic_parity > max_bias_threshold
    msg := sprintf(
        "Demographic parity %.2f exceeds acceptable threshold %.2f",
        [input.spec.fairness.demographic_parity, max_bias_threshold]
    )
}
```

### Stability Policies

**Drift Detection**
```rego
max_drift_critical := 0.30

deny contains msg if {
    input.spec.drift.score > max_drift_critical
    msg := sprintf(
        "Model drift score %.2f exceeds critical threshold",
        [input.spec.drift.score]
    )
}
```

### Security Policies

**Approved Dependencies**
```rego
approved_packages := [
    "torch",
    "numpy",
    "pandas",
    "scikit-learn",
    "transformers",
    "fastapi",
    "uvicorn"
]

deny contains msg if {
    some dep in input.spec.dependencies
    pkg := split(dep, ">=")[0]
    not pkg in approved_packages
    msg := sprintf("Unapproved dependency: %s", [pkg])
}
```

**Approved Frameworks**
```rego
approved_frameworks := ["pytorch", "tensorflow", "sklearn", "xgboost"]

deny contains msg if {
    not input.spec.model.framework in approved_frameworks
    msg := sprintf(
        "Framework %s is not approved for production",
        [input.spec.model.framework]
    )
}
```

### Auditability Policies

**Experiment Tracking**
```rego
deny contains msg if {
    not input.spec.model.experiment_id
    msg := "Model must be linked to a tracked experiment (MLflow/W&B)"
}
```

**Data Source Approval**
```rego
deny contains msg if {
    some source in input.spec.data_sources
    source.approved != true
    msg := sprintf("Data source %s is not approved", [source.name])
}
```

## Policy Thresholds

| Policy | Threshold | Rationale |
|--------|-----------|-----------|
| Accuracy | >= 0.85 | Baseline quality for production |
| F1 Score | >= 0.80 | Balanced precision and recall |
| Demographic Parity | < 0.10 | Fair treatment across groups |
| Drift Score | < 0.30 | Model stability check |

## Policy Testing

All policies have unit tests:

```bash
# Run policy tests
opa test src/policies/ -v

# Example output
src/policies/model-governance_test.rego:
data.model.governance.test_valid_model_passes: PASS
data.model.governance.test_low_accuracy_denied: PASS
data.model.governance.test_missing_fairness_denied: PASS
data.model.governance.test_high_drift_denied: PASS
```

## Validation Examples

### Valid Model

```yaml
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
```

Result: **ALLOWED**

### Invalid Model - Low Accuracy

```yaml
spec:
  metrics:
    accuracy: 0.78  # Below 0.85 threshold
    f1_score: 0.75
```

Result: **DENIED**
```
Model accuracy 0.78 is below minimum threshold 0.85
Model F1 score 0.75 is below minimum threshold 0.80
```

### Invalid Model - Missing Fairness

```yaml
spec:
  metrics:
    accuracy: 0.90
    f1_score: 0.88
  # No fairness section
```

Result: **DENIED**
```
Model must include fairness/bias evaluation metrics
```

### Invalid Model - High Drift

```yaml
spec:
  drift:
    score: 0.45  # Above 0.30 threshold
```

Result: **DENIED**
```
Model drift score 0.45 exceeds critical threshold
```

## Running Policy Validation

### Command Line

```bash
# Install OPA
curl -L -o opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64
chmod +x opa

# Validate a manifest
opa eval \
  --input examples/valid/model-manifest.yaml \
  --data src/policies/model-governance.rego \
  'data.model.governance.deny'

# Using conftest
conftest test examples/valid/model-manifest.yaml \
  --policy src/policies/
```

### GitHub Actions

```yaml
- name: Run model governance policies
  run: |
    opa eval \
      --input ${{ env.MODEL_MANIFEST }} \
      --data src/policies/model-governance.rego \
      --format pretty \
      'data.model.governance.deny'
```

## Custom Policies

Organizations can extend policies:

```rego
package model.governance.custom

import rego.v1

# Require specific model naming convention
deny contains msg if {
    not regex.match(`^[a-z]+-[a-z]+-v[0-9]+$`, input.spec.model.name)
    msg := "Model name must follow pattern: domain-task-vN"
}

# Require minimum training data size
deny contains msg if {
    input.spec.training.sample_size < 10000
    msg := "Model must be trained on at least 10,000 samples"
}
```

## Policy Governance

### Policy Updates

1. Propose policy change via PR
2. Run policy tests
3. Review with ML team
4. Merge and deploy
5. Existing models grandfathered (optional)

### Policy Exceptions

For legitimate exceptions:

```yaml
metadata:
  annotations:
    policy.mlifecycle.io/exception: "accuracy"
    policy.mlifecycle.io/exception-reason: "Experimental model for A/B test"
    policy.mlifecycle.io/exception-approver: "ml-lead@company.com"
    policy.mlifecycle.io/exception-expires: "2025-02-01"
```

## Best Practices

1. **Start Lenient**: Begin with warning-only policies
2. **Iterate**: Tighten thresholds based on data
3. **Document**: Clear rationale for each policy
4. **Test**: Comprehensive unit tests for policies
5. **Alert**: Notify teams before policy changes
6. **Audit**: Log all policy decisions
