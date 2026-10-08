"""Tests for CLI entry point."""

import os
from unittest.mock import patch

import pytest

from pg_mcp.__main__ import main


class TestMain:
    def test_invalid_transport_exits(self) -> None:
        with patch.dict(os.environ, {"MCP_TRANSPORT": "invalid"}, clear=False):
            with pytest.raises(SystemExit, match="Unsupported MCP_TRANSPORT"):
                main()

    def test_default_stdio_transport(self) -> None:
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("MCP_TRANSPORT", None)
            with patch("pg_mcp.__main__.mcp.run") as mock_run:
                main()
                mock_run.assert_called_once_with(transport="stdio")

    def test_streamable_http_transport(self) -> None:
        with patch.dict(os.environ, {"MCP_TRANSPORT": "streamable-http"}, clear=False):
            with patch("pg_mcp.__main__.mcp.run") as mock_run:
                main()
                mock_run.assert_called_once_with(transport="streamable-http")
