# scripts/

One-shot host-setup + project-management scripts. None of these are needed during normal build/deploy — they're for first-time setup, mod renaming, and the Blender MCP install.

| Script | What it does | When to run |
|---|---|---|
| `setup.sh` | Interactive first-time setup. Generates `gradle.properties` from `.example` (asks for mod metadata), generates `config.sh` from `.example` (asks for MultiMC mods dir + preview output dir), offers to run `rename_mod.sh` and `install_blender_mcp.sh`. | Once, right after cloning. |
| `rename_mod.sh <new_id> <new_group_id>` | Renames `mod_id` and `mod_group_id` throughout the source tree — Java packages, asset dirs, JSON refs, Python paths. Reversible by running again with the old values. | When forking this scaffold for a new mod. `setup.sh` will offer to call this automatically. |
| `install_blender_mcp.sh` | Idempotent installer for the headless Blender + BlenderMCP pipeline (required for Tier B polygonal rendering). Installs Blender 5.x (sudo), `uv`, clones the patched fork, installs the addon, symlinks `tools/corelib_obj_export.py` into Blender's user modules dir, verifies the project-local launcher, registers the MCP server with Claude Code. Pass `--check` to report state without changing anything. | Once per host, only if you plan to use Tier B. |
| `blender_mcp_start_headless.sh` | Starts the headless Blender server on TCP 9876. Checked-in here as the canonical (and only) copy — the install script just verifies it's executable. Locates its sibling `.py` via its own path, so it works from any cwd. | After install, every time you want the Blender server up. |
| `blender_mcp_start_headless.py` | Python startup script that the launcher hands to `blender -b --python`. Enables the addon and runs the MCP socket server on the main thread. | Called by the launcher; not run directly. |

## Typical first-time flow

```sh
git clone <this-repo>
cd ai-minecraft-mobs-creator
scripts/setup.sh           # answer the prompts; this calls install_blender_mcp.sh at the end if you say yes
source config.sh
./gradlew build
```

## Manual reset / redo

If `setup.sh` produced something you want to redo:

```sh
rm gradle.properties config.sh        # delete the generated copies
scripts/setup.sh --force              # or just: scripts/setup.sh — will skip if files exist, --force overwrites
```

For Blender MCP uninstall (manual; not part of any script):

```sh
pkill -f "blender -b --python.*blender_mcp_start_headless"
sudo rm -rf /opt/blender /usr/local/bin/blender
rm -rf ~/repos/blender-mcp
rm -f ~/.config/blender/*/scripts/addons/blender_mcp.py
rm -f ~/.config/blender/*/scripts/modules/corelib_obj_export.py
claude mcp remove "blender" -s user
```
