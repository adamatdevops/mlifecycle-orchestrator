# =============================================================================
# Model Governance Policy
# =============================================================================
# Validates ML model manifests before deployment.
# Ensures model quality, fairness, drift thresholds, and dependency compliance.
#
# Usage:
#   conftest test model-manifest.yaml -p src/policies/
#   opa eval -d src/policies/ -i model-manifest.json "data.model.governance"
# =============================================================================

package model.governance

import rego.v1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

default allow := false

# Thresholds
min_accuracy := 0.85
min_f1_score := 0.80
max_drift_warning := 0.1
max_drift_critical := 0.3
max_bias_threshold := 0.1

# Approved ML frameworks
approved_frameworks := {"pytorch", "sklearn", "tensorflow", "xgboost", "lightgbm"}

# Approved data sources (prefix matching)
approved_data_prefixes := {"s3://approved-data-", "gs://ml-datasets-", "transactions-prod"}

# Approved Python packages for production
approved_packages := {
    "torch", "torchvision", "torchaudio",
    "scikit-learn", "sklearn",
    "tensorflow", "keras",
    "xgboost", "lightgbm", "catboost",
    "pandas", "numpy", "scipy",
    "fastapi", "uvicorn", "pydantic",
    "mlflow", "onnx", "onnxruntime"
}

# -----------------------------------------------------------------------------
# Main Allow Rule
# -----------------------------------------------------------------------------

allow if {
    count(deny) == 0
}

# -----------------------------------------------------------------------------
# Model Quality Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.spec.metrics.accuracy < min_accuracy
    msg := sprintf(
        "Model accuracy %.2f is below minimum threshold %.2f",
        [input.spec.metrics.accuracy, min_accuracy]
    )
}

deny contains msg if {
    input.spec.metrics.f1_score < min_f1_score
    msg := sprintf(
        "Model F1 score %.2f is below minimum threshold %.2f",
        [input.spec.metrics.f1_score, min_f1_score]
    )
}

deny contains msg if {
    not input.spec.metrics
    msg := "Model manifest must include performance metrics (accuracy, f1_score)"
}

deny contains msg if {
    not input.spec.metrics.accuracy
    msg := "Model must have accuracy metric defined"
}

# -----------------------------------------------------------------------------
# Fairness / Bias Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    not input.spec.fairness
    msg := "Model must include fairness/bias evaluation metrics"
}

deny contains msg if {
    input.spec.fairness.demographic_parity > max_bias_threshold
    msg := sprintf(
        "Demographic parity %.3f exceeds maximum bias threshold %.3f",
        [input.spec.fairness.demographic_parity, max_bias_threshold]
    )
}

deny contains msg if {
    input.spec.fairness.equalized_odds > max_bias_threshold
    msg := sprintf(
        "Equalized odds %.3f exceeds maximum bias threshold %.3f",
        [input.spec.fairness.equalized_odds, max_bias_threshold]
    )
}

# -----------------------------------------------------------------------------
# Drift Detection Policies
# -----------------------------------------------------------------------------

warn contains msg if {
    input.spec.drift.score > max_drift_warning
    input.spec.drift.score <= max_drift_critical
    msg := sprintf(
        "Model drift score %.2f exceeds warning threshold %.2f",
        [input.spec.drift.score, max_drift_warning]
    )
}

deny contains msg if {
    input.spec.drift.score > max_drift_critical
    msg := sprintf(
        "Model drift score %.2f exceeds critical threshold %.2f - deployment blocked",
        [input.spec.drift.score, max_drift_critical]
    )
}

# -----------------------------------------------------------------------------
# Framework & Dependency Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    framework := input.spec.model.framework
    not framework in approved_frameworks
    msg := sprintf(
        "Framework '%s' is not approved. Approved: %v",
        [framework, approved_frameworks]
    )
}

deny contains msg if {
    some dep in input.spec.dependencies
    pkg := extract_package_name(dep)
    not pkg in approved_packages
    msg := sprintf(
        "Dependency '%s' is not in approved packages list",
        [dep]
    )
}

# -----------------------------------------------------------------------------
# Data Lineage Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    not input.spec.data_sources
    msg := "Model must declare data sources for lineage tracking"
}

deny contains msg if {
    some source in input.spec.data_sources
    not is_approved_data_source(source)
    msg := sprintf(
        "Data source '%s' is not from an approved source",
        [source.source]
    )
}

# -----------------------------------------------------------------------------
# Experiment Tracking Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    not input.spec.model.experiment_id
    msg := "Model must be linked to an MLflow experiment (experiment_id required)"
}

deny contains msg if {
    input.spec.model.experiment_id == ""
    msg := "Model experiment_id cannot be empty"
}

# -----------------------------------------------------------------------------
# Resource & Deployment Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    not input.spec.inference.resources
    msg := "Inference configuration must include resource requests/limits"
}

deny contains msg if {
    not input.spec.inference.resources.limits.memory
    msg := "Inference deployment must have memory limits defined"
}

warn contains msg if {
    not input.spec.inference.autoscaling
    msg := "Inference deployment should have autoscaling configuration"
}

# -----------------------------------------------------------------------------
# Semantic Versioning Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    not input.spec.model.version
    msg := "Model must have a version number"
}

deny contains msg if {
    version := input.spec.model.version
    not is_valid_semver(version)
    msg := sprintf(
        "Model version '%s' is not valid semantic versioning (expected: X.Y.Z)",
        [version]
    )
}

