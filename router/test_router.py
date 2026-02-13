"""Tests for router.py -- workflow routing decisions."""

import json
import sys
from datetime import datetime
from pathlib import Path

import pytest

import router


@pytest.fixture(autouse=True)
def isolate_paths(tmp_path, monkeypatch):
    """Redirect router file paths to tmp_path for every test."""
    state_path = str(tmp_path / "state.json")
    export_config_path = str(tmp_path / "export_config.json")
    monkeypatch.setattr(router, "STATE_PATH", state_path)
    monkeypatch.setattr(router, "EXPORT_CONFIG", export_config_path)


def _run_main(monkeypatch, capsys, depth, max_depth):
    """Set sys.argv and call main(), return captured stdout."""
    monkeypatch.setattr(
        sys, "argv",
        ["router.py", "--depth", str(depth), "--max-depth", str(max_depth)],
    )
    router.main()
    return capsys.readouterr().out


def _read_state():
    return json.loads(Path(router.STATE_PATH).read_text())


# ── load_state ──────────────────────────────────────────────


class TestLoadState:
    def test_returns_empty_history_when_file_missing(self):
        assert router.load_state() == {"history": []}

    def test_loads_valid_state_file(self):
        state = {"history": [{"depth": 0, "continue": True}]}
        Path(router.STATE_PATH).write_text(json.dumps(state))
        assert router.load_state() == state

    def test_returns_empty_history_on_corrupt_json(self):
        Path(router.STATE_PATH).write_text("not valid json{{")
        assert router.load_state() == {"history": []}

    def test_returns_empty_history_on_empty_file(self):
        Path(router.STATE_PATH).write_text("")
        assert router.load_state() == {"history": []}


# ── save_state ──────────────────────────────────────────────


class TestSaveState:
    def test_writes_state_as_json(self):
        state = {"history": [{"depth": 0}]}
        router.save_state(state)
        assert json.loads(Path(router.STATE_PATH).read_text()) == state

    def test_overwrites_existing_state(self):
        router.save_state({"history": [{"depth": 0}]})
        new_state = {"history": [{"depth": 1}]}
        router.save_state(new_state)
        assert json.loads(Path(router.STATE_PATH).read_text()) == new_state


# ── main: decision logic ───────────────────────────────────


class TestMainDecision:
    def test_stop_when_export_config_exists(self, monkeypatch, capsys):
        Path(router.EXPORT_CONFIG).write_text('{"action":"none"}')
        out = _run_main(monkeypatch, capsys, depth=0, max_depth=5)
        assert out.strip() == "false"

    def test_stop_at_depth_limit(self, monkeypatch, capsys):
        out = _run_main(monkeypatch, capsys, depth=4, max_depth=5)
        assert out.strip() == "false"

    def test_stop_when_depth_exceeds_limit(self, monkeypatch, capsys):
        out = _run_main(monkeypatch, capsys, depth=5, max_depth=5)
        assert out.strip() == "false"

    def test_continue_when_under_limit(self, monkeypatch, capsys):
        out = _run_main(monkeypatch, capsys, depth=0, max_depth=5)
        assert out.strip() == "true"

    def test_continue_at_one_below_limit(self, monkeypatch, capsys):
        out = _run_main(monkeypatch, capsys, depth=3, max_depth=5)
        assert out.strip() == "true"

    def test_export_config_takes_priority_over_depth(self, monkeypatch, capsys):
        Path(router.EXPORT_CONFIG).write_text('{"action":"none"}')
        out = _run_main(monkeypatch, capsys, depth=4, max_depth=5)
        assert out.strip() == "false"
        state = _read_state()
        assert "export_config" in state["history"][-1]["reason"]


# ── main: state accumulation ───────────────────────────────


class TestMainState:
    def test_appends_to_existing_history(self, monkeypatch, capsys):
        existing = {"history": [{"depth": 0, "continue": True, "reason": "prev", "timestamp": "t"}]}
        Path(router.STATE_PATH).write_text(json.dumps(existing))
        _run_main(monkeypatch, capsys, depth=1, max_depth=5)
        state = _read_state()
        assert len(state["history"]) == 2

    def test_entry_has_required_fields(self, monkeypatch, capsys):
        _run_main(monkeypatch, capsys, depth=0, max_depth=5)
        entry = _read_state()["history"][-1]
        assert set(entry.keys()) >= {"depth", "continue", "reason", "timestamp"}

    def test_timestamp_is_valid_iso(self, monkeypatch, capsys):
        _run_main(monkeypatch, capsys, depth=0, max_depth=5)
        ts = _read_state()["history"][-1]["timestamp"]
        datetime.fromisoformat(ts)


# ── main: argument parsing ─────────────────────────────────


class TestMainArgs:
    def test_missing_depth_exits(self, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["router.py", "--max-depth", "5"])
        with pytest.raises(SystemExit):
            router.main()

    def test_missing_max_depth_exits(self, monkeypatch):
        monkeypatch.setattr(sys, "argv", ["router.py", "--depth", "0"])
        with pytest.raises(SystemExit):
            router.main()
