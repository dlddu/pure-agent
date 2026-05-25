"""Tests for gate.config -- GateConfig, TranscriptUploadConfig, and constants."""

import pytest

from gate.config import (
    EXPORT_CONFIG_FILENAME,
    TRANSCRIPT_DIR_NAME,
    GateConfig,
    TranscriptUploadConfig,
)


class TestGateConfig:
    def test_from_env_default_work_dir(self, monkeypatch):
        """Default WORK_DIR is /work when env var is unset."""
        monkeypatch.delenv("WORK_DIR", raising=False)
        cfg = GateConfig.from_env()
        assert cfg.export_config == "/work/export_config.json"
        assert cfg.transcript_dir == "/work/.transcripts"

    def test_from_env_custom_work_dir(self, monkeypatch):
        """WORK_DIR env var overrides the default path."""
        monkeypatch.setenv("WORK_DIR", "/custom/dir")
        cfg = GateConfig.from_env()
        assert cfg.export_config == "/custom/dir/export_config.json"
        assert cfg.transcript_dir == "/custom/dir/.transcripts"

    def test_from_env_uses_module_constants(self, monkeypatch):
        """from_env() builds paths using EXPORT_CONFIG_FILENAME."""
        monkeypatch.setenv("WORK_DIR", "/test")
        cfg = GateConfig.from_env()
        assert cfg.export_config == f"/test/{EXPORT_CONFIG_FILENAME}"
        assert cfg.transcript_dir == f"/test/{TRANSCRIPT_DIR_NAME}"

    def test_frozen(self):
        """GateConfig is immutable."""
        cfg = GateConfig(export_config="/a", transcript_dir="/b")
        with pytest.raises(AttributeError):
            cfg.export_config = "/changed"


class TestTranscriptUploadConfig:
    def test_from_env_returns_none_when_url_not_set(self, monkeypatch):
        monkeypatch.delenv("TRANSCRIPT_UPLOAD_API_URL", raising=False)
        assert TranscriptUploadConfig.from_env() is None

    def test_from_env_returns_none_when_url_empty(self, monkeypatch):
        monkeypatch.setenv("TRANSCRIPT_UPLOAD_API_URL", "")
        assert TranscriptUploadConfig.from_env() is None

    def test_from_env_returns_config_when_url_set(self, monkeypatch):
        monkeypatch.setenv("TRANSCRIPT_UPLOAD_API_URL", "http://viewer.svc:3000")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.api_base_url == "http://viewer.svc:3000"

    def test_from_env_default_timeout(self, monkeypatch):
        monkeypatch.setenv("TRANSCRIPT_UPLOAD_API_URL", "http://viewer.svc:3000")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.timeout == 30.0

    def test_frozen(self):
        cfg = TranscriptUploadConfig(api_base_url="http://viewer.svc:3000")
        with pytest.raises(AttributeError):
            cfg.api_base_url = "changed"
