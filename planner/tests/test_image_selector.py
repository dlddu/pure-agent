"""Tests for planner.image_selector -- LLM-based image selection."""

import json
from unittest.mock import patch

from planner.environments import DEFAULT_ENVIRONMENT_ID, ENVIRONMENT_MAP
from planner.image_selector import select_image_via_llm


class TestSelectImageViaLlm:
    def test_fallback_when_no_base_url(self):
        """Without ANTHROPIC_BASE_URL, falls back to default."""
        image, raw_id = select_image_via_llm("some task", anthropic_base_url="", api_key="test")
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id == "_NO_BASE_URL"

    def test_fallback_on_network_error(self):
        """On connection error, falls back to default with error detail."""
        image, raw_id = select_image_via_llm(
            "some task",
            anthropic_base_url="http://localhost:1",
            api_key="test",
        )
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id is not None and raw_id.startswith("_ERROR:")

    def test_selects_python_environment(self):
        """When LLM returns python-analysis, resolves to python image."""

        def mock_response(*args, **kwargs):
            from unittest.mock import MagicMock

            resp = MagicMock()
            resp.read.return_value = json.dumps(
                {"content": [{"type": "text", "text": '{"environment_id": "python-analysis"}'}]}
            ).encode()
            resp.__enter__ = lambda s: s
            resp.__exit__ = lambda s, *a: None
            return resp

        with patch("urllib.request.urlopen", side_effect=mock_response):
            image, raw_id = select_image_via_llm(
                "pandas 데이터 분석", anthropic_base_url="http://fake", api_key="test"
            )
        assert "python-agent" in image
        assert raw_id == "python-analysis"

    def test_selects_infra_environment(self):
        """When LLM returns infra, resolves to infra image."""

        def mock_response(*args, **kwargs):
            from unittest.mock import MagicMock

            resp = MagicMock()
            resp.read.return_value = json.dumps(
                {"content": [{"type": "text", "text": '{"environment_id": "infra"}'}]}
            ).encode()
            resp.__enter__ = lambda s: s
            resp.__exit__ = lambda s, *a: None
            return resp

        with patch("urllib.request.urlopen", side_effect=mock_response):
            image, raw_id = select_image_via_llm(
                "kubectl deploy", anthropic_base_url="http://fake", api_key="test"
            )
        assert "infra-agent" in image
        assert raw_id == "infra"

    def test_strips_markdown_code_fence(self):
        """When LLM wraps JSON in markdown code fences, still parses correctly."""

        def mock_response(*args, **kwargs):
            from unittest.mock import MagicMock

            resp = MagicMock()
            resp.read.return_value = json.dumps(
                {"content": [{"type": "text", "text": '```json\n{"environment_id": "infra"}\n```'}]}
            ).encode()
            resp.__enter__ = lambda s: s
            resp.__exit__ = lambda s, *a: None
            return resp

        with patch("urllib.request.urlopen", side_effect=mock_response):
            image, raw_id = select_image_via_llm(
                "kubectl deploy", anthropic_base_url="http://fake", api_key="test"
            )
        assert "infra-agent" in image
        assert raw_id == "infra"

    def test_strips_markdown_code_fence_no_newline(self):
        """When LLM wraps JSON in code fences without newlines."""

        def mock_response(*args, **kwargs):
            from unittest.mock import MagicMock

            resp = MagicMock()
            resp.read.return_value = json.dumps(
                {
                    "content": [
                        {"type": "text", "text": '```json{"environment_id": "python-analysis"}```'}
                    ]
                }
            ).encode()
            resp.__enter__ = lambda s: s
            resp.__exit__ = lambda s, *a: None
            return resp

        with patch("urllib.request.urlopen", side_effect=mock_response):
            image, raw_id = select_image_via_llm(
                "pandas analysis", anthropic_base_url="http://fake", api_key="test"
            )
        assert "python-agent" in image
        assert raw_id == "python-analysis"

    def test_unknown_environment_falls_back(self):
        """When LLM returns unknown ID, falls back to default."""

        def mock_response(*args, **kwargs):
            from unittest.mock import MagicMock

            resp = MagicMock()
            resp.read.return_value = json.dumps(
                {"content": [{"type": "text", "text": '{"environment_id": "unknown-env"}'}]}
            ).encode()
            resp.__enter__ = lambda s: s
            resp.__exit__ = lambda s, *a: None
            return resp

        with patch("urllib.request.urlopen", side_effect=mock_response):
            image, raw_id = select_image_via_llm(
                "something", anthropic_base_url="http://fake", api_key="test"
            )
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id == "unknown-env"

    def test_malformed_llm_response_falls_back(self):
        """When LLM returns non-JSON text, falls back to default."""

        def mock_response(*args, **kwargs):
            from unittest.mock import MagicMock

            resp = MagicMock()
            resp.read.return_value = json.dumps(
                {"content": [{"type": "text", "text": "I think you should use python"}]}
            ).encode()
            resp.__enter__ = lambda s: s
            resp.__exit__ = lambda s, *a: None
            return resp

        with patch("urllib.request.urlopen", side_effect=mock_response):
            image, raw_id = select_image_via_llm(
                "something", anthropic_base_url="http://fake", api_key="test"
            )
        assert image == ENVIRONMENT_MAP[DEFAULT_ENVIRONMENT_ID].image
        assert raw_id is not None and raw_id.startswith("_PARSE_TEXT:")
