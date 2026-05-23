#!/usr/bin/env bash
# Start headless Blender with the BlenderMCP socket server on TCP 9876.
# The Claude Code MCP client (uvx blender-mcp) connects to this.
#
# Usage (run from anywhere — the script locates its sibling .py via its own path):
#   scripts/blender_mcp_start_headless.sh                                            # foreground
#   nohup scripts/blender_mcp_start_headless.sh > /tmp/blender-mcp.log 2>&1 &        # background
#   BLENDER_PORT=9999 scripts/blender_mcp_start_headless.sh                          # custom port
#   pkill -f "blender -b --python.*blender_mcp_start_headless"                       # stop
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
export BLENDER_PORT="${BLENDER_PORT:-9876}"
exec blender -b --python "$SCRIPT_DIR/blender_mcp_start_headless.py"
