# Examples

This directory contains example model manifests for testing policy validation.

## Valid Examples

Examples that pass all governance policies:

| File | Description |
|------|-------------|
| `valid/model-manifest.yaml` | Complete, properly configured model deployment |

## Invalid Examples

Examples that fail governance policies (used for testing):

| File | Policy Violation |
|------|------------------|
| `invalid/model-no-metrics.yaml` | Missing required performance metrics |
| `invalid/model-below-accuracy.yaml` | Accuracy below 0.85 threshold |
| `invalid/model-drift-detected.yaml` | Drift score exceeds critical threshold |
| `invalid/model-bias-detected.yaml` | Fairness metrics exceed bias threshold |

## Testing

Validate manifests against policies:

```bash
# Test valid manifest (should pass)
conftest test examples/valid/model-manifest.yaml -p src/policies/

# Test invalid manifests (should fail)
conftest test examples/invalid/ -p src/policies/
```

## Sample Models

Pre-trained PyTorch models for demonstration:

```
sample-models/
└── pytorch-classifier/    # Binary classification demo model
```
