# ADR 0003: FastAPI for Inference Service

## Status

Accepted

## Context

We need a web framework for the ML inference service that will handle prediction requests. Requirements:

- High performance for low-latency inference
- Async support for concurrent requests
- Easy integration with ML frameworks
- OpenAPI documentation
- Prometheus metrics support

Options considered:

1. **FastAPI** - Modern async Python framework
2. **Flask** - Traditional Python microframework
3. **Django** - Full-featured Python framework
4. **TorchServe** - PyTorch-specific serving
5. **TensorFlow Serving** - TensorFlow-specific serving
6. **Triton Inference Server** - NVIDIA serving platform

## Decision

We will use **FastAPI** for the inference service.

## Rationale

### Advantages

1. **Performance**
   - Built on Starlette (ASGI)
   - Async/await support
   - Comparable to Node.js/Go
   - Efficient request handling

2. **Developer Experience**
   - Type hints with Pydantic
   - Automatic OpenAPI docs
   - Request/response validation
   - Intuitive API design

3. **ML Integration**
   - Framework agnostic
   - Easy PyTorch/TensorFlow integration
   - NumPy serialization
   - Batch prediction support

4. **Production Ready**
   - Uvicorn ASGI server
   - Health check endpoints
   - Metrics instrumentation
   - Docker-friendly

5. **Flexibility**
   - Any model format
   - Custom preprocessing
   - Multiple models
   - A/B testing support

### Trade-offs

1. **Not ML-Specific**
   - No built-in model versioning
   - Manual GPU optimization
   - Custom batching logic
   - Mitigation: Implement as needed

2. **Single Framework**
   - Supports any framework but requires code
   - Not auto-optimized per framework
   - Mitigation: Optimize for primary framework

## Implementation

### Basic Structure
```python
from fastapi import FastAPI
from pydantic import BaseModel
import torch

app = FastAPI()
model = None

class PredictionRequest(BaseModel):
    instances: list[list[float]]

@app.post("/predict")
async def predict(request: PredictionRequest):
    with torch.no_grad():
        predictions = model(request.instances)
    return {"predictions": predictions}
```

### Endpoints
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Liveness probe |
| `/ready` | GET | Readiness probe |
| `/predict` | POST | Run inference |
| `/model/info` | GET | Model metadata |
| `/metrics` | GET | Prometheus metrics |

## Consequences

### Positive

- High performance async serving
- Excellent documentation
- Easy testing
- Framework flexibility
- Active community

### Negative

- Manual ML optimizations needed
- No automatic batching
- Custom model management

## Alternatives Rejected

### Flask
- Synchronous by default
- Older architecture
- Less performant
- No built-in validation

### Django
- Overkill for microservice
- Heavier footprint
- ORM unnecessary
- Slower startup

### TorchServe
- PyTorch-specific
- More complex setup
- Less flexible
- Steeper learning curve

### TensorFlow Serving
- TensorFlow-specific
- gRPC primary
- Less Python-friendly
- Limited customization

### Triton Inference Server
- Complex setup
- NVIDIA ecosystem
- Overkill for simple cases
- Good for multi-model/GPU

## References

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [FastAPI for ML](https://fastapi.tiangolo.com/deployment/docker/)
- [Uvicorn](https://www.uvicorn.org/)
