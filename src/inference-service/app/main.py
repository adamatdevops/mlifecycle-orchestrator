"""
ML Inference Service
====================
Zero-touch deployed inference endpoint for ML models.

This service is automatically deployed when models are registered
in MLflow and pass governance policies.

Endpoints:
- GET  /health     - Liveness check
- GET  /ready      - Readiness check (model loaded)
- POST /predict    - Model inference
- GET  /model/info - Model metadata
- GET  /metrics    - Prometheus metrics
"""

import os
import logging
import time
from typing import Any
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field
import torch
import numpy as np

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

MODEL_NAME = os.getenv("MODEL_NAME", "unknown")
MODEL_VERSION = os.getenv("MODEL_VERSION", "unknown")
MODEL_URI = os.getenv("MODEL_URI", "")
MODEL_FRAMEWORK = os.getenv("MODEL_FRAMEWORK", "pytorch")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

# -----------------------------------------------------------------------------
# Metrics (Prometheus format)
# -----------------------------------------------------------------------------

class Metrics:
    """Simple Prometheus-style metrics collector."""

    def __init__(self):
        self.request_count = 0
        self.request_latency_sum = 0.0
        self.prediction_count = 0
        self.error_count = 0

    def record_request(self, latency: float, success: bool = True):
        self.request_count += 1
        self.request_latency_sum += latency
        if success:
            self.prediction_count += 1
        else:
            self.error_count += 1

    def to_prometheus(self) -> str:
        avg_latency = self.request_latency_sum / max(self.request_count, 1)
        return f"""# HELP inference_requests_total Total number of inference requests
# TYPE inference_requests_total counter
inference_requests_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.request_count}

# HELP inference_predictions_total Total successful predictions
# TYPE inference_predictions_total counter
inference_predictions_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.prediction_count}

# HELP inference_errors_total Total prediction errors
# TYPE inference_errors_total counter
inference_errors_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.error_count}

# HELP inference_latency_seconds Average inference latency
# TYPE inference_latency_seconds gauge
inference_latency_seconds{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {avg_latency:.6f}
"""


metrics = Metrics()

# -----------------------------------------------------------------------------
# Model Loading
# -----------------------------------------------------------------------------

class ModelWrapper:
    """Wrapper for PyTorch model with inference logic."""

    def __init__(self):
        self.model = None
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.loaded = False

    def load(self):
        """Load model from URI or use demo model."""
        logger.info(f"Loading model: {MODEL_NAME} v{MODEL_VERSION}")
        logger.info(f"Model URI: {MODEL_URI}")
        logger.info(f"Device: {self.device}")

        try:
            if MODEL_URI and MODEL_URI != "demo":
                # In production, load from MLflow or S3
                # self.model = mlflow.pytorch.load_model(MODEL_URI)
                logger.info("Production model loading would happen here")
                self._load_demo_model()
            else:
                # Demo mode: create simple classifier
                self._load_demo_model()

            self.loaded = True
            logger.info("Model loaded successfully")

        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            raise

    def _load_demo_model(self):
        """Create a simple demo model for testing."""
        # Simple binary classifier for demonstration
        self.model = torch.nn.Sequential(
            torch.nn.Linear(10, 32),
            torch.nn.ReLU(),
            torch.nn.Linear(32, 16),
            torch.nn.ReLU(),
            torch.nn.Linear(16, 2),
            torch.nn.Softmax(dim=1)
        ).to(self.device)
        self.model.eval()

    def predict(self, features: list[list[float]]) -> list[dict[str, Any]]:
        """Run inference on input features."""
        if not self.loaded:
            raise RuntimeError("Model not loaded")

        with torch.no_grad():
            # Convert to tensor
            input_tensor = torch.tensor(features, dtype=torch.float32).to(self.device)

            # Ensure correct input shape (pad if needed for demo)
            if input_tensor.shape[1] < 10:
                padding = torch.zeros(input_tensor.shape[0], 10 - input_tensor.shape[1]).to(self.device)
                input_tensor = torch.cat([input_tensor, padding], dim=1)
            elif input_tensor.shape[1] > 10:
                input_tensor = input_tensor[:, :10]

            # Run inference
            outputs = self.model(input_tensor)

            # Format results
            results = []
            for i, output in enumerate(outputs.cpu().numpy()):
                prediction = int(np.argmax(output))
                confidence = float(np.max(output))
                results.append({
                    "prediction": prediction,
                    "confidence": confidence,
                    "probabilities": output.tolist()
                })

            return results


