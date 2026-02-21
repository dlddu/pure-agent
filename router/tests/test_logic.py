"""Tests for router.logic -- core routing decision functions."""

import json
import logging
from pathlib import Path

import pytest

from router.logic import should_continue, write_output
from tests.conftest import single_log

# ── should_continue ──────────────────────────────────────


class TestShouldContinue:
    def test_stop_when_export_config_provided(self, config):
        cont, reason = should_continue(config, '{"actions":["none"]}', 0, 5)
        assert cont is False
        assert reason == "export_config provided"

    @pytest.mark.parametrize(
        "depth, max_depth, expected, expected_reason",
        [
            (0, 1, False, "depth limit (0/1)"),  # minimum valid max_depth -> stop immediately
            (3, 5, True, "no export_config, continuing"),  # one below boundary -> continue
            (4, 5, False, "depth limit (4/5)"),  # at boundary -> stop
            (5, 5, False, "depth limit (5/5)"),  # past boundary -> stop
            (0, 10, True, "no export_config, continuing"),  # well under limit -> continue
            (9, 10, False, "depth limit (9/10)"),  # at boundary with different max -> stop
        ],
    )
    def test_depth_boundary(self, config, depth, max_depth, expected, expected_reason):
        """Depth limit: stop when depth >= max_depth - 1."""
        cont, reason = should_continue(config, "{}", depth, max_depth)
        assert cont is expected
        assert reason == expected_reason

    def test_stop_when_export_config_is_empty_string(self, config):
        """An empty string is treated as no config (continue under depth limit)."""
        cont, reason = should_continue(config, "", 0, 5)
        assert cont is True
        assert reason == "no export_config, continuing"

    def test_export_config_takes_priority_over_depth(self, config):
        cont, reason = should_continue(config, '{"actions":["none"]}', 4, 5)
        assert cont is False
        assert reason == "export_config provided"


class TestShouldContinueWithContinueAction:
    def test_continue_action_returns_true(self, config):
        cont, reason = should_continue(config, '{"actions":["continue"]}', 0, 5)
        assert cont is True
        assert reason == "continue action requested"

    def test_continue_action_deletes_config_file(self, config):
        Path(config.export_config).write_text('{"actions":["continue"]}')
        should_continue(config, '{"actions":["continue"]}', 0, 5)
        assert not Path(config.export_config).exists()

    def test_continue_action_when_no_file_on_disk(self, config):
        """Continue action works even if there's no file on disk (just warns)."""
        cont, reason = should_continue(config, '{"actions":["continue"]}', 0, 5)
        assert cont is True
        assert reason == "continue action requested"

    def test_non_continue_action_stops(self, config):
        cont, reason = should_continue(config, '{"actions":["report"]}', 0, 5)
        assert cont is False
        assert reason == "export_config provided"

    def test_malformed_json_stops(self, config):
        cont, reason = should_continue(config, "not json", 0, 5)
        assert cont is False
        assert "unparseable" in reason

    def test_missing_actions_key_stops(self, config):
        """Old format with 'action' (singular) falls back to stop."""
        cont, reason = should_continue(config, '{"action":"none"}', 0, 5)
        assert cont is False
        assert reason == "export_config provided"

    def test_empty_actions_stops(self, config):
        cont, reason = should_continue(config, '{"actions":[]}', 0, 5)
        assert cont is False
        assert reason == "export_config provided"


class TestShouldContinueWithSingleQuotes:
    """JSON values containing single quotes must be handled correctly."""

    def test_stop_with_single_quote_in_summary(self, config):
        data = {"summary": "it's done", "actions": ["none"]}
        cont, reason = should_continue(config, json.dumps(data), 0, 5)
        assert cont is False
        assert reason == "export_config provided"

    def test_continue_with_single_quote_in_summary(self, config):
        data = {"summary": "it's continuing", "actions": ["continue"]}
        cont, reason = should_continue(config, json.dumps(data), 0, 5)
        assert cont is True
        assert reason == "continue action requested"

    def test_multiple_single_quotes(self, config):
        data = {"summary": "user's task isn't done, let's retry", "actions": ["report"]}
        cont, reason = should_continue(config, json.dumps(data), 0, 5)
        assert cont is False
        assert reason == "export_config provided"

    def test_single_quote_in_nested_field(self, config):
        data = {
            "actions": ["create_pr"],
            "pr": {"title": "fix: handle it's edge case", "body": "don't break"},
        }
        cont, reason = should_continue(config, json.dumps(data), 0, 5)
        assert cont is False
        assert reason == "export_config provided"


# ── write_output ─────────────────────────────────────────


class TestWriteOutput:
    @pytest.mark.parametrize("value", ["true", "false"])
    def test_writes_value_with_newline(self, tmp_path, caplog, value):
        """Output file contains the value followed by exactly one newline."""
        out = str(tmp_path / "output.txt")
        with caplog.at_level(logging.INFO, logger="router"):
            write_output(value, out)
        assert Path(out).read_text() == value + "\n"
        rec = single_log(caplog, lambda r: r.message.startswith("Output:"), "Output")
        assert rec.message == f"Output: {value} -> {out}"

    def test_raises_oserror_when_directory_missing(self, tmp_path):
        """write_output raises OSError when the output directory does not exist."""
        out = str(tmp_path / "nonexistent_dir" / "output.txt")
        with pytest.raises(OSError):
            write_output("false", out)

    def test_overwrites_existing_file(self, tmp_path):
        """Writing output replaces any previous content."""
        out = str(tmp_path / "output.txt")
        Path(out).write_text("old-content\n")
        write_output("false", out)
        assert Path(out).read_text() == "false\n"
