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
import uuid
from datetime import datetime
from typing import Any, Optional
from contextlib import asynccontextmanager
from functools import wraps

from fastapi import FastAPI, HTTPException, Request, Depends, Security
from fastapi.security import APIKeyHeader
from fastapi.responses import PlainTextResponse, JSONResponse
from pydantic import BaseModel, Field, field_validator
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
API_KEY = os.getenv("API_KEY", "")  # Empty = no auth required
ENABLE_AUDIT_LOG = os.getenv("ENABLE_AUDIT_LOG", "true").lower() == "true"
MAX_BATCH_SIZE = int(os.getenv("MAX_BATCH_SIZE", "100"))
MAX_FEATURES = int(os.getenv("MAX_FEATURES", "1000"))

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)
audit_logger = logging.getLogger("audit")

# -----------------------------------------------------------------------------
# Custom Exceptions
# -----------------------------------------------------------------------------

class InferenceError(Exception):
    """Base exception for inference service errors."""
    def __init__(self, message: str, error_code: str, details: Optional[dict] = None):
        self.message = message
        self.error_code = error_code
        self.details = details or {}
        super().__init__(message)


class ModelNotLoadedError(InferenceError):
    """Raised when model is not loaded."""
    def __init__(self, message: str = "Model not loaded"):
        super().__init__(message, "MODEL_NOT_LOADED")


class ModelLoadError(InferenceError):
    """Raised when model fails to load."""
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "MODEL_LOAD_ERROR", details)


class ValidationError(InferenceError):
    """Raised when input validation fails."""
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "VALIDATION_ERROR", details)


class PredictionError(InferenceError):
    """Raised when prediction fails."""
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(message, "PREDICTION_ERROR", details)


class AuthenticationError(InferenceError):
    """Raised when authentication fails."""
    def __init__(self, message: str = "Invalid or missing API key"):
        super().__init__(message, "AUTHENTICATION_ERROR")


class RateLimitError(InferenceError):
    """Raised when rate limit is exceeded."""
    def __init__(self, message: str = "Rate limit exceeded"):
        super().__init__(message, "RATE_LIMIT_ERROR")


# -----------------------------------------------------------------------------
# Structured Error Response
# -----------------------------------------------------------------------------

class APIError(BaseModel):
    """Structured API error response."""
    error_code: str = Field(..., description="Machine-readable error code")
    message: str = Field(..., description="Human-readable error message")
    details: Optional[dict] = Field(default=None, description="Additional error details")
    request_id: str = Field(..., description="Unique request identifier")
    timestamp: str = Field(..., description="Error timestamp in ISO format")


# -----------------------------------------------------------------------------
# Metrics (Prometheus format)
# -----------------------------------------------------------------------------

