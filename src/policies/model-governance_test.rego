# =============================================================================
# Model Governance Policy - Unit Tests
# =============================================================================
# Run: opa test src/policies/ -v
# =============================================================================

package model.governance_test

import data.model.governance
import rego.v1

# -----------------------------------------------------------------------------
# Test Data: Valid Model
# -----------------------------------------------------------------------------

valid_model := {
    "apiVersion": "mlifecycle.io/v1",
    "kind": "ModelDeployment",
    "spec": {
        "model": {
            "name": "fraud-detector",
            "version": "2.1.0",
            "uri": "s3://model-bucket/fraud-detector/v2.1.0",
            "framework": "pytorch",
            "experiment_id": "exp-abc123"
        },
        "metrics": {
            "accuracy": 0.94,
            "f1_score": 0.90,
            "precision": 0.91,
            "recall": 0.89
        },
        "fairness": {
            "demographic_parity": 0.02,
            "equalized_odds": 0.03
        },
        "drift": {
            "score": 0.05
        },
        "dependencies": [
            "torch>=2.0.0",
            "numpy>=1.24.0",
            "pandas>=2.0.0"
        ],
        "data_sources": [
            {"source": "transactions-prod", "approved": true}
        ],
        "inference": {
            "replicas": 2,
            "resources": {
                "requests": {"cpu": "500m", "memory": "1Gi"},
                "limits": {"cpu": "2", "memory": "4Gi"}
            },
            "autoscaling": {
                "minReplicas": 2,
                "maxReplicas": 10
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Test: Valid Model Should Pass
# -----------------------------------------------------------------------------

test_valid_model_allowed if {
    governance.allow with input as valid_model
}

test_valid_model_no_denies if {
    count(governance.deny) == 0 with input as valid_model
}

# -----------------------------------------------------------------------------
# Test: Accuracy Threshold
# -----------------------------------------------------------------------------

test_deny_low_accuracy if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/metrics/accuracy", "value": 0.80}])
    "Model accuracy 0.80 is below minimum threshold 0.85" in governance.deny with input as model
}

test_allow_minimum_accuracy if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/metrics/accuracy", "value": 0.85}])
    governance.allow with input as model
}

# -----------------------------------------------------------------------------
# Test: F1 Score Threshold
# -----------------------------------------------------------------------------

test_deny_low_f1_score if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/metrics/f1_score", "value": 0.75}])
    "Model F1 score 0.75 is below minimum threshold 0.80" in governance.deny with input as model
}

# -----------------------------------------------------------------------------
# Test: Missing Metrics
# -----------------------------------------------------------------------------

test_deny_missing_metrics if {
    model := json.remove(valid_model, ["/spec/metrics"])
    "Model manifest must include performance metrics (accuracy, f1_score)" in governance.deny with input as model
}

test_deny_missing_accuracy if {
    model := json.remove(valid_model, ["/spec/metrics/accuracy"])
    "Model must have accuracy metric defined" in governance.deny with input as model
}

# -----------------------------------------------------------------------------
# Test: Fairness Requirements
# -----------------------------------------------------------------------------

test_deny_missing_fairness if {
    model := json.remove(valid_model, ["/spec/fairness"])
    "Model must include fairness/bias evaluation metrics" in governance.deny with input as model
}

test_deny_high_demographic_parity if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/fairness/demographic_parity", "value": 0.15}])
    count([m | m := governance.deny[_]; contains(m, "Demographic parity")]) > 0 with input as model
}

test_deny_high_equalized_odds if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/fairness/equalized_odds", "value": 0.12}])
    count([m | m := governance.deny[_]; contains(m, "Equalized odds")]) > 0 with input as model
}

# -----------------------------------------------------------------------------
# Test: Drift Detection
# -----------------------------------------------------------------------------

test_warn_moderate_drift if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/drift/score", "value": 0.15}])
    count([m | m := governance.warn[_]; contains(m, "drift score")]) > 0 with input as model
}

test_deny_critical_drift if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/drift/score", "value": 0.35}])
    count([m | m := governance.deny[_]; contains(m, "drift score")]) > 0 with input as model
}

test_no_drift_warning_below_threshold if {
    count(governance.warn) == 0 with input as valid_model
}

# -----------------------------------------------------------------------------
# Test: Framework Validation
# -----------------------------------------------------------------------------

test_deny_unapproved_framework if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/model/framework", "value": "custom-ml"}])
    count([m | m := governance.deny[_]; contains(m, "not approved")]) > 0 with input as model
}

test_allow_sklearn_framework if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/model/framework", "value": "sklearn"}])
    governance.allow with input as model
}

test_allow_tensorflow_framework if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/model/framework", "value": "tensorflow"}])
    governance.allow with input as model
}

# -----------------------------------------------------------------------------
# Test: Dependency Validation
# -----------------------------------------------------------------------------

test_deny_unapproved_dependency if {
    model := json.patch(valid_model, [{"op": "add", "path": "/spec/dependencies/-", "value": "malicious-package>=1.0.0"}])
    count([m | m := governance.deny[_]; contains(m, "not in approved packages")]) > 0 with input as model
}

test_allow_approved_dependencies if {
    governance.allow with input as valid_model
}

# -----------------------------------------------------------------------------
# Test: Data Source Validation
# -----------------------------------------------------------------------------

test_deny_missing_data_sources if {
    model := json.remove(valid_model, ["/spec/data_sources"])
    "Model must declare data sources for lineage tracking" in governance.deny with input as model
}

test_deny_unapproved_data_source if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/data_sources", "value": [{"source": "unknown-bucket", "approved": false}]}])
    count([m | m := governance.deny[_]; contains(m, "not from an approved source")]) > 0 with input as model
}

# -----------------------------------------------------------------------------
# Test: Experiment Tracking
# -----------------------------------------------------------------------------

test_deny_missing_experiment_id if {
    model := json.remove(valid_model, ["/spec/model/experiment_id"])
    "Model must be linked to an MLflow experiment (experiment_id required)" in governance.deny with input as model
}

test_deny_empty_experiment_id if {
    model := json.patch(valid_model, [{"op": "replace", "path": "/spec/model/experiment_id", "value": ""}])
    "Model experiment_id cannot be empty" in governance.deny with input as model
}

# -----------------------------------------------------------------------------
# Test: Resource Requirements
# -----------------------------------------------------------------------------

test_deny_missing_resources if {
    model := json.remove(valid_model, ["/spec/inference/resources"])
    "Inference configuration must include resource requests/limits" in governance.deny with input as model
}

test_deny_missing_memory_limits if {
    model := json.remove(valid_model, ["/spec/inference/resources/limits/memory"])
    "Inference deployment must have memory limits defined" in governance.deny with input as model
}

test_warn_missing_autoscaling if {
    model := json.remove(valid_model, ["/spec/inference/autoscaling"])
    count([m | m := governance.warn[_]; contains(m, "autoscaling")]) > 0 with input as model
}
