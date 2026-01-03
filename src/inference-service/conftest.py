"""Pytest configuration for inference service tests."""

import sys
from pathlib import Path

# Add the inference-service directory to Python path
# This allows tests to import from 'app' module
sys.path.insert(0, str(Path(__file__).parent))