class Metrics:
    """Prometheus-style metrics collector with detailed tracking."""

    def __init__(self):
        self.request_count = 0
        self.request_latency_sum = 0.0
        self.prediction_count = 0
        self.error_count = 0
        self.validation_error_count = 0
        self.auth_error_count = 0
        self.instances_processed = 0
        self.latency_histogram = {
            "le_10ms": 0,
            "le_50ms": 0,
            "le_100ms": 0,
            "le_500ms": 0,
            "le_1000ms": 0,
            "le_inf": 0
        }

    def record_request(self, latency: float, success: bool = True, instances: int = 0):
        self.request_count += 1
        self.request_latency_sum += latency
        self.instances_processed += instances

        # Update histogram
        latency_ms = latency * 1000
        if latency_ms <= 10:
            self.latency_histogram["le_10ms"] += 1
        elif latency_ms <= 50:
            self.latency_histogram["le_50ms"] += 1
        elif latency_ms <= 100:
            self.latency_histogram["le_100ms"] += 1
        elif latency_ms <= 500:
            self.latency_histogram["le_500ms"] += 1
        elif latency_ms <= 1000:
            self.latency_histogram["le_1000ms"] += 1
        else:
            self.latency_histogram["le_inf"] += 1

        if success:
            self.prediction_count += 1
        else:
            self.error_count += 1

    def record_validation_error(self):
        self.validation_error_count += 1
        self.error_count += 1

    def record_auth_error(self):
        self.auth_error_count += 1
        self.error_count += 1

    def to_prometheus(self) -> str:
        avg_latency = self.request_latency_sum / max(self.request_count, 1)
        return f"""# HELP inference_requests_total Total number of inference requests
# TYPE inference_requests_total counter
inference_requests_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.request_count}

# HELP inference_predictions_total Total successful predictions
# TYPE inference_predictions_total counter
inference_predictions_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.prediction_count}

# HELP inference_instances_total Total instances processed
# TYPE inference_instances_total counter
inference_instances_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.instances_processed}

# HELP inference_errors_total Total prediction errors
# TYPE inference_errors_total counter
inference_errors_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.error_count}

# HELP inference_validation_errors_total Total validation errors
# TYPE inference_validation_errors_total counter
inference_validation_errors_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.validation_error_count}

# HELP inference_auth_errors_total Total authentication errors
# TYPE inference_auth_errors_total counter
inference_auth_errors_total{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {self.auth_error_count}

# HELP inference_latency_seconds Average inference latency
# TYPE inference_latency_seconds gauge
inference_latency_seconds{{model="{MODEL_NAME}",version="{MODEL_VERSION}"}} {avg_latency:.6f}

# HELP inference_latency_histogram Inference latency histogram
# TYPE inference_latency_histogram histogram
inference_latency_bucket{{model="{MODEL_NAME}",version="{MODEL_VERSION}",le="0.01"}} {self.latency_histogram["le_10ms"]}
inference_latency_bucket{{model="{MODEL_NAME}",version="{MODEL_VERSION}",le="0.05"}} {self.latency_histogram["le_50ms"]}
inference_latency_bucket{{model="{MODEL_NAME}",version="{MODEL_VERSION}",le="0.1"}} {self.latency_histogram["le_100ms"]}
inference_latency_bucket{{model="{MODEL_NAME}",version="{MODEL_VERSION}",le="0.5"}} {self.latency_histogram["le_500ms"]}
inference_latency_bucket{{model="{MODEL_NAME}",version="{MODEL_VERSION}",le="1.0"}} {self.latency_histogram["le_1000ms"]}
inference_latency_bucket{{model="{MODEL_NAME}",version="{MODEL_VERSION}",le="+Inf"}} {self.latency_histogram["le_inf"]}
"""


metrics = Metrics()

# -----------------------------------------------------------------------------
# Audit Logging
# -----------------------------------------------------------------------------

class AuditLog:
    """Structured audit logging for compliance and debugging."""

    @staticmethod
    def log_prediction(
        request_id: str,
        client_ip: str,
        instances_count: int,
        latency_ms: float,
        success: bool,
        error: Optional[str] = None
    ):
        if not ENABLE_AUDIT_LOG:
            return

        audit_entry = {
            "event": "prediction",
            "request_id": request_id,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "model_name": MODEL_NAME,
            "model_version": MODEL_VERSION,
            "client_ip": client_ip,
            "instances_count": instances_count,
            "latency_ms": round(latency_ms, 2),
            "success": success,
            "error": error
        }
        audit_logger.info(str(audit_entry))

    @staticmethod
    def log_auth_failure(request_id: str, client_ip: str, reason: str):
        if not ENABLE_AUDIT_LOG:
            return

        audit_entry = {
            "event": "auth_failure",
            "request_id": request_id,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "client_ip": client_ip,
            "reason": reason
        }
        audit_logger.warning(str(audit_entry))


# -----------------------------------------------------------------------------
# Authentication
# -----------------------------------------------------------------------------

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def verify_api_key(
    request: Request,
    api_key: Optional[str] = Security(api_key_header)
) -> Optional[str]:
    """Verify API key if authentication is enabled."""
    if not API_KEY:
        # Authentication disabled
        return None

    request_id = getattr(request.state, "request_id", "unknown")
    client_ip = request.client.host if request.client else "unknown"

    if not api_key:
        metrics.record_auth_error()
        AuditLog.log_auth_failure(request_id, client_ip, "missing_api_key")
        raise AuthenticationError("API key is required")

    if api_key != API_KEY:
        metrics.record_auth_error()
        AuditLog.log_auth_failure(request_id, client_ip, "invalid_api_key")
        raise AuthenticationError("Invalid API key")

    return api_key