model_wrapper = ModelWrapper()

# -----------------------------------------------------------------------------
# Lifespan Management
# -----------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan - load model on startup."""
    logger.info("Starting inference service...")
    try:
        model_wrapper.load()
    except Exception as e:
        logger.error(f"Failed to initialize model: {e}")
        # Continue anyway for health check visibility
    yield
    logger.info("Shutting down inference service...")

# -----------------------------------------------------------------------------
# FastAPI Application
# -----------------------------------------------------------------------------

app = FastAPI(
    title="ML Inference Service",
    description="Zero-touch deployed ML inference endpoint",
    version=MODEL_VERSION,
    lifespan=lifespan
)

# -----------------------------------------------------------------------------
# Request/Response Models
# -----------------------------------------------------------------------------

class PredictionRequest(BaseModel):
    """Input for prediction endpoint."""
    instances: list[list[float]] = Field(
        ...,
        description="List of feature vectors for prediction",
        example=[[1.0, 2.0, 3.0, 4.0, 5.0]]
    )


class PredictionResult(BaseModel):
    """Single prediction result."""
    prediction: int
    confidence: float
    probabilities: list[float]


class PredictionResponse(BaseModel):
    """Output from prediction endpoint."""
    predictions: list[PredictionResult]
    model_name: str
    model_version: str
    inference_time_ms: float


class ModelInfo(BaseModel):
    """Model metadata."""
    name: str
    version: str
    uri: str
    framework: str
    loaded: bool
    device: str

# -----------------------------------------------------------------------------
# Endpoints
# -----------------------------------------------------------------------------

@app.get("/health")
async def health():
    """Liveness probe - service is running."""
    return {"status": "healthy"}


@app.get("/ready")
async def ready():
    """Readiness probe - model is loaded and ready."""
    if not model_wrapper.loaded:
        raise HTTPException(status_code=503, detail="Model not loaded")
    return {
        "status": "ready",
        "model": MODEL_NAME,
        "version": MODEL_VERSION
    }


@app.post("/predict", response_model=PredictionResponse)
async def predict(request: PredictionRequest, req: Request):
    """Run inference on input features."""
    if not model_wrapper.loaded:
        raise HTTPException(status_code=503, detail="Model not loaded")

    start_time = time.time()
    success = True

    try:
        results = model_wrapper.predict(request.instances)
        predictions = [PredictionResult(**r) for r in results]

    except Exception as e:
        success = False
        logger.error(f"Prediction failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        latency = time.time() - start_time
        metrics.record_request(latency, success)

    return PredictionResponse(
        predictions=predictions,
        model_name=MODEL_NAME,
        model_version=MODEL_VERSION,
        inference_time_ms=latency * 1000
    )


@app.get("/model/info", response_model=ModelInfo)
async def model_info():
    """Get model metadata."""
    return ModelInfo(
        name=MODEL_NAME,
        version=MODEL_VERSION,
        uri=MODEL_URI,
        framework=MODEL_FRAMEWORK,
        loaded=model_wrapper.loaded,
        device=model_wrapper.device
    )


@app.get("/metrics", response_class=PlainTextResponse)
async def prometheus_metrics():
    """Prometheus metrics endpoint."""
    return metrics.to_prometheus()


# -----------------------------------------------------------------------------
# Error Handlers
# -----------------------------------------------------------------------------

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}")
    metrics.error_count += 1
    return {"error": str(exc), "status": 500}