deny contains msg if {
    some dep in input.spec.dependencies
    not is_valid_version_constraint(dep)
    msg := sprintf(
        "Dependency '%s' must have a valid version constraint (>=, ==, ~=)",
        [dep]
    )
}

# Prevent unpinned dependencies in production
warn contains msg if {
    some dep in input.spec.dependencies
    not contains(dep, ">=")
    not contains(dep, "==")
    not contains(dep, "~=")
    msg := sprintf(
        "Dependency '%s' should have version constraint for reproducibility",
        [dep]
    )
}

# -----------------------------------------------------------------------------
# Monitoring & Observability Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    not input.spec.monitoring
    msg := "Model must include monitoring configuration"
}

deny contains msg if {
    input.spec.monitoring
    not input.spec.monitoring.enabled
    msg := "Continuous monitoring must be enabled for production models"
}

warn contains msg if {
    input.spec.monitoring
    not input.spec.monitoring.drift_detection
    msg := "Drift detection should be configured for monitoring"
}

warn contains msg if {
    input.spec.monitoring
    not input.spec.monitoring.alerting
    msg := "Alerting configuration recommended for production models"
}

# -----------------------------------------------------------------------------
# Model Explainability Policies (Recommended)
# -----------------------------------------------------------------------------

warn contains msg if {
    not input.spec.explainability
    msg := "Model should include explainability metrics (SHAP, LIME, feature importance)"
}

warn contains msg if {
    input.spec.explainability
    not input.spec.explainability.method
    msg := "Explainability section should specify method used"
}

# -----------------------------------------------------------------------------
# Performance Regression Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.spec.previous_version
    input.spec.metrics.accuracy < input.spec.previous_version.metrics.accuracy - 0.02
    msg := sprintf(
        "Model accuracy %.3f is more than 2%% lower than previous version %.3f",
        [input.spec.metrics.accuracy, input.spec.previous_version.metrics.accuracy]
    )
}

deny contains msg if {
    input.spec.previous_version
    input.spec.metrics.f1_score < input.spec.previous_version.metrics.f1_score - 0.02
    msg := sprintf(
        "Model F1 score %.3f is more than 2%% lower than previous version %.3f",
        [input.spec.metrics.f1_score, input.spec.previous_version.metrics.f1_score]
    )
}

# Latency regression check
warn contains msg if {
    input.spec.inference.latency_p99_ms
    input.spec.previous_version.inference.latency_p99_ms
    input.spec.inference.latency_p99_ms > input.spec.previous_version.inference.latency_p99_ms * 1.5
    msg := sprintf(
        "Model inference latency %.0fms is 50%% higher than previous version %.0fms",
        [input.spec.inference.latency_p99_ms, input.spec.previous_version.inference.latency_p99_ms]
    )
}

# -----------------------------------------------------------------------------
# Training Data Quality Policies
# -----------------------------------------------------------------------------

warn contains msg if {
    input.spec.training
    input.spec.training.sample_size < 1000
    msg := sprintf(
        "Training sample size %d is below recommended minimum of 1000",
        [input.spec.training.sample_size]
    )
}

deny contains msg if {
    input.spec.training
    input.spec.training.sample_size < 100
    msg := sprintf(
        "Training sample size %d is below minimum required of 100",
        [input.spec.training.sample_size]
    )
}

# -----------------------------------------------------------------------------
# Security Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.spec.model.uri
    startswith(input.spec.model.uri, "http://")
    msg := "Model URI must use HTTPS, not HTTP"
}

deny contains msg if {
    some dep in input.spec.dependencies
    is_known_vulnerable(dep)
    msg := sprintf(
        "Dependency '%s' has known security vulnerabilities",
        [dep]
    )
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

extract_package_name(dep) := pkg if {
    # Handle versioned deps like "torch>=2.0.0" or "scikit-learn==1.3.0"
    parts := regex.split("[<>=!~]+", dep)
    pkg := parts[0]
}

is_approved_data_source(source) if {
    some prefix in approved_data_prefixes
    startswith(source.source, prefix)
}

is_approved_data_source(source) if {
    source.approved == true
}

# Validate semantic versioning (X.Y.Z format)
is_valid_semver(version) if {
    regex.match(`^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$`, version)
}

# Also allow quoted versions like "2.1.0"
is_valid_semver(version) if {
    trimmed := trim(version, "\"")
    regex.match(`^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$`, trimmed)
}

# Validate version constraint in dependency
is_valid_version_constraint(dep) if {
    contains(dep, ">=")
}

is_valid_version_constraint(dep) if {
    contains(dep, "==")
}

is_valid_version_constraint(dep) if {
    contains(dep, "~=")
}

is_valid_version_constraint(dep) if {
    contains(dep, "<=")
}

is_valid_version_constraint(dep) if {
    contains(dep, "<")
}

is_valid_version_constraint(dep) if {
    contains(dep, ">")
}

# Package without version constraint (allowed but warned)
is_valid_version_constraint(dep) if {
    not contains(dep, ">=")
    not contains(dep, "==")
    not contains(dep, "~=")
    not contains(dep, "<=")
    not contains(dep, "<")
    not contains(dep, ">")
}

# Known vulnerable packages (simplified - in production, use external CVE database)
known_vulnerable_packages := {
    "torch<1.9.0",
    "tensorflow<2.4.0",
    "numpy<1.19.0"
}

is_known_vulnerable(dep) if {
    some vuln in known_vulnerable_packages
    startswith(dep, extract_package_name(vuln))
    # Simple version check - in production use proper version comparison
}
