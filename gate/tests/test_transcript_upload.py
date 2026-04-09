"""Tests for gate.transcript_upload -- S3 transcript upload logic."""

from pathlib import Path
from unittest.mock import MagicMock

import pytest

from gate.config import TranscriptUploadConfig
from gate.transcript_upload import (
    _collect_uploads,
    _find_transcript_files,
    upload_transcripts,
)


@pytest.fixture
def upload_config() -> TranscriptUploadConfig:
    return TranscriptUploadConfig(bucket_name="my-bucket", region="ap-northeast-2")


@pytest.fixture
def mock_s3() -> MagicMock:
    return MagicMock()


# ── _find_transcript_files ──────────────────────────────


class TestFindTranscriptFiles:
    def test_returns_empty_when_dir_missing(self, tmp_path):
        result = _find_transcript_files(str(tmp_path / "nonexistent"))
        assert result == []

    def test_returns_empty_when_dir_is_empty(self, tmp_path):
        result = _find_transcript_files(str(tmp_path))
        assert result == []

    def test_finds_jsonl_files(self, tmp_path):
        (tmp_path / "abc123.jsonl").write_text("")
        (tmp_path / "def456.jsonl").write_text("")
        result = _find_transcript_files(str(tmp_path))
        assert len(result) == 2
        assert all(f.endswith(".jsonl") for f in result)

    def test_skips_non_jsonl_files(self, tmp_path):
        (tmp_path / "readme.txt").write_text("")
        (tmp_path / "data.json").write_text("")
        (tmp_path / "session.jsonl").write_text("")
        result = _find_transcript_files(str(tmp_path))
        assert len(result) == 1

    def test_skips_empty_session_id(self, tmp_path):
        (tmp_path / ".jsonl").write_text("")
        (tmp_path / "valid.jsonl").write_text("")
        result = _find_transcript_files(str(tmp_path))
        assert len(result) == 1
        assert "valid.jsonl" in result[0]


# ── _collect_uploads ────────────────────────────────────