# -----------------------------------------------------------------------------
# Model Loading
# -----------------------------------------------------------------------------

class ModelWrapper:
    """Wrapper for PyTorch model with inference logic."""

    def __init__(self):
        self.model = None
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.loaded = False
        self.input_features = 10  # Expected input size

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
            raise ModelLoadError(f"Failed to load model: {e}", {"uri": MODEL_URI})

    def _load_demo_model(self):
        """Create a simple demo model for testing."""
        # Simple binary classifier for demonstration
        self.model = torch.nn.Sequential(
            torch.nn.Linear(self.input_features, 32),
            torch.nn.ReLU(),
            torch.nn.Linear(32, 16),
            torch.nn.ReLU(),
            torch.nn.Linear(16, 2),
            torch.nn.Softmax(dim=1)
        ).to(self.device)
        self.model.eval()

    def validate_input(self, features: list[list[float]]) -> None:
        """Validate input features before prediction."""
        if not features:
            raise ValidationError(
                "Empty instances list",
                {"field": "instances", "reason": "list cannot be empty"}
            )

        if len(features) > MAX_BATCH_SIZE:
            raise ValidationError(
                f"Batch size {len(features)} exceeds maximum {MAX_BATCH_SIZE}",
                {"field": "instances", "max_batch_size": MAX_BATCH_SIZE, "actual": len(features)}
            )

        for i, instance in enumerate(features):
            if not isinstance(instance, list):
                raise ValidationError(
                    f"Instance {i} is not a list",
                    {"field": f"instances[{i}]", "expected": "list", "actual": type(instance).__name__}
                )

            if len(instance) > MAX_FEATURES:
                raise ValidationError(
                    f"Instance {i} has {len(instance)} features, maximum is {MAX_FEATURES}",
                    {"field": f"instances[{i}]", "max_features": MAX_FEATURES, "actual": len(instance)}
                )

            for j, value in enumerate(instance):
                if not isinstance(value, (int, float)):
                    raise ValidationError(
                        f"Instance {i}, feature {j} is not a number",
                        {"field": f"instances[{i}][{j}]", "expected": "number", "actual": type(value).__name__}
                    )

                if not np.isfinite(value):
                    raise ValidationError(
                        f"Instance {i}, feature {j} is not finite (NaN or Inf)",
                        {"field": f"instances[{i}][{j}]", "value": str(value)}
                    )

    def predict(self, features: list[list[float]]) -> list[dict[str, Any]]:
        """Run inference on input features."""
        if not self.loaded:
            raise ModelNotLoadedError()

        # Validate input
        self.validate_input(features)

        try:
            with torch.no_grad():
                # Convert to tensor
                input_tensor = torch.tensor(features, dtype=torch.float32).to(self.device)

                # Ensure correct input shape (pad if needed for demo)
                if input_tensor.shape[1] < self.input_features:
                    padding = torch.zeros(
                        input_tensor.shape[0],
                        self.input_features - input_tensor.shape[1]
                    ).to(self.device)
                    input_tensor = torch.cat([input_tensor, padding], dim=1)
                elif input_tensor.shape[1] > self.input_features:
                    input_tensor = input_tensor[:, :self.input_features]

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

        except ValidationError:
            raise
        except Exception as e:
            raise PredictionError(f"Inference failed: {str(e)}")


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
# Middleware
# -----------------------------------------------------------------------------

@app.middleware("http")
async def add_request_id(request: Request, call_next):
    """Add unique request ID to each request."""
    request_id = str(uuid.uuid4())[:8]
    request.state.request_id = request_id

    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response

# -----------------------------------------------------------------------------
# Request/Response Models
# -----------------------------------------------------------------------------

