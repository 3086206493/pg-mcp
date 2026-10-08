"""Main entry point for PostgreSQL MCP Server.

This module provides the CLI entry point for running the MCP server
using FastMCP with stdio transport.
"""

import os

import anyio

from pg_mcp.server import mcp


def main() -> None:
    """Main entry point for the PostgreSQL MCP Server.

    Transport is selected via MCP_TRANSPORT env var:
      - stdio (default): for Claude Desktop
      - sse / streamable-http: HTTP server on 0.0.0.0:8000
    """
    transport = os.getenv("MCP_TRANSPORT", "stdio").strip().lower()
    if transport not in {"stdio", "sse", "streamable-http"}:
        raise SystemExit(f"Unsupported MCP_TRANSPORT={transport!r}")
    mcp.run(transport=transport)  # type: ignore[arg-type]


if __name__ == "__main__":
    main()
