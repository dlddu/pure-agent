"""Tests for router entry point -- subprocess execution via ``python -m router``."""

from tests.conftest import run_subprocess


class TestEntryPoint:
    def test_script_runs_as_subprocess(self, work_env):
        """python -m router invokes run() via __main__.py."""
        result = run_subprocess(work_env, "--depth", "0", "--max-depth", "5")
        assert result.returncode == 0
        assert (work_env / "output.txt").read_text() == "true\n"
        assert "decision=CONTINUE" in result.stderr

    def test_script_stops_when_export_config_provided(self, work_env):
        """Subprocess returns 0 and writes 'false' when export_config is provided."""
        result = run_subprocess(
            work_env,
            "--depth",
            "0",
            "--max-depth",
            "5",
            "--export-config",
            '{"action":"report"}',
        )
        assert result.returncode == 0
        assert (work_env / "output.txt").read_text() == "false\n"
        assert "decision=STOP" in result.stderr

    def test_script_stops_at_depth_limit(self, work_env):
        """Subprocess at depth limit writes false output."""
        result = run_subprocess(work_env, "--depth", "4", "--max-depth", "5")
        assert result.returncode == 0
        assert (work_env / "output.txt").read_text() == "false\n"
        assert "decision=STOP" in result.stderr

    def test_script_exits_2_on_invalid_args(self, work_env):
        """Subprocess exits 2 when required args are missing."""
        result = run_subprocess(work_env)
        assert result.returncode == 2
        assert not (work_env / "output.txt").exists()
