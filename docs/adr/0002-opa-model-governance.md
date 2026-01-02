# ADR 0002: OPA for Model Governance

## Status

Accepted

## Context

ML model deployments require governance to ensure quality, fairness, and compliance. We need a policy engine to evaluate models before deployment.

Options considered:

1. **Open Policy Agent (OPA)** - General-purpose policy engine
2. **Custom Python Scripts** - Bespoke validation logic
3. **ML Platforms** - Built-in governance (MLflow, Kubeflow)
4. **AWS SageMaker Model Monitor** - AWS-native solution

## Decision

We will use **Open Policy Agent (OPA)** with Rego policies for model governance.

## Rationale

### Advantages

1. **Declarative Policies**
   - Rego is purpose-built for policy
   - Clear separation of policy from code
   - Version-controlled policies
   - Easy to audit and review

2. **Extensibility**
   - Add new policies without code changes
   - Combine multiple policy domains
   - Custom functions available

3. **Testing**
   - Built-in test framework
   - Unit tests for policies
   - Simulation capabilities

4. **Ecosystem**
   - Conftest for CI integration
   - Gatekeeper for Kubernetes
   - Widely adopted in cloud-native

5. **Platform Agnostic**
   - Works with any ML platform
   - Not tied to specific vendor
   - Portable across environments

### Trade-offs

1. **Learning Curve**
   - Rego syntax is unique
   - Requires training for data scientists
   - Mitigation: Provide templates and examples

2. **Runtime Dependency**
   - OPA binary required in pipeline
   - Additional component to maintain
   - Mitigation: Use official Docker images

## Policy Examples

### Quality Gate
```rego
deny contains msg if {
    input.spec.metrics.accuracy < 0.85
    msg := "Model accuracy below threshold"
}
```

### Fairness Check
```rego
deny contains msg if {
    not input.spec.fairness
    msg := "Fairness metrics required"
}
```

### Drift Detection
```rego
deny contains msg if {
    input.spec.drift.score > 0.30
    msg := "Model drift too high"
}
```

## Consequences

### Positive

- Consistent policy enforcement
- Auditable decisions
- Easy policy updates
- Strong community support

### Negative

- Additional tool to learn
- Rego debugging can be tricky
- Policies need maintenance

## Alternatives Rejected

### Custom Python Scripts
- Harder to maintain
- Less declarative
- Testing more complex
- No standard format

### ML Platform Built-in
- Vendor lock-in
- Limited customization
- May not cover all policies
- Different per platform

### AWS SageMaker Monitor
- AWS-specific
- Runtime monitoring, not gate
- Additional cost
- Limited policy flexibility

## References

- [Open Policy Agent](https://www.openpolicyagent.org/)
- [Rego Policy Language](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Conftest](https://www.conftest.dev/)