class TestCollectUploads:
    def test_main_transcript_only(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        assert len(uploads) == 1
        assert uploads[0].key == "abc123.jsonl"

    def test_main_plus_subagents(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        subagent_dir = tmp_path / "abc123" / "subagents"
        subagent_dir.mkdir(parents=True)
        (subagent_dir / "sub1.jsonl").write_text("")
        (subagent_dir / "sub2.jsonl").write_text("")

        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        keys = {u.key for u in uploads}
        assert keys == {"abc123.jsonl", "abc123/sub1.jsonl", "abc123/sub2.jsonl"}

    def test_no_subagent_dir(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        assert len(uploads) == 1

    def test_ignores_non_jsonl_in_subagents(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        subagent_dir = tmp_path / "abc123" / "subagents"
        subagent_dir.mkdir(parents=True)
        (subagent_dir / "sub1.jsonl").write_text("")
        (subagent_dir / "notes.txt").write_text("")

        uploads = _collect_uploads(str(tmp_path), [transcript_file])
        keys = {u.key for u in uploads}
        assert keys == {"abc123.jsonl", "abc123/sub1.jsonl"}

    def test_prefix_prepended_to_main_and_subagent_keys(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        subagent_dir = tmp_path / "abc123" / "subagents"
        subagent_dir.mkdir(parents=True)
        (subagent_dir / "sub1.jsonl").write_text("")

        uploads = _collect_uploads(str(tmp_path), [transcript_file], "env/prod")
        keys = {u.key for u in uploads}
        assert keys == {"env/prod/abc123.jsonl", "env/prod/abc123/sub1.jsonl"}

    def test_empty_prefix_leaves_keys_unchanged(self, tmp_path):
        transcript_file = str(tmp_path / "abc123.jsonl")
        Path(transcript_file).write_text("")
        uploads = _collect_uploads(str(tmp_path), [transcript_file], "")
        assert [u.key for u in uploads] == ["abc123.jsonl"]


# ── upload_transcripts ──────────────────────────────────


class TestUploadTranscripts:
    def test_returns_zero_when_no_transcript_dir(self, tmp_path, upload_config, mock_s3):
        count = upload_transcripts(str(tmp_path / "nonexistent"), upload_config, mock_s3)
        assert count == 0
        mock_s3.put_object.assert_not_called()

    def test_returns_zero_when_no_jsonl_files(self, tmp_path, upload_config, mock_s3):
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 0

    def test_uploads_single_file(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("transcript data")
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 1
        mock_s3.put_object.assert_called_once_with(
            Bucket="my-bucket",
            Key="abc123.jsonl",
            Body=b"transcript data",
            ContentType="application/jsonl",
        )

    def test_uploads_with_subagents(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("main")
        sub_dir = tmp_path / "abc123" / "subagents"
        sub_dir.mkdir(parents=True)
        (sub_dir / "sub1.jsonl").write_text("sub1")
        (sub_dir / "sub2.jsonl").write_text("sub2")

        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 3
        assert mock_s3.put_object.call_count == 3

    def test_uploads_multiple_sessions(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "session1.jsonl").write_text("s1")
        (tmp_path / "session2.jsonl").write_text("s2")
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 2

    def test_s3_error_propagates(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("data")
        mock_s3.put_object.side_effect = Exception("Access Denied")
        with pytest.raises(Exception, match="Access Denied"):
            upload_transcripts(str(tmp_path), upload_config, mock_s3)

    def test_uploads_only_main_when_subagents_dir_missing(self, tmp_path, upload_config, mock_s3):
        (tmp_path / "abc123.jsonl").write_text("data")
        count = upload_transcripts(str(tmp_path), upload_config, mock_s3)
        assert count == 1
        mock_s3.put_object.assert_called_once_with(
            Bucket="my-bucket",
            Key="abc123.jsonl",
            Body=b"data",
            ContentType="application/jsonl",
        )

    def test_uploads_with_prefix(self, tmp_path, mock_s3):
        config = TranscriptUploadConfig(
            bucket_name="my-bucket", region="ap-northeast-2", prefix="env/prod"
        )
        (tmp_path / "abc123.jsonl").write_text("data")
        sub_dir = tmp_path / "abc123" / "subagents"
        sub_dir.mkdir(parents=True)
        (sub_dir / "sub1.jsonl").write_text("sub")

        count = upload_transcripts(str(tmp_path), config, mock_s3)
        assert count == 2
        keys = {call.kwargs["Key"] for call in mock_s3.put_object.call_args_list}
        assert keys == {"env/prod/abc123.jsonl", "env/prod/abc123/sub1.jsonl"}

    def test_creates_client_with_endpoint_url(self, tmp_path, monkeypatch):
        """When endpoint_url is set, boto3 client receives it (for LocalStack)."""
        config = TranscriptUploadConfig(
            bucket_name="test-bucket",
            region="us-east-1",
            endpoint_url="http://localhost:4566",
        )
        (tmp_path / "session.jsonl").write_text("data")

        from unittest.mock import patch

        import boto3

        with patch.object(boto3, "client", wraps=boto3.client) as spy_client:
            mock_client = MagicMock()
            spy_client.return_value = mock_client
            upload_transcripts(str(tmp_path), config)
            spy_client.assert_called_once_with(
                "s3", region_name="us-east-1", endpoint_url="http://localhost:4566"
            )

    def test_creates_client_without_endpoint_url_when_none(self, tmp_path, monkeypatch):
        """When endpoint_url is None, boto3 client is created without it."""
        config = TranscriptUploadConfig(
            bucket_name="test-bucket",
            region="us-east-1",
            endpoint_url=None,
        )
        (tmp_path / "session.jsonl").write_text("data")

        from unittest.mock import patch

        import boto3

        with patch.object(boto3, "client", wraps=boto3.client) as spy_client:
            mock_client = MagicMock()
            spy_client.return_value = mock_client
            upload_transcripts(str(tmp_path), config)
            spy_client.assert_called_once_with("s3", region_name="us-east-1")

    def test_assume_role_uses_sts_credentials_for_s3_client(self, tmp_path):
        """When assume_role_arn is set, STS AssumeRole is called and creds flow into S3 client."""
        config = TranscriptUploadConfig(
            bucket_name="test-bucket",
            region="us-east-1",
            assume_role_arn="arn:aws:iam::123456789012:role/GateUploader",
        )
        (tmp_path / "session.jsonl").write_text("data")

        from unittest.mock import patch

        import boto3

        sts_client = MagicMock()
        sts_client.assume_role.return_value = {
            "Credentials": {
                "AccessKeyId": "AKIAFAKE",
                "SecretAccessKey": "secret",
                "SessionToken": "token",
                "Expiration": "2030-01-01T00:00:00Z",
            }
        }
        s3_client = MagicMock()

        def fake_client(service: str, **kwargs):
            if service == "sts":
                return sts_client
            if service == "s3":
                return s3_client
            raise AssertionError(f"unexpected service {service}")

        with patch.object(boto3, "client", side_effect=fake_client) as spy_client:
            upload_transcripts(str(tmp_path), config)

        sts_client.assume_role.assert_called_once_with(
            RoleArn="arn:aws:iam::123456789012:role/GateUploader",
            RoleSessionName="gate-transcript-upload",
        )
        # STS client created with region
        assert spy_client.call_args_list[0].args == ("sts",)
        assert spy_client.call_args_list[0].kwargs == {"region_name": "us-east-1"}
        # S3 client created with temporary credentials
        assert spy_client.call_args_list[1].args == ("s3",)
        assert spy_client.call_args_list[1].kwargs == {
            "region_name": "us-east-1",
            "aws_access_key_id": "AKIAFAKE",
            "aws_secret_access_key": "secret",
            "aws_session_token": "token",
        }
        s3_client.put_object.assert_called_once()

    def test_assume_role_skipped_when_arn_not_set(self, tmp_path):
        """Without assume_role_arn, STS is never called."""
        config = TranscriptUploadConfig(
            bucket_name="test-bucket",
            region="us-east-1",
        )
        (tmp_path / "session.jsonl").write_text("data")

        from unittest.mock import patch

        import boto3

        with patch.object(boto3, "client") as spy_client:
            spy_client.return_value = MagicMock()
            upload_transcripts(str(tmp_path), config)

        services_called = [call.args[0] for call in spy_client.call_args_list]
        assert services_called == ["s3"]

    def test_assume_role_passes_endpoint_url_to_sts(self, tmp_path):
        """endpoint_url is forwarded to the STS client too (useful for LocalStack)."""
        config = TranscriptUploadConfig(
            bucket_name="test-bucket",
            region="us-east-1",
            endpoint_url="http://localhost:4566",
            assume_role_arn="arn:aws:iam::123456789012:role/GateUploader",
        )
        (tmp_path / "session.jsonl").write_text("data")

        from unittest.mock import patch

        import boto3

        sts_client = MagicMock()
        sts_client.assume_role.return_value = {
            "Credentials": {
                "AccessKeyId": "AKIAFAKE",
                "SecretAccessKey": "secret",
                "SessionToken": "token",
                "Expiration": "2030-01-01T00:00:00Z",
            }
        }
        s3_client = MagicMock()

        def fake_client(service: str, **kwargs):
            return sts_client if service == "sts" else s3_client

        with patch.object(boto3, "client", side_effect=fake_client) as spy_client:
            upload_transcripts(str(tmp_path), config)

        assert spy_client.call_args_list[0].kwargs == {
            "region_name": "us-east-1",
            "endpoint_url": "http://localhost:4566",
        }
        assert spy_client.call_args_list[1].kwargs == {
            "region_name": "us-east-1",
            "endpoint_url": "http://localhost:4566",
            "aws_access_key_id": "AKIAFAKE",
            "aws_secret_access_key": "secret",
            "aws_session_token": "token",
        }
