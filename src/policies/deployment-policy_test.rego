# =============================================================================
# Kubernetes Deployment Policy - Unit Tests
# =============================================================================
# Run: opa test src/policies/ -v
# =============================================================================

package kubernetes.deployment_test

import data.kubernetes.deployment
import rego.v1

# -----------------------------------------------------------------------------
# Test Data: Valid Deployment
# -----------------------------------------------------------------------------

valid_deployment := {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
        "name": "fraud-detector-inference",
        "labels": {
            "app": "fraud-detector",
            "version": "v2.1.0",
            "team": "ml-platform",
            "type": "ml-inference"
        }
    },
    "spec": {
        "replicas": 2,
        "selector": {
            "matchLabels": {"app": "fraud-detector"}
        },
        "template": {
            "metadata": {
                "labels": {
                    "app": "fraud-detector",
                    "version": "v2.1.0",
                    "team": "ml-platform"
                },
                "annotations": {
                    "prometheus.io/scrape": "true",
                    "prometheus.io/port": "8080"
                }
            },
            "spec": {
                "securityContext": {
                    "runAsNonRoot": true,
                    "runAsUser": 1000
                },
                "containers": [{
                    "name": "inference",
                    "image": "ghcr.io/example-org/fraud-detector:v2.1.0",
                    "securityContext": {
                        "privileged": false,
                        "allowPrivilegeEscalation": false,
                        "readOnlyRootFilesystem": true
                    },
                    "resources": {
                        "requests": {"cpu": "500m", "memory": "1Gi"},
                        "limits": {"cpu": "2", "memory": "4Gi"}
                    },
                    "livenessProbe": {
                        "httpGet": {"path": "/health", "port": 8080}
                    },
                    "readinessProbe": {
                        "httpGet": {"path": "/ready", "port": 8080}
                    },
                    "env": [{
                        "name": "MODEL_URI",
                        "value": "s3://model-bucket/fraud-detector/v2.1.0"
                    }]
                }]
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Test: Valid Deployment Should Pass
# -----------------------------------------------------------------------------

test_valid_deployment_allowed if {
    deployment.allow with input as valid_deployment
}

test_valid_deployment_no_denies if {
    count(deployment.deny) == 0 with input as valid_deployment
}

# -----------------------------------------------------------------------------
# Test: Security Context
# -----------------------------------------------------------------------------

test_deny_privileged_container if {
    d := json.patch(valid_deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/privileged", "value": true}])
    count([m | m := deployment.deny[_]; contains(m, "privileged mode")]) > 0 with input as d
}

test_deny_missing_run_as_non_root if {
    d := json.remove(valid_deployment, ["/spec/template/spec/securityContext/runAsNonRoot"])
    "Deployment must set runAsNonRoot: true in pod security context" in deployment.deny with input as d
}

test_deny_privilege_escalation if {
    d := json.patch(valid_deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/allowPrivilegeEscalation", "value": true}])
    count([m | m := deployment.deny[_]; contains(m, "privilege escalation")]) > 0 with input as d
}

# -----------------------------------------------------------------------------
# Test: Resource Limits
# -----------------------------------------------------------------------------

test_deny_missing_memory_limits if {
    d := json.remove(valid_deployment, ["/spec/template/spec/containers/0/resources/limits/memory"])
    count([m | m := deployment.deny[_]; contains(m, "memory limits")]) > 0 with input as d
}

test_deny_missing_cpu_limits if {
    d := json.remove(valid_deployment, ["/spec/template/spec/containers/0/resources/limits/cpu"])
    count([m | m := deployment.deny[_]; contains(m, "CPU limits")]) > 0 with input as d
}

test_deny_missing_memory_requests if {
    d := json.remove(valid_deployment, ["/spec/template/spec/containers/0/resources/requests/memory"])
    count([m | m := deployment.deny[_]; contains(m, "memory requests")]) > 0 with input as d
}

# -----------------------------------------------------------------------------
# Test: Health Checks
# -----------------------------------------------------------------------------

test_deny_missing_liveness_probe if {
    d := json.remove(valid_deployment, ["/spec/template/spec/containers/0/livenessProbe"])
    count([m | m := deployment.deny[_]; contains(m, "liveness probe")]) > 0 with input as d
}

test_deny_missing_readiness_probe if {
    d := json.remove(valid_deployment, ["/spec/template/spec/containers/0/readinessProbe"])
    count([m | m := deployment.deny[_]; contains(m, "readiness probe")]) > 0 with input as d
}

# -----------------------------------------------------------------------------
# Test: Image Policies
# -----------------------------------------------------------------------------

test_deny_latest_tag if {
    d := json.patch(valid_deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "ghcr.io/example-org/fraud-detector:latest"}])
    count([m | m := deployment.deny[_]; contains(m, ":latest tag")]) > 0 with input as d
}

test_deny_no_tag if {
    d := json.patch(valid_deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "ghcr.io/example-org/fraud-detector"}])
    count([m | m := deployment.deny[_]; contains(m, "image tag")]) > 0 with input as d
}

test_deny_unapproved_registry if {
    d := json.patch(valid_deployment, [{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "malicious-registry.com/fraud-detector:v1.0.0"}])
    count([m | m := deployment.deny[_]; contains(m, "approved registry")]) > 0 with input as d
}

# -----------------------------------------------------------------------------
# Test: Label Policies
# -----------------------------------------------------------------------------

test_deny_missing_app_label if {
    d := json.remove(valid_deployment, ["/metadata/labels/app"])
    "Deployment must have label 'app'" in deployment.deny with input as d
}

test_deny_missing_version_label if {
    d := json.remove(valid_deployment, ["/metadata/labels/version"])
    "Deployment must have label 'version'" in deployment.deny with input as d
}

test_deny_missing_team_label if {
    d := json.remove(valid_deployment, ["/metadata/labels/team"])
    "Deployment must have label 'team'" in deployment.deny with input as d
}

# -----------------------------------------------------------------------------
# Test: Replica Warning
# -----------------------------------------------------------------------------

test_warn_single_replica if {
    d := json.patch(valid_deployment, [{"op": "replace", "path": "/spec/replicas", "value": 1}])
    count([m | m := deployment.warn[_]; contains(m, "at least 2 replicas")]) > 0 with input as d
}

test_no_replica_warning_with_two if {
    count([m | m := deployment.warn[_]; contains(m, "replicas")]) == 0 with input as valid_deployment
}