class PredictionRequest(BaseModel):
    """Input for prediction endpoint."""
    instances: list[list[float]] = Field(
        ...,
        description="List of feature vectors for prediction",
        examples=[[[1.0, 2.0, 3.0, 4.0, 5.0]]]
    )

    @field_validator('instances')
    @classmethod
    def validate_instances(cls, v):
        if not v:
            raise ValueError("instances cannot be empty")
        if len(v) > MAX_BATCH_SIZE:
            raise ValueError(f"batch size exceeds maximum of {MAX_BATCH_SIZE}")
        return v


class PredictionResult(BaseModel):
    """Single prediction result."""
    prediction: int
    confidence: float
    probabilities: list[float]


class PredictionResponse(BaseModel):
    """Output from prediction endpoint."""
    request_id: str
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
    input_features: int
    max_batch_size: int

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
        raise ModelNotLoadedError()
    return {
        "status": "ready",
        "model": MODEL_NAME,
        "version": MODEL_VERSION
    }


@app.post("/predict", response_model=PredictionResponse)
async def predict(
    request: PredictionRequest,
    req: Request,
    _: Optional[str] = Depends(verify_api_key)
):
    """Run inference on input features."""
    request_id = req.state.request_id
    client_ip = req.client.host if req.client else "unknown"
    start_time = time.time()
    success = True
    error_msg = None

    try:
        if not model_wrapper.loaded:
            raise ModelNotLoadedError()

        results = model_wrapper.predict(request.instances)
        predictions = [PredictionResult(**r) for r in results]

    except InferenceError:
        success = False
        raise

    except Exception as e:
        success = False
        error_msg = str(e)
        logger.error(f"Prediction failed: {e}")
        raise PredictionError(f"Unexpected error: {str(e)}")

    finally:
        latency = time.time() - start_time
        metrics.record_request(latency, success, len(request.instances) if success else 0)
        AuditLog.log_prediction(
            request_id=request_id,
            client_ip=client_ip,
            instances_count=len(request.instances),
            latency_ms=latency * 1000,
            success=success,
            error=error_msg
        )

    return PredictionResponse(
        request_id=request_id,
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
        device=model_wrapper.device,
        input_features=model_wrapper.input_features,
        max_batch_size=MAX_BATCH_SIZE
    )


@app.get("/metrics", response_class=PlainTextResponse)
async def prometheus_metrics():
    """Prometheus metrics endpoint."""
    return metrics.to_prometheus()


# -----------------------------------------------------------------------------
# Error Handlers
# -----------------------------------------------------------------------------

@app.exception_handler(InferenceError)
async def inference_error_handler(request: Request, exc: InferenceError):
    """Handle custom inference errors with structured response."""
    request_id = getattr(request.state, "request_id", "unknown")

    status_code_map = {
        "MODEL_NOT_LOADED": 503,
        "MODEL_LOAD_ERROR": 503,
        "VALIDATION_ERROR": 422,
        "PREDICTION_ERROR": 500,
        "AUTHENTICATION_ERROR": 401,
        "RATE_LIMIT_ERROR": 429,
    }

    status_code = status_code_map.get(exc.error_code, 500)

    if exc.error_code == "VALIDATION_ERROR":
        metrics.record_validation_error()

    error_response = APIError(
        error_code=exc.error_code,
        message=exc.message,
        details=exc.details,
        request_id=request_id,
        timestamp=datetime.utcnow().isoformat() + "Z"
    )

    return JSONResponse(
        status_code=status_code,
        content=error_response.model_dump()
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Handle unexpected errors with structured response."""
    request_id = getattr(request.state, "request_id", "unknown")
    logger.error(f"Unhandled exception [{request_id}]: {exc}")
    metrics.error_count += 1

    error_response = APIError(
        error_code="INTERNAL_ERROR",
        message="An unexpected error occurred",
        details={"exception": str(exc)} if LOG_LEVEL == "DEBUG" else None,
        request_id=request_id,
        timestamp=datetime.utcnow().isoformat() + "Z"
    )

    return JSONResponse(
        status_code=500,
        content=error_response.model_dump()
    )
