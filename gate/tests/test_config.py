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
    def test_from_env_returns_none_when_bucket_not_set(self, monkeypatch):
        monkeypatch.delenv("AWS_S3_BUCKET_NAME", raising=False)
        assert TranscriptUploadConfig.from_env() is None

    def test_from_env_returns_none_when_bucket_empty(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "")
        assert TranscriptUploadConfig.from_env() is None

    def test_from_env_returns_config_when_bucket_set(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.setenv("AWS_REGION", "us-west-2")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.bucket_name == "my-bucket"
        assert cfg.region == "us-west-2"

    def test_from_env_uses_default_region(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.delenv("AWS_REGION", raising=False)
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.region == "ap-northeast-2"

    def test_from_env_reads_endpoint_url(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.setenv("AWS_ENDPOINT_URL", "http://localhost:4566")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.endpoint_url == "http://localhost:4566"

    def test_from_env_endpoint_url_defaults_to_none(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.delenv("AWS_ENDPOINT_URL", raising=False)
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.endpoint_url is None

    def test_from_env_endpoint_url_empty_string_becomes_none(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.setenv("AWS_ENDPOINT_URL", "")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.endpoint_url is None

    def test_from_env_prefix_defaults_to_empty(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.delenv("AWS_S3_PREFIX", raising=False)
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.prefix == ""

    def test_from_env_prefix_plain(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.setenv("AWS_S3_PREFIX", "transcripts")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.prefix == "transcripts"

    def test_from_env_prefix_strips_trailing_slash(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.setenv("AWS_S3_PREFIX", "transcripts/")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.prefix == "transcripts"

    def test_from_env_prefix_strips_leading_and_trailing_slashes(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.setenv("AWS_S3_PREFIX", "/transcripts/")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.prefix == "transcripts"

    def test_from_env_prefix_preserves_interior_slashes(self, monkeypatch):
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "my-bucket")
        monkeypatch.setenv("AWS_S3_PREFIX", "foo/bar/baz")
        cfg = TranscriptUploadConfig.from_env()
        assert cfg is not None
        assert cfg.prefix == "foo/bar/baz"

    def test_frozen(self):
        cfg = TranscriptUploadConfig(bucket_name="b", region="r")
        with pytest.raises(AttributeError):
            cfg.bucket_name = "changed"
