"""Tests for router.cli -- CLI argument parsing, orchestration, error handling."""

import json
import logging
import sys
from pathlib import Path

import pytest

from router.cli import _write_fallback_output, main, run
from tests.conftest import (
    OUTPUT_PLACEHOLDER,
    decision_message,
    run_main,
    single_log,
)

# ── main: integration ────────────────────────────────────


class TestMain:
    def test_stop_when_export_config_provided(self, work_env, monkeypatch, caplog):
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(
                monkeypatch,
                work_env,
                depth=0,
                max_depth=5,
                export_config='{"actions":["none"]}',
            )
        assert out.strip() == "false"
        assert decision_message(caplog) == ("depth=0/5 decision=STOP reason=export_config provided")

    def test_stop_at_depth_limit(self, work_env, monkeypatch, caplog):
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(monkeypatch, work_env, depth=4, max_depth=5)
        assert out.strip() == "false"
        assert decision_message(caplog) == ("depth=4/5 decision=STOP reason=depth limit (4/5)")

    def test_continue_when_under_limit(self, work_env, monkeypatch, caplog):
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(monkeypatch, work_env, depth=0, max_depth=5)
        assert out.strip() == "true"
        assert decision_message(caplog) == (
            "depth=0/5 decision=CONTINUE reason=no export_config, continuing"
        )

    def test_continue_at_nonzero_depth(self, work_env, monkeypatch, caplog):
        """Continue decision works at mid-range depth, not just depth=0."""
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(monkeypatch, work_env, depth=2, max_depth=5)
        assert out.strip() == "true"
        assert decision_message(caplog) == (
            "depth=2/5 decision=CONTINUE reason=no export_config, continuing"
        )

    def test_both_stop_conditions_uses_export_config(self, work_env, monkeypatch, caplog):
        """When export_config provided AND at depth limit, export_config reason wins."""
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(
                monkeypatch,
                work_env,
                depth=4,
                max_depth=5,
                export_config='{"actions":["report"]}',
            )
        assert out.strip() == "false"
        assert decision_message(caplog) == ("depth=4/5 decision=STOP reason=export_config provided")

    def test_continue_action_returns_true(self, work_env, monkeypatch, caplog):
        """When export_config has continue action, router returns true."""
        (work_env / "export_config.json").write_text('{"actions":["continue"]}')
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(
                monkeypatch,
                work_env,
                depth=0,
                max_depth=5,
                export_config='{"actions":["continue"]}',
            )
        assert out.strip() == "true"
        assert decision_message(caplog) == (
            "depth=0/5 decision=CONTINUE reason=continue action requested"
        )
        assert not (work_env / "export_config.json").exists()


class TestMainWithSingleQuotes:
    """Integration tests for JSON containing single quotes passed via CLI."""

    def test_stop_with_single_quote_in_summary(self, work_env, monkeypatch, caplog):
        export_config = json.dumps({"summary": "it's done", "actions": ["none"]})
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(
                monkeypatch,
                work_env,
                depth=0,
                max_depth=5,
                export_config=export_config,
            )
        assert out.strip() == "false"
        assert decision_message(caplog) == ("depth=0/5 decision=STOP reason=export_config provided")

    def test_continue_with_single_quote_in_pr_title(self, work_env, monkeypatch, caplog):
        export_config = json.dumps(
            {
                "actions": ["continue"],
                "pr": {"title": "fix: handle it's edge case"},
            }
        )
        (work_env / "export_config.json").write_text(export_config)
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(
                monkeypatch,
                work_env,
                depth=0,
                max_depth=5,
                export_config=export_config,
            )
        assert out.strip() == "true"
        assert not (work_env / "export_config.json").exists()


# ── _write_fallback_output ───────────────────────────────


