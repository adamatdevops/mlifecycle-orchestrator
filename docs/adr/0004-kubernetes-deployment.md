# ADR 0004: Kubernetes with Kustomize for Deployment

## Status

Accepted

## Context

We need a deployment platform for ML inference services that supports:

- Auto-scaling based on load
- Rolling updates with zero downtime
- Health monitoring
- Multi-environment management
- Resource isolation

Options considered:

1. **Kubernetes with Kustomize** - K8s with overlay management
2. **Kubernetes with Helm** - K8s with templating
3. **AWS ECS** - AWS container service
4. **AWS Lambda** - Serverless functions
5. **Docker Compose** - Simple container orchestration

## Decision

We will use **Kubernetes with Kustomize** for deployment.

## Rationale

### Advantages

1. **Scalability**
   - Horizontal Pod Autoscaler
   - Cluster Autoscaler
   - GPU node pools
   - Handle variable loads

2. **Reliability**
   - Self-healing pods
   - Rolling updates
   - Pod Disruption Budgets
   - Multi-zone deployment

3. **Kustomize Benefits**
   - Native kubectl integration
   - No templating language
   - Clear base/overlay structure
   - GitOps friendly

4. **Observability**
   - ServiceMonitor for Prometheus
   - Standard logging
   - Network policies
   - Resource metrics

5. **Portability**
   - Cloud agnostic
   - EKS, GKE, AKS support
   - On-premise option
   - Consistent tooling

### Trade-offs

1. **Complexity**
   - Steeper learning curve
   - Requires K8s expertise
   - More YAML files
   - Mitigation: Use templates and documentation

2. **Infrastructure Cost**
   - Control plane overhead
   - Node minimum
   - GPU nodes expensive
   - Mitigation: Use Fargate, spot instances

## Environment Strategy

### Base Configuration
```yaml
# infrastructure/kubernetes/base/
├── kustomization.yaml
├── deployment.yaml
├── service.yaml
├── hpa.yaml
└── pdb.yaml
```

### Overlays
```yaml
# infrastructure/kubernetes/overlays/
├── dev/
│   └── kustomization.yaml    # 1 replica, 500m CPU
├── staging/
│   └── kustomization.yaml    # 2 replicas, 1 CPU
└── prod/
    └── kustomization.yaml    # 3+ replicas, 2 CPU
```

### Deployment
```bash
# Deploy to staging
kustomize build overlays/staging | kubectl apply -f -

# Deploy to production
kustomize build overlays/prod | kubectl apply -f -
```

## Key Configurations

### HPA
```yaml
spec:
  minReplicas: 2
  maxReplicas: 50
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### PDB
```yaml
spec:
  minAvailable: 1
```

### Health Checks
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 15

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
```

## Consequences

### Positive

- Production-grade orchestration
- Excellent scaling capabilities
- Strong ecosystem
- Portable across clouds

### Negative

- Operational complexity
- Requires K8s knowledge
- Infrastructure overhead

## Alternatives Rejected

### Helm
- Templating adds complexity
- Go template syntax
- Harder to understand
- Kustomize is simpler for our needs

### AWS ECS
- AWS lock-in
- Less portable
- Smaller ecosystem
- Good alternative for AWS-only

### AWS Lambda
- Cold start latency
- Model size limits
- Stateless challenges
- Good for light workloads

### Docker Compose
- Not production-grade
- No auto-scaling
- Limited health checks
- Development only

## References

- [Kustomize](https://kustomize.io/)
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
