# =============================================================================
# Kubernetes Deployment Policy for ML Inference Services
# =============================================================================
# Validates Kubernetes deployment manifests for inference services.
# Ensures security best practices, resource limits, and observability.
#
# Usage:
#   conftest test deployment.yaml -p src/policies/
# =============================================================================

package kubernetes.deployment

import rego.v1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

default allow := false

# Required labels for inference deployments
required_labels := {"app", "version", "team"}

# Approved container registries
approved_registries := {
    "ghcr.io/",
    "gcr.io/",
    ".dkr.ecr.",
    "docker.io/library/"
}

# -----------------------------------------------------------------------------
# Main Allow Rule
# -----------------------------------------------------------------------------

allow if {
    count(deny) == 0
}

# -----------------------------------------------------------------------------
# Security Context Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    container.securityContext.privileged == true
    msg := sprintf("Container '%s' must not run in privileged mode", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    not input.spec.template.spec.securityContext.runAsNonRoot
    msg := "Deployment must set runAsNonRoot: true in pod security context"
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    container.securityContext.allowPrivilegeEscalation == true
    msg := sprintf("Container '%s' must not allow privilege escalation", [container.name])
}

warn contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.securityContext.readOnlyRootFilesystem
    msg := sprintf("Container '%s' should use read-only root filesystem", [container.name])
}

# -----------------------------------------------------------------------------
# Resource Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.resources.limits.memory
    msg := sprintf("Container '%s' must have memory limits defined", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.resources.limits.cpu
    msg := sprintf("Container '%s' must have CPU limits defined", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.resources.requests.memory
    msg := sprintf("Container '%s' must have memory requests defined", [container.name])
}

# -----------------------------------------------------------------------------
# Health Check Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.livenessProbe
    msg := sprintf("Container '%s' must have a liveness probe", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not container.readinessProbe
    msg := sprintf("Container '%s' must have a readiness probe", [container.name])
}

# -----------------------------------------------------------------------------
# Image Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    endswith(container.image, ":latest")
    msg := sprintf("Container '%s' must not use :latest tag", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not contains(container.image, ":")
    msg := sprintf("Container '%s' must specify an image tag", [container.name])
}

deny contains msg if {
    input.kind == "Deployment"
    some container in input.spec.template.spec.containers
    not is_approved_registry(container.image)
    msg := sprintf("Container '%s' image must be from an approved registry", [container.name])
}

# -----------------------------------------------------------------------------
# Label Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.kind == "Deployment"
    some label in required_labels
    not input.metadata.labels[label]
    msg := sprintf("Deployment must have label '%s'", [label])
}

deny contains msg if {
    input.kind == "Deployment"
    some label in required_labels
    not input.spec.template.metadata.labels[label]
    msg := sprintf("Pod template must have label '%s'", [label])
}

# -----------------------------------------------------------------------------
# Replica Policies
# -----------------------------------------------------------------------------

warn contains msg if {
    input.kind == "Deployment"
    input.spec.replicas < 2
    msg := "Production deployments should have at least 2 replicas for high availability"
}

# -----------------------------------------------------------------------------
# ML Inference Specific Policies
# -----------------------------------------------------------------------------

deny contains msg if {
    input.kind == "Deployment"
    input.metadata.labels.type == "ml-inference"
    some container in input.spec.template.spec.containers
    some env in container.env
    env.name == "MODEL_URI"
    not is_approved_model_uri(env.value)
    msg := "Model URI must be from an approved model registry"
}

warn contains msg if {
    input.kind == "Deployment"
    input.metadata.labels.type == "ml-inference"
    not has_prometheus_annotations(input.spec.template.metadata.annotations)
    msg := "ML inference deployments should have Prometheus scrape annotations"
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

is_approved_registry(image) if {
    some registry in approved_registries
    contains(image, registry)
}

is_approved_model_uri(uri) if {
    startswith(uri, "s3://")
}

is_approved_model_uri(uri) if {
    startswith(uri, "gs://")
}

is_approved_model_uri(uri) if {
    startswith(uri, "mlflow://")
}

has_prometheus_annotations(annotations) if {
    annotations["prometheus.io/scrape"] == "true"
}