class TestWriteFallbackOutput:
    def test_writes_false_when_output_arg_present(self, tmp_path, monkeypatch, caplog):
        """Fallback writes 'false' to the --output path and logs it."""
        out = str(tmp_path / "fallback.txt")
        monkeypatch.setattr(sys, "argv", ["router", "--output", out])
        with caplog.at_level(logging.INFO, logger="router"):
            _write_fallback_output()
        assert Path(out).read_text() == "false\n"
        rec = single_log(caplog, lambda r: "fallback" in r.message, "fallback")
        assert rec.message == f"Wrote fallback output: false -> {out}"

    @pytest.mark.parametrize(
        "argv",
        [
            pytest.param(["router", "--depth", "0"], id="no-output-arg"),
            pytest.param(["router", "--output"], id="output-is-last-arg"),
            pytest.param(["router", "--output", ""], id="empty-string-output"),
        ],
    )
    def test_silently_returns_when_output_missing_or_dangling(
        self, tmp_path, monkeypatch, caplog, argv
    ):
        """When --output has no value, is absent, or is empty, silently returns."""
        monkeypatch.setattr(sys, "argv", argv)
        with caplog.at_level(logging.INFO, logger="router"):
            _write_fallback_output()
        assert "fallback" not in caplog.text
        assert list(tmp_path.iterdir()) == []

    def test_silently_returns_when_path_unwritable(self, monkeypatch, caplog):
        """When --output points to a nonexistent directory, silently returns."""
        bad_path = "/nonexistent-dir/output.txt"
        monkeypatch.setattr(sys, "argv", ["router", "--output", bad_path])
        with caplog.at_level(logging.INFO, logger="router"):
            _write_fallback_output()
        assert "fallback" not in caplog.text
        assert not Path(bad_path).exists()

    def test_uses_first_output_when_duplicated(self, tmp_path, monkeypatch, caplog):
        """When --output appears twice, fallback uses the first occurrence."""
        first = str(tmp_path / "first.txt")
        second = str(tmp_path / "second.txt")
        monkeypatch.setattr(sys, "argv", ["router", "--output", first, "--output", second])
        with caplog.at_level(logging.INFO, logger="router"):
            _write_fallback_output()
        assert Path(first).read_text() == "false\n"
        assert not Path(second).exists()


# ── argument parsing ─────────────────────────────────────


class TestArgs:
    @pytest.mark.parametrize(
        "argv_template",
        [
            pytest.param(
                [
                    "router",
                    "--max-depth",
                    "5",
                    "--export-config",
                    "{}",
                    "--output",
                    OUTPUT_PLACEHOLDER,
                ],
                id="missing-depth",
            ),
            pytest.param(
                ["router", "--depth", "0", "--export-config", "{}", "--output", OUTPUT_PLACEHOLDER],
                id="missing-max-depth",
            ),
            pytest.param(
                ["router", "--depth", "0", "--max-depth", "5", "--export-config", "{}"],
                id="missing-output",
            ),
        ],
    )
    def test_missing_required_arg_exits(self, monkeypatch, tmp_path, argv_template):
        """Omitting any required argument causes exit code 2."""
        output_path = str(tmp_path / "o.txt")
        argv = [output_path if a == OUTPUT_PLACEHOLDER else a for a in argv_template]
        monkeypatch.setattr(sys, "argv", argv)
        with pytest.raises(SystemExit) as exc_info:
            main()
        assert exc_info.value.code == 2

    @pytest.mark.parametrize(
        "argv_template",
        [
            pytest.param(
                [
                    "router",
                    "--depth",
                    "-1",
                    "--max-depth",
                    "5",
                    "--export-config",
                    "{}",
                    "--output",
                    OUTPUT_PLACEHOLDER,
                ],
                id="negative-depth",
            ),
            pytest.param(
                [
                    "router",
                    "--depth",
                    "0",
                    "--max-depth",
                    "0",
                    "--export-config",
                    "{}",
                    "--output",
                    OUTPUT_PLACEHOLDER,
                ],
                id="zero-max-depth",
            ),
            pytest.param(
                [
                    "router",
                    "--depth",
                    "abc",
                    "--max-depth",
                    "5",
                    "--export-config",
                    "{}",
                    "--output",
                    OUTPUT_PLACEHOLDER,
                ],
                id="non-integer-depth",
            ),
            pytest.param(
                [
                    "router",
                    "--depth",
                    "0",
                    "--max-depth",
                    "1.5",
                    "--export-config",
                    "{}",
                    "--output",
                    OUTPUT_PLACEHOLDER,
                ],
                id="float-max-depth",
            ),
            pytest.param(
                [
                    "router",
                    "--depth",
                    "0",
                    "--max-depth",
                    "-1",
                    "--export-config",
                    "{}",
                    "--output",
                    OUTPUT_PLACEHOLDER,
                ],
                id="negative-max-depth",
            ),
        ],
    )
    def test_invalid_arg_exits(self, monkeypatch, tmp_path, argv_template):
        """Invalid argument values cause exit code 2."""
        output_path = str(tmp_path / "o.txt")
        argv = [output_path if a == OUTPUT_PLACEHOLDER else a for a in argv_template]
        monkeypatch.setattr(sys, "argv", argv)
        with pytest.raises(SystemExit) as exc_info:
            main()
        assert exc_info.value.code == 2


