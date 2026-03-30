"""Tests for planner.mcp_config -- MCP client configuration generation."""

import json

from planner.mcp_config import get_mcp_config_path, write_mcp_config


class TestWriteMcpConfig:
    def test_writes_valid_json(self, tmp_path):
        config_path = str(tmp_path / "mcp.json")
        write_mcp_config(config_path, "mcp-server")
        config = json.loads((tmp_path / "mcp.json").read_text())
        assert "mcpServers" in config
        assert "pure-agent" in config["mcpServers"]
        assert config["mcpServers"]["pure-agent"]["type"] == "http"

    def test_uses_default_port(self, tmp_path):
        config_path = str(tmp_path / "mcp.json")
        write_mcp_config(config_path, "mcp-host")
        config = json.loads((tmp_path / "mcp.json").read_text())
        assert "8080" in config["mcpServers"]["pure-agent"]["url"]

    def test_uses_custom_port(self, tmp_path):
        config_path = str(tmp_path / "mcp.json")
        write_mcp_config(config_path, "mcp-host", mcp_port="9090")
        config = json.loads((tmp_path / "mcp.json").read_text())
        assert "9090" in config["mcpServers"]["pure-agent"]["url"]

    def test_url_format(self, tmp_path):
        config_path = str(tmp_path / "mcp.json")
        write_mcp_config(config_path, "my-host", mcp_port="8080")
        config = json.loads((tmp_path / "mcp.json").read_text())
        assert config["mcpServers"]["pure-agent"]["url"] == "http://my-host:8080/mcp"


class TestGetMcpConfigPath:
    def test_returns_path_with_default_base(self):
        path = get_mcp_config_path()
        assert path == "/tmp/planner_mcp.json"

    def test_returns_path_with_custom_base(self):
        path = get_mcp_config_path("/var/run")
        assert path == "/var/run/planner_mcp.json"
