#!/usr/bin/env bash
# install_blender_mcp.sh — rebuild the headless Blender + BlenderMCP pipeline.
#
# Idempotent: each step checks what's already in place and skips it.
# Safe to re-run after a partial install or to verify a healthy setup.
#
# Usage:
#   scripts/install_blender_mcp.sh             # install / repair (interactive sudo)
#   scripts/install_blender_mcp.sh --check     # report current state, change nothing
#
# Prerequisites assumed to already be on the host:
#   - sudo access (for the Blender tarball install in step 1)
#   - gh CLI authenticated (to check upstream PR state in step 3)
#   - claude CLI authenticated (to register the MCP server in step 6)
#   - SSH key with github.com access (to clone the fork — falls back to HTTPS if missing)
#
# Tear-down (manual; not part of this script):
#   pkill -f "blender -b --python.*blender_mcp_start_headless"
#   sudo rm -rf /opt/blender /usr/local/bin/blender
#   rm -rf ~/repos/blender-mcp
#   rm -f ~/.config/blender/*/scripts/addons/blender_mcp.py
#   rm -f ~/.config/blender/*/scripts/modules/corelib_obj_export.py
#   claude mcp remove "blender" -s user
#
# Related docs:
#   - ~/.claude/CLAUDE.md "Headless Blender + BlenderMCP" section (landmines list)
#   - ~/repos/blender-mcp (the user's patched fork; branch headless-bg-mode-timer-fix)
#   - Upstream PR https://github.com/ahujasid/blender-mcp/pull/252

set -euo pipefail

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

# Fail fast if stdin isn't a TTY — this script has interactive prompts and a
# sudo step, both of which need a real terminal. AI agents calling this from
# a non-interactive shell (e.g. Bash tool with no PTY) would otherwise hang
# for minutes waiting for input.
if [[ $CHECK_ONLY -eq 0 ]] && ! [ -t 0 ]; then
    echo "ERROR: install_blender_mcp.sh is interactive (prompts for sudo + confirmation)." >&2
    echo "       Run it from a real terminal, not from an automated/piped session." >&2
    echo "       If you're an AI agent: tell the user to run this themselves via the !-prefix." >&2
    echo "       For a read-only state report, pass --check instead." >&2
    exit 1
fi

# ---- pretty logging ----
log()  { printf "\033[1;36m[step]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m  ✓\033[0m %s\n" "$*"; }
skip() { printf "\033[1;33m  ⊝ skip\033[0m %s\n" "$*"; }
note() { printf "         \033[0;37m%s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m  ✗ %s\033[0m\n" "$*" >&2; }