# ── run: error boundary ──────────────────────────────────


class TestRun:
    def test_crash_exits_with_code_1(self, crash_env, caplog):
        """If main() throws, run() exits 1 and logs the exception."""
        with caplog.at_level(logging.ERROR, logger="router"):
            with pytest.raises(SystemExit) as exc_info:
                run()
        assert exc_info.value.code == 1
        rec = single_log(caplog, lambda r: r.levelno >= logging.ERROR, "error")
        assert rec.getMessage() == "Router crashed with unhandled exception"
        assert isinstance(rec.exc_info[1], RuntimeError)
        assert str(rec.exc_info[1]) == "disk full"

    def test_crash_writes_fallback_output(self, crash_env):
        """If main() crashes, run() should write 'false' to the output file."""
        with pytest.raises(SystemExit):
            run()
        assert Path(crash_env).read_text().strip() == "false"

    def test_systemexit_propagates(self, work_env, monkeypatch, caplog):
        """Argparse errors (SystemExit) propagate through run() without fallback or error log."""
        output_path = str(work_env / "fallback.txt")
        monkeypatch.setattr(
            sys, "argv", ["router", "--output", output_path]
        )  # missing --depth and --max-depth
        with caplog.at_level(logging.ERROR, logger="router"):
            with pytest.raises(SystemExit) as exc_info:
                run()
        assert exc_info.value.code == 2  # argparse convention
        assert not Path(output_path).exists(), "fallback output must not be written on SystemExit"
        error_logs = [r for r in caplog.records if r.levelno >= logging.ERROR]
        assert error_logs == [], "SystemExit must not trigger error logging"

    def test_success_does_not_invoke_fallback(self, run_env, monkeypatch):
        """On successful execution, _write_fallback_output is never called."""
        from router import cli

        fallback_called = False

        def _spy_fallback():
            nonlocal fallback_called
            fallback_called = True

        monkeypatch.setattr(cli, "_write_fallback_output", _spy_fallback)
        run()
        assert not fallback_called, "_write_fallback_output must not be called on success"

    def test_happy_path_returns_normally(self, run_env):
        """run() returns without raising when main() succeeds."""
        run()  # should not raise
        assert Path(run_env).read_text() == "true\n"


# ── transcript upload integration ───────────────────────


class TestTranscriptUploadIntegration:
    def test_upload_skipped_when_no_aws_config(self, work_env, monkeypatch, caplog):
        """When AWS_S3_BUCKET_NAME is not set, upload is skipped gracefully."""
        monkeypatch.delenv("AWS_S3_BUCKET_NAME", raising=False)
        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(monkeypatch, work_env, depth=0, max_depth=5)
        assert out.strip() == "true"
        assert "Transcript upload skipped" in caplog.text

    def test_upload_called_after_routing_decision(self, work_env, monkeypatch, caplog):
        """Transcript upload runs after routing decision is written."""
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "test-bucket")
        from unittest.mock import MagicMock

        import router.transcript_upload as tu

        mock_upload = MagicMock(return_value=1)
        monkeypatch.setattr(tu, "upload_transcripts", mock_upload)

        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(monkeypatch, work_env, depth=0, max_depth=5)
        assert out.strip() == "true"
        mock_upload.assert_called_once()
        assert "Transcript upload complete: 1 file(s)" in caplog.text

    def test_upload_failure_does_not_affect_routing(self, work_env, monkeypatch, caplog):
        """Transcript upload failure is logged but does not change the routing output."""
        monkeypatch.setenv("AWS_S3_BUCKET_NAME", "test-bucket")
        from unittest.mock import MagicMock

        import router.transcript_upload as tu

        monkeypatch.setattr(tu, "upload_transcripts", MagicMock(side_effect=Exception("S3 down")))

        with caplog.at_level(logging.INFO, logger="router"):
            out = run_main(monkeypatch, work_env, depth=0, max_depth=5)
        assert out.strip() == "true"
        assert "Transcript upload failed (non-fatal)" in caplog.text
