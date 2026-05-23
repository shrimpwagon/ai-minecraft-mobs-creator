"""Headless Blender startup: enable BlenderMCP addon, run server on main thread.

Loaded by the sibling ``blender_mcp_start_headless.sh`` via ``blender -b --python``.
"""
import os
import signal
import sys
import bpy

PORT = int(os.environ.get('BLENDER_PORT') or 9876)

print("[blender-mcp] enabling addon...", flush=True)
try:
    bpy.ops.preferences.addon_enable(module='blender_mcp')
except Exception as e:
    print(f"[blender-mcp] addon_enable failed: {e}", file=sys.stderr, flush=True)
    sys.exit(1)

import blender_mcp as mcp_addon

server = mcp_addon.BlenderMCPServer(host='0.0.0.0', port=PORT)
bpy.types.blendermcp_server = server
bpy.context.scene.blendermcp_server_running = True

def _shutdown(signum, _frame):
    print(f"[blender-mcp] signal {signum}, stopping server", flush=True)
    try:
        server.stop()
    finally:
        sys.exit(0)

signal.signal(signal.SIGTERM, _shutdown)
signal.signal(signal.SIGINT, _shutdown)

# In background mode, server.start() now blocks on the main thread,
# running the accept loop here. No more `while True: sleep` workaround.
# (This requires the patched addon — see ~/repos/blender-mcp branch
# headless-bg-mode-timer-fix / upstream PR #252.)
server.start()