ask() {
    local prompt="$1"
    read -r -p "         → $prompt [y/N]: " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# ---- pre-flight: probe current state ----
log "Pre-flight checks"
BL_BIN=$(command -v blender || true)
UV_BIN=$(command -v uv || true)
REPO_DIR="$HOME/repos/blender-mcp"
# Project-local launcher (checked-in, no per-host copy needed).
PROJECT_ROOT="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
LAUNCHER_SH="$PROJECT_ROOT/scripts/blender_mcp_start_headless.sh"
LAUNCHER_PY="$PROJECT_ROOT/scripts/blender_mcp_start_headless.py"

ADDON_PATH=""
for d in "$HOME"/.config/blender/*/scripts/addons/blender_mcp.py; do
    [[ -f "$d" ]] && ADDON_PATH="$d"
done

MCP_REGISTERED=0
if claude mcp get blender >/dev/null 2>&1; then
    MCP_REGISTERED=1
fi

printf "  %-13s %s\n" "blender:"   "${BL_BIN:-MISSING}"
printf "  %-13s %s\n" "uv:"        "${UV_BIN:-MISSING}"
printf "  %-13s %s\n" "fork:"      "$([[ -d $REPO_DIR ]] && echo $REPO_DIR || echo MISSING)"
printf "  %-13s %s\n" "launcher:"  "$([[ -f $LAUNCHER_SH && -f $LAUNCHER_PY ]] && echo OK || echo MISSING)"
printf "  %-13s %s\n" "addon:"     "${ADDON_PATH:-MISSING}"
printf "  %-13s %s\n" "MCP cfg:"   "$([[ $MCP_REGISTERED -eq 1 ]] && echo OK || echo MISSING)"

[[ $CHECK_ONLY -eq 1 ]] && exit 0
echo

# ============================================================================
# 1. Install Blender from blender.org tarball (apt's is too old; snap disabled)
# ============================================================================
log "[1/7] Blender"
if [[ -z "$BL_BIN" ]]; then
    LATEST=$(curl -s https://download.blender.org/release/Blender5.1/ \
        | grep -oE 'blender-5\.1\.[0-9]+-linux-x64\.tar\.xz' \
        | sort -uV | tail -1)
    if [[ -z "$LATEST" ]]; then
        err "Couldn't determine latest Blender 5.1.x tarball from blender.org"
        exit 1
    fi
    note "latest 5.1.x tarball on blender.org: $LATEST"
    URL="https://download.blender.org/release/Blender5.1/$LATEST"
    TARBALL="/tmp/$LATEST"
    EXTRACTED_DIR="${LATEST%.tar.xz}"

    if [[ ! -f "$TARBALL" ]]; then
        note "downloading to $TARBALL (≈400 MB)..."
        curl -fsSL -o "$TARBALL" "$URL"
    else
        note "tarball already in /tmp, reusing"
    fi

    if ! ask "Run sudo to extract into /opt and symlink to /usr/local/bin/blender?"; then
        err "Aborted by user."
        exit 1
    fi
    sudo tar -xJf "$TARBALL" -C /opt
    sudo mv "/opt/$EXTRACTED_DIR" /opt/blender
    sudo ln -sf /opt/blender/blender /usr/local/bin/blender
    ok "installed: $(blender -b --version | head -1)"
else
    skip "already installed at $BL_BIN ($(blender -b --version | head -1))"
fi

# Register .desktop file + icons for apps-menu integration (the tarball already
# ships them; we just have to drop them in the user's local share). This gives
# Blender the same "Applications menu" presence as an apt-install, without
# downgrading from the latest 5.x tarball to an older apt version (Ubuntu noble /
# Mint 22 only ship 4.0.2). Idempotent.
if [[ -f /opt/blender/blender.desktop && ! -f "$HOME/.local/share/applications/blender.desktop" ]]; then
    log "[1b/7] menu integration (.desktop + icons)"
    mkdir -p "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/scalable/apps"
    # Use the symlink path in Exec — works regardless of where Blender lives
    sed 's|^Exec=blender|Exec=/usr/local/bin/blender|' /opt/blender/blender.desktop \
        > "$HOME/.local/share/applications/blender.desktop"
    [[ -f /opt/blender/blender.svg          ]] && cp /opt/blender/blender.svg          "$HOME/.local/share/icons/hicolor/scalable/apps/blender.svg"
    [[ -f /opt/blender/blender-symbolic.svg ]] && cp /opt/blender/blender-symbolic.svg "$HOME/.local/share/icons/hicolor/scalable/apps/blender-symbolic.svg"
    # Refresh caches — most DEs pick changes up automatically, but cinnamon/mate sometimes need a nudge
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    gtk-update-icon-cache -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
    ok "registered Blender in the apps menu (log out / back in if it doesn't show immediately)"
else
    skip "menu integration already registered (or tarball didn't ship a .desktop file)"
fi

# ============================================================================
# 2. uv (the Python tool runner used by `uvx blender-mcp`)
# ============================================================================
log "[2/7] uv"
if [[ -z "$UV_BIN" ]]; then
    note "installing via astral.sh script"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # add to PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
    ok "installed: $(uv --version)"
else
    skip "already at $UV_BIN ($(uv --version))"
fi

# ============================================================================
# 3. Clone the patched fork (or upstream, if PR #252 has merged)
# ============================================================================
log "[3/7] blender-mcp repo"
if [[ ! -d "$REPO_DIR" ]]; then
    mkdir -p "$HOME/repos"
    PR_STATE=$(gh pr view 252 --repo ahujasid/blender-mcp --json state -q .state 2>/dev/null || echo "UNKNOWN")
    note "upstream PR #252 state: $PR_STATE"

    if [[ "$PR_STATE" == "MERGED" ]]; then
        note "patch is upstream — cloning ahujasid/blender-mcp (no local fix needed)"
        git clone https://github.com/ahujasid/blender-mcp.git "$REPO_DIR"
    else
        note "patch still local — cloning fork shrimpwagon/blender-mcp"
        if ! git clone git@github.com:shrimpwagon/blender-mcp.git "$REPO_DIR" 2>/dev/null; then
            note "SSH clone failed, falling back to HTTPS"
            git clone https://github.com/shrimpwagon/blender-mcp.git "$REPO_DIR"
        fi
        (cd "$REPO_DIR" && git checkout headless-bg-mode-timer-fix)
    fi
    ok "cloned to $REPO_DIR"
else
    skip "fork already cloned at $REPO_DIR"
fi

# ============================================================================
# 4. Install addon into Blender's user-scripts dir (path is version-dependent)
# ============================================================================
log "[4/7] addon"
if [[ -z "$ADDON_PATH" ]]; then
    # Ask Blender itself where its addons dir is — adapts to whatever Blender version is installed
    ADDON_DIR=$(blender -b --python-expr \
        "import bpy; print('ADDON_DIR=' + bpy.utils.user_resource('SCRIPTS', path='addons', create=True))" \
        2>&1 | grep -oE '/home[^ ]+addons')
    if [[ -z "$ADDON_DIR" ]]; then
        err "couldn't resolve Blender's user-scripts addons dir"
        exit 1
    fi
    note "addons dir: $ADDON_DIR"
    cp "$REPO_DIR/addon.py" "$ADDON_DIR/blender_mcp.py"

    # smoke-test that the addon enables in headless mode
    if blender -b --python-expr \
        "import bpy; bpy.ops.preferences.addon_enable(module='blender_mcp'); print('ADDON_OK')" \
        2>&1 | grep -q "ADDON_OK"; then
        ok "addon installed and verified to enable headless"
    else
        err "addon copied but failed to enable headless — patch may be missing"
        exit 1
    fi
else
    skip "addon already at $ADDON_PATH"
fi

# ============================================================================
# 4b. Symlink corelib_obj_export.py into Blender's user modules dir.
#     Lets any Blender Python script run by the agent simply
#     `from corelib_obj_export import export_corelib_obj` — the OBJ
#     format-only exporter that handles corelib's gotchas.
# ============================================================================
log "[4b/7] corelib_obj_export module"
REPO_ROOT="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
SRC_MODULE="$REPO_ROOT/tools/corelib_obj_export.py"
if [[ ! -f "$SRC_MODULE" ]]; then
    err "expected $SRC_MODULE to exist — wrong repo layout?"
    exit 1
fi
MODULES_DIR=$(blender -b --python-expr \
    "import bpy; print('MODDIR=' + bpy.utils.user_resource('SCRIPTS', path='modules', create=True))" \
    2>&1 | grep -oE '/home[^ ]+modules')
if [[ -z "$MODULES_DIR" ]]; then
    err "couldn't resolve Blender's user-scripts modules dir"
    exit 1
fi
LINK_PATH="$MODULES_DIR/corelib_obj_export.py"
# Symlink so future edits in the repo propagate without re-running this step.
ln -sfn "$SRC_MODULE" "$LINK_PATH"
note "symlinked: $LINK_PATH -> $SRC_MODULE"
if blender -b --python-expr \
    "import corelib_obj_export; print('EXPORT_OK')" 2>&1 | grep -q "EXPORT_OK"; then
    ok "import smoke-test passed"
else
    err "Blender could not import corelib_obj_export — check $LINK_PATH"
    exit 1
fi

# ============================================================================
# 5. Launcher scripts — checked into the repo at scripts/blender_mcp_start_headless.{sh,py}.
#    Just verify they're present and executable; the canonical copies live
#    in the repo, no per-host duplicate in ~/scripts/.
# ============================================================================
log "[5/7] launcher scripts"
if [[ -f "$LAUNCHER_SH" && -f "$LAUNCHER_PY" ]]; then
    chmod +x "$LAUNCHER_SH"
    ok "project-local launcher present: $LAUNCHER_SH"
else
    err "expected $LAUNCHER_SH and $LAUNCHER_PY in the repo — wrong layout?"
    exit 1
fi

# ============================================================================
# 6. Register the MCP server with Claude Code (user scope)
# ============================================================================
log "[6/7] Claude Code MCP registration"
if [[ $MCP_REGISTERED -eq 0 ]]; then
    # Gotcha: `-e` is variadic in `claude mcp add`, so the server name MUST come
    # BEFORE -e — otherwise the parser slurps the name into the env-var list
    # and you get: "Invalid environment variable format: blender"
    claude mcp add blender --scope user -e DISABLE_TELEMETRY=true -- uvx blender-mcp
    ok "registered (user scope): $(claude mcp get blender | head -1)"
else
    skip "already registered: $(claude mcp get blender | head -1)"
fi

# ============================================================================
# 7. Smoke test
# ============================================================================
log "[7/7] smoke test"
pkill -f "blender -b --python.*blender_mcp_start_headless" 2>/dev/null && sleep 2 || true
nohup "$LAUNCHER_SH" > /tmp/blender-mcp.log 2>&1 &
disown
sleep 4
if ss -tlnp 2>/dev/null | grep -q ':9876'; then
    ok "listening on 0.0.0.0:9876"
else
    err "port 9876 not listening — last 20 lines of /tmp/blender-mcp.log:"
    tail -20 /tmp/blender-mcp.log
    exit 1
fi

echo
echo "=========================================================="
echo "All steps complete. Final verification:"
echo "  In a fresh Claude Code session, ask:"
echo '    "Use the blender MCP to get scene info."'
echo "  A successful response means the entire pipeline is wired."
echo "=========================================================="
