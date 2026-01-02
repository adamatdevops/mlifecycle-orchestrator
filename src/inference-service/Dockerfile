# =============================================================================
# ML Inference Service Dockerfile
# =============================================================================
# Multi-stage build for minimal, secure production image.
#
# Build: docker build -t inference-service:latest .
# Run:   docker run -p 8080:8080 inference-service:latest
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder
# -----------------------------------------------------------------------------
FROM python:3.11-slim as builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# -----------------------------------------------------------------------------
# Stage 2: Production
# -----------------------------------------------------------------------------
FROM python:3.11-slim as production

# Labels
LABEL maintainer="ML Platform Team"
LABEL description="Zero-touch ML Inference Service"
LABEL version="1.0.0"

# Security: Create non-root user
RUN groupadd -r inference && useradd -r -g inference inference

WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application code
COPY app/ ./app/

# Security: Set ownership
RUN chown -R inference:inference /app

# Security: Run as non-root user
USER inference

# Environment variables
ENV MODEL_NAME="demo-model"
ENV MODEL_VERSION="1.0.0"
ENV MODEL_URI="demo"
ENV MODEL_FRAMEWORK="pytorch"
ENV LOG_LEVEL="INFO"
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Run the service
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
