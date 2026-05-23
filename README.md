# AI Minecraft Mobs and Blocks Creator

An AI agent–driven scaffold for creating custom Minecraft mobs and blocks. You tell an agent (Claude Code) *"make me a fire-breathing pumpkin mob,"* it generates the 3D model, generates the texture, writes the Java entity classes, builds the mod jar, deploys it to your MultiMC instance, and renders multi-angle previews so you can review before launching the game.

**This is not a normal Minecraft mod.** It's a tooling repository that AI agents work in. Cloning it gets you the scaffolding; the agent fills in the actual mod content.

## First-time prerequisites (one-time per host)

You need these in place **before** cloning, or `scripts/setup.sh` will tell you what's missing and stop:

1. **JDK 21** — Mojang's runtime since 1.20.5:
   ```sh
   sudo apt install openjdk-21-jdk
   ```

2. **A Minecraft launcher with a 1.21.1 + NeoForge instance.** [Prism Launcher](https://prismlauncher.org/) is the recommended fork (active development); MultiMC also works:
   ```sh
   flatpak install -y flathub org.prismlauncher.PrismLauncher   # recommended
   # OR
   sudo apt install multimc                                      # older fork
   ```
   Then in the launcher:
   - **Add Instance** → **Custom** → Minecraft **`1.21.1`**
   - **Add Loader** → **NeoForge** → **`21.1.230`** (any 21.1.x works)
   - Name it anything (e.g. "AI mobs creator") → **Create**
   - Log in with your Microsoft/Mojang account when the launcher prompts

3. **Claude Code** — see [claude.com/claude-code](https://claude.com/claude-code). The scaffold's `CLAUDE.md` is written for it.

4. *(Optional, only for polygonal Tier B mobs)* **Blender** — `scripts/install_blender_mcp.sh` handles the install after clone; skip this if you only want blocky Tier A mobs.

5. *(Optional, for AI-generated textures)* **OpenAI codex CLI** with a ChatGPT subscription. The scaffold falls back to hand-coded Pillow textures if codex isn't available.

Once 1–3 are done, the three commands below get you building.

## How to use it

Three commands to get going from scratch:

```sh
git clone https://github.com/shrimpwagon/ai-minecraft-mobs-creator.git
cd ai-minecraft-mobs-creator
./scripts/setup.sh          # interactive — first-time only; asks for mod metadata + local paths
                            # (also offers to run scripts/install_blender_mcp.sh if you want
                            # the polygonal-mob tier; say yes if you want it, otherwise skip)
claude                      # start Claude Code in this directory
```

That's the entire setup. Once `claude` is running, just tell it what to build in plain English:

**Mobs:**
> *"Make me a fire-breathing pumpkin mob with vine tendrils."*
> *"Build a friendly hovering cube mob with a glowing core."*
> *"Create a teleporting jellyfish that drops blue dye."*

**Blocks:**
> *"Add a block that turns nearby water into lava."*
> *"Make a translucent crystal that gives Speed II when stood on."*
> *"A gold ore block but every layer of stone underneath turns to ore for 30 seconds when broken."*

**Items, weapons, armor:**
> *"Make me a flaming sword that sets enemies on fire on hit."*
> *"Add a healing potion that gives Regeneration III for 10 seconds."*
> *"Create a magnetic helmet that pulls dropped items toward me within 8 blocks."*
> *"A glowing crystal pickaxe with diamond-tier stats but 3x durability."*

Claude reads `CLAUDE.md` automatically and handles the full pipeline for each request:

1. Asks you two quick clarifying questions in plain language — how should it look (big blocks / lots of small blocks / smooth shapes) and how to make the texture (paint pixels myself / let AI generate it).
2. Generates the 3D model, the texture, the Java entity class + renderer, and the loot table.
3. Renders multi-angle previews to your Desktop so you can eyeball it before launching the game.
4. Runs `./gradlew build` and copies the resulting jar to your MultiMC instance — Claude already knows the path from your `config.sh`.

Then load your MultiMC instance, summon the mob (`/summon myfirstmod:<name>`), and test. Iterate by telling Claude what to change — *"the head is too small,"* *"give him a red coat,"* *"make him hostile."*

## Requirements

| Requirement | Notes |
|---|---|
| **OS** | Linux (developed and tested on Linux Mint). Probably works on macOS, untested. Probably does NOT work on Windows without WSL. |
| **Minecraft** | 1.21.1 (the version is locked across the gradle config, gotcha mitigations, and library versions) |
| **Mod loader** | NeoForge 21.1.230 (NOT Fabric, NOT legacy Forge) |
| **Java** | JDK 21 |
| **Launcher** | [MultiMC](https://multimc.org/) or [Prism Launcher](https://prismlauncher.org/) — strongly recommended. Multi-instance management is much easier than with the vanilla launcher, especially for testing modded 1.21.1 alongside other versions / modpacks. |
| **AI agent** | [Claude Code](https://www.anthropic.com/claude-code) — the scaffold's `CLAUDE.md` is written for it. |
| **AI texture generation (optional)** | [OpenAI codex CLI](https://github.com/openai/codex) with a ChatGPT subscription, for AI-generated textures. Falls back to hand-coded Pillow Python for textures if codex isn't available. |
| **Blender 5.x (optional)** | Only required if you're going to use Tier B (polygonal mobs). `scripts/install_blender_mcp.sh` installs everything (Blender tarball + patched BlenderMCP socket server + Applications-menu integration). |

## How the agent uses this scaffold

The agent reads **[CLAUDE.md](CLAUDE.md)** on first encounter. From that single file it knows everything it needs:

- The two clarifying questions to ask before building any new mob or block (visual style + texture method, phrased in plain language).
- Where the two **helpers** in `tools/` live and what they do — deliberately narrow:
  - `tools/codex_image.py` wraps the codex CLI's `image_gen` tool, handling the four codex landmines.
  - `tools/corelib_obj_export.py` is a Blender-Python module that the installer symlinks into Blender's user modules dir. The agent imports it from inside any Blender Python call (via the BlenderMCP socket) to write a corelib-compatible OBJ with the four format gotchas (face triplets, V-flip, triangulation, CCW winding check) handled.
- For Tier B (polygonal) mobs, the agent drives Blender directly via the BlenderMCP socket — building the mesh with bmesh (rotated cubes, spheres, cones, sculpted geometry, anything Blender can express), assigning UVs however it wants, then calling `corelib_obj_export` to dump the OBJ. No PARTS-list constraint, no per-mob driver scripts.
- Before declaring a polygonal mob done, the agent renders multi-angle previews in the same Blender call and **pauses for user creative review** before writing any Java.
- For blocks, items, weapons, and armor the agent writes Java + JSON + texture-gen directly from the rules in CLAUDE.md; there are no helpers because there are no gotchas to prevent.
- All technical reference (rendering tiers, OBJ format gotchas, headless Blender landmines, codex landmines, Java/JSON templates) lives in the Technical reference section at the bottom of **[CLAUDE.md](CLAUDE.md)**. Everything the agent needs is in that one file.

The agent should not need to "poke around" to figure out the workflow. If it does, that's a doc bug — open an issue.

## File layout

```
.
├── README.md                        ← this file (human-facing docs)
├── CLAUDE.md                        ← all agent-facing rules + technical reference
├── LICENSE                          ← MIT
├── gradle.properties.example        ← committed template
├── config.example.sh                ← committed template
├── build.gradle, settings.gradle, gradlew, gradle/
│
├── scripts/                         ← one-shot host setup + project management
│   ├── setup.sh                     ← first-time interactive setup
│   ├── rename_mod.sh                ← rename mod_id throughout the source
│   ├── install_blender_mcp.sh       ← idempotent Blender + BlenderMCP installer (Tier B only)
│   └── blender_mcp_start_headless.{sh,py}   ← the Blender server launcher
│
├── tools/                           ← narrow helpers — only where they prevent real failure modes
│   ├── codex_image.py               ← codex CLI wrapper for AI texture generation (default for textures)
│   └── corelib_obj_export.py        ← Blender-Python module: format-only OBJ exporter for Tier B mobs
│                                      (symlinked into ~/.config/blender/<v>/scripts/modules/ by the installer
│                                       so any Blender Python call can `import corelib_obj_export` directly)
│
└── src/main/                        ← standard NeoForge MDK Java + resources
    ├── java/com/<group>/<mod_id>/   ← Java source: entity/, block/, client/, Mod*.java, MyFirstMod.java
    └── resources/
        ├── META-INF/neoforge.mods.toml
        ├── assets/<mod_id>/         ← animations/, blockstates/, geo/, lang/, models/, textures/
        └── data/<mod_id>/loot_table/{blocks,entities}/
```

## Build & deploy (after a mob/block has been added)

```sh
source config.sh                                  # loads MULTIMC_MODS_DIR + PREVIEW_OUTPUT_DIR
./gradlew build                                   # → build/libs/<mod_id>-<version>.jar
cp build/libs/*.jar "$MULTIMC_MODS_DIR"           # deploy to your MultiMC instance
```

Your MultiMC instance also needs the **GeckoLib** and **henkelmax/corelib** runtime jars. They're declared as Maven deps for the build, but Minecraft needs them present at runtime. `scripts/setup.sh` offers to auto-download and install both into your instance during first-time setup; or fetch them yourself from CurseForge/Modrinth.

Reload the world (or load a fresh one), summon the mob with `/summon <mod_id>:<name>`, and you're testing.

## Headless Blender install (Tier B mobs only)

Tier B (polygonal) mobs need a headless Blender exposing the BlenderMCP socket on TCP 9876. Skip this entire section if you only plan to build Tier A (cube-based) mobs and blocks.

```sh
scripts/install_blender_mcp.sh             # interactive — sudo, installs Blender + addon + launcher
scripts/install_blender_mcp.sh --check     # report what's installed, change nothing
```

This installs Blender 5.x to `/opt/blender/`, the patched BlenderMCP addon ([upstream PR #252](https://github.com/ahujasid/blender-mcp/pull/252) — needed for `-b` headless mode), `uv` for `uvx blender-mcp`, and symlinks `tools/corelib_obj_export.py` into Blender's user-modules dir.

Start / verify / stop the server:

```sh
nohup scripts/blender_mcp_start_headless.sh > /tmp/blender-mcp.log 2>&1 &     # background
ss -tlnp | grep 9876                                                            # verify listening
pkill -f "blender -b --python.*blender_mcp_start_headless"                      # stop
```

The agent will auto-start the launcher in the background when it needs Tier B — so usually you don't have to touch this after the one-time install.

## The two rendering tiers

The agent picks one of two rendering tiers per mob, based on the visual look you describe. Full decision rubric + technical depth lives in [CLAUDE.md](CLAUDE.md).

| Tier | Look | Library | Animation |
|---|---|---|---|
| **A simple** | Big blocky cuboids — vanilla Minecraft style | GeckoLib | Per-bone (walks, attacks, etc.) |
| **A detailed** | Many small cuboids — Alex's Mobs / Mowzie's Mobs style | GeckoLib | Per-bone |
| **B polygonal** | Anything Blender can model — tilted parts, organic shapes, sculpted geometry, smooth curves, rotated boxes | henkelmax/corelib | Whole-model transforms only (bob, sway, spin) |

The scaffold ships with **no example mobs or blocks** — that's intentional. Every asset is built fresh from your conversation with the agent, so no prior asset's style or proportions leak into a new build.

## Customizing for your own mod

`scripts/setup.sh` will offer to rename the mod from `aitemplate` to whatever you choose. The rename script (`scripts/rename_mod.sh`) updates:

- `src/main/java/<group>/<id>/` directory and every `.java` file's package + `MODID`
- `src/main/resources/assets/<id>/` and `data/<id>/`
- Every `"<old-id>:..."` reference in JSON, TOML, Python

You can re-run it later if you change your mind: `scripts/rename_mod.sh <new_id> <new_group_id>`.

## Credits

- [NeoForged](https://neoforged.net/) — the mod loader
- [GeckoLib](https://github.com/bernie-g/geckolib) (Bernie G.) — Tier A entity rendering library
- [henkelmax/corelib](https://github.com/henkelmax/corelib) (Max Henkel) — Tier B polygonal entity rendering library. As of May 2026, the only off-the-shelf polygonal-mesh loader for NeoForge 1.21.1.
- [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp) — Blender ↔ MCP bridge. This scaffold uses a [patched fork](https://github.com/shrimpwagon/blender-mcp/tree/headless-bg-mode-timer-fix) (upstream [PR #252](https://github.com/ahujasid/blender-mcp/pull/252)) for headless mode support.

## License

MIT — see [LICENSE](LICENSE).
