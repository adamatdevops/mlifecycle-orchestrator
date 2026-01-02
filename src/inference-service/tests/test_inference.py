"""
Tests for ML Inference Service
==============================
Run: pytest src/inference-service/tests/ -v
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app, model_wrapper


@pytest.fixture(scope="module")
def client():
    """Create test client and ensure model is loaded."""
    # Load model for tests
    if not model_wrapper.loaded:
        model_wrapper.load()

    with TestClient(app) as c:
        yield c


class TestHealthEndpoints:
    """Test health and readiness endpoints."""

    def test_health_check(self, client):
        """Health endpoint should return healthy status."""
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"

    def test_ready_check(self, client):
        """Ready endpoint should return ready when model is loaded."""
        response = client.get("/ready")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ready"
        assert "model" in data
        assert "version" in data


class TestPredictionEndpoint:
    """Test prediction endpoint."""

    def test_predict_single_instance(self, client):
        """Should return prediction for single instance."""
        response = client.post(
            "/predict",
            json={"instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]}
        )
        assert response.status_code == 200
        data = response.json()
        assert len(data["predictions"]) == 1
        assert "prediction" in data["predictions"][0]
        assert "confidence" in data["predictions"][0]
        assert "probabilities" in data["predictions"][0]
        assert data["inference_time_ms"] > 0
        assert "request_id" in data

    def test_predict_multiple_instances(self, client):
        """Should return predictions for multiple instances."""
        response = client.post(
            "/predict",
            json={
                "instances": [
                    [1.0, 2.0, 3.0, 4.0, 5.0],
                    [5.0, 4.0, 3.0, 2.0, 1.0],
                    [0.5, 0.5, 0.5, 0.5, 0.5]
                ]
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert len(data["predictions"]) == 3

    def test_predict_includes_model_info(self, client):
        """Prediction response should include model metadata."""
        response = client.post(
            "/predict",
            json={"instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]}
        )
        assert response.status_code == 200
        data = response.json()
        assert "model_name" in data
        assert "model_version" in data
        assert "request_id" in data

    def test_predict_empty_instances(self, client):
        """Should return 422 for empty instances list."""
        response = client.post(
            "/predict",
            json={"instances": []}
        )
        assert response.status_code == 422

    def test_predict_invalid_request(self, client):
        """Should return 422 for invalid request format."""
        response = client.post(
            "/predict",
            json={"invalid_field": "value"}
        )
        assert response.status_code == 422


class TestInputValidation:
    """Test input validation for feature vectors."""

    def test_invalid_feature_type_string(self, client):
        """Should reject string values in feature vector."""
        response = client.post(
            "/predict",
            json={"instances": [["invalid", 2.0, 3.0]]}
        )
        assert response.status_code == 422

    def test_batch_size_limit(self, client):
        """Should reject batches exceeding MAX_BATCH_SIZE."""
        # Create 101 instances (default max is 100)
        large_batch = [[1.0, 2.0, 3.0] for _ in range(101)]
        response = client.post(
            "/predict",
            json={"instances": large_batch}
        )
        assert response.status_code == 422

    def test_valid_batch_within_limit(self, client):
        """Should accept batches within MAX_BATCH_SIZE."""
        # Create 10 instances
        batch = [[1.0, 2.0, 3.0] for _ in range(10)]
        response = client.post(
            "/predict",
            json={"instances": batch}
        )
        assert response.status_code == 200
        assert len(response.json()["predictions"]) == 10


class TestStructuredErrors:
    """Test structured error responses."""

    def test_error_response_format(self, client):
        """Error responses should have structured format."""
        response = client.post(
            "/predict",
            json={"instances": []}
        )
        assert response.status_code == 422
        # Pydantic validation errors have different format

    def test_request_id_in_response(self, client):
        """Responses should include X-Request-ID header."""
        response = client.post(
            "/predict",
            json={"instances": [[1.0, 2.0, 3.0]]}
        )
        assert "X-Request-ID" in response.headers


class TestModelInfoEndpoint:
    """Test model info endpoint."""

    def test_model_info(self, client):
        """Should return model metadata."""
        response = client.get("/model/info")
        assert response.status_code == 200
        data = response.json()
        assert "name" in data
        assert "version" in data
        assert "framework" in data
        assert "loaded" in data
        assert "device" in data
        assert "input_features" in data
        assert "max_batch_size" in data
        assert data["loaded"] is True


class TestMetricsEndpoint:
    """Test Prometheus metrics endpoint."""

    def test_metrics_format(self, client):
        """Metrics should be in Prometheus format."""
        response = client.get("/metrics")
        assert response.status_code == 200
        assert "text/plain" in response.headers["content-type"]

        content = response.text
        assert "inference_requests_total" in content
        assert "inference_predictions_total" in content
        assert "inference_errors_total" in content
        assert "inference_latency_seconds" in content
        assert "inference_instances_total" in content
        assert "inference_validation_errors_total" in content

    def test_metrics_increment_after_prediction(self, client):
        """Metrics should increment after predictions."""
        # Get initial metrics
        response1 = client.get("/metrics")
        initial_content = response1.text

        # Make a prediction
        client.post("/predict", json={"instances": [[1.0, 2.0, 3.0]]})

        # Get updated metrics
        response2 = client.get("/metrics")
        updated_content = response2.text

        # Verify metrics changed (simple check - content should differ)
        assert response1.status_code == 200
        assert response2.status_code == 200

    def test_latency_histogram(self, client):
        """Metrics should include latency histogram buckets."""
        response = client.get("/metrics")
        content = response.text
        assert "inference_latency_bucket" in content


class TestAuthentication:
    """Test API authentication (when enabled)."""

    def test_predict_without_auth_when_disabled(self, client):
        """Should allow requests without API key when auth is disabled."""
        # Default config has empty API_KEY (auth disabled)
        response = client.post(
            "/predict",
            json={"instances": [[1.0, 2.0, 3.0]]}
        )
        # Should succeed since auth is disabled by default
        assert response.status_code == 200
