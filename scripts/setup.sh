#!/usr/bin/env bash
# setup.sh — one-shot interactive setup for a fresh clone.
#
# Walks you through:
#   1. Generating gradle.properties from gradle.properties.example with your mod metadata
#   2. Generating config.sh from config.example.sh with your local paths
#   3. (Optional) Renaming the mod from `aitemplate` to your own mod id (runs rename_mod.sh)
#   4. (Optional) Installing the host-side headless Blender + BlenderMCP pipeline
#
# Idempotent: skips a step if the output file already exists, unless you pass --force.
#
# Usage:
#   scripts/setup.sh           # interactive
#   scripts/setup.sh --force   # overwrite existing gradle.properties / config.sh

set -euo pipefail

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# Fail fast if stdin isn't a TTY — this script is interactive throughout
# (mod metadata + path prompts, plus an inner call to install_blender_mcp.sh
# which needs sudo). AI agents must not call this directly; they should
# instruct the user to run it via the !-prefix in Claude Code.
if ! [ -t 0 ]; then
    echo "ERROR: setup.sh is interactive — needs a real terminal for prompts." >&2
    echo "       If you're an AI agent: tell the user to run this themselves via the !-prefix" >&2
    echo "       (e.g. ask them to type: !scripts/setup.sh )" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

log()  { printf "\033[1;36m[setup]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m  ✓\033[0m %s\n" "$*"; }
skip() { printf "\033[1;33m  ⊝ skip\033[0m %s\n" "$*"; }

prompt() {
    local message="$1"
    local default="$2"
    local var
    if [[ -n "$default" ]]; then
        read -r -p "  ${message} [${default}]: " var
        var="${var:-$default}"
    else
        read -r -p "  ${message}: " var
    fi
    echo "$var"
}

# ----------------------------------------------------------------------------
# 1. gradle.properties — mod metadata
# ----------------------------------------------------------------------------
log "[1/4] mod metadata → gradle.properties"
if [[ -f gradle.properties && $FORCE -eq 0 ]]; then
    skip "gradle.properties already exists (use --force to regenerate)"
else
    echo "  Each prompt has a default in [brackets]. Press enter to accept."
    MOD_ID=$(prompt   "mod_id (lowercase alphanumeric + underscores)" "aitemplate")
    MOD_NAME=$(prompt "mod_name (human-readable)"                    "AI Template Mod")
    MOD_AUTHORS=$(prompt "mod_authors (comma-separate multiple)"     "YourName")
    MOD_GROUP=$(prompt "mod_group_id (reverse-DNS PARENT — the Java pkg becomes <group>.<id>)" "com.${MOD_AUTHORS%%,*}")
    MOD_VERSION=$(prompt "mod_version"                               "1.0.0")
    MOD_LICENSE=$(prompt "mod_license (shown in the in-game Mods list; this does NOT rewrite LICENSE at repo root)" "MIT")
    MOD_DESC=$(prompt  "mod_description (one short sentence)"        "A NeoForge 1.21.1 mod.")
    echo
    echo "  Creative-mode tab (the in-game tab that holds all your mod's blocks/items/spawn-eggs):"
    TAB_NAME=$(prompt "tab display name"                             "$MOD_NAME")
    TAB_ICON=$(prompt "tab icon — vanilla Minecraft item name (e.g. barrier, grass_block, diamond, command_block, book)" "barrier")

    # Normalize icon to UPPER_SNAKE for Java's Items.X enum and validate the shape.
    # If the typed name doesn't resolve to a real Items constant, Gradle will fail with a
    # readable "cannot find symbol Items.FOO" — easier than re-implementing the registry.
    TAB_ICON_ENUM=$(printf '%s' "$TAB_ICON" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_\n' '_' | sed -e 's/^_*//; s/_*$//')
    if ! [[ "$TAB_ICON_ENUM" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        echo "  WARNING: tab icon '${TAB_ICON}' doesn't look like a Minecraft item id; falling back to BARRIER."
        TAB_ICON_ENUM="BARRIER"
    fi

    # Escape characters that have meaning in sed's replacement string ($ &, the delimiter |, and \)
    # so a mod_description like "A & B | C $foo" doesn't blow up.
    esc_for_sed() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
    # JSON-safe escape for the lang file value (escape backslash and double-quote).
    esc_for_json() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

    # write gradle.properties by templating the .example (using | delimiter since paths/desc may contain /)
    sed \
        -e "s|^mod_id=.*|mod_id=$(esc_for_sed "$MOD_ID")|" \
        -e "s|^mod_name=.*|mod_name=$(esc_for_sed "$MOD_NAME")|" \
        -e "s|^mod_authors=.*|mod_authors=$(esc_for_sed "$MOD_AUTHORS")|" \
        -e "s|^mod_group_id=.*|mod_group_id=$(esc_for_sed "$MOD_GROUP")|" \
        -e "s|^mod_version=.*|mod_version=$(esc_for_sed "$MOD_VERSION")|" \
        -e "s|^mod_license=.*|mod_license=$(esc_for_sed "$MOD_LICENSE")|" \
        -e "s|^mod_description=.*|mod_description=$(esc_for_sed "$MOD_DESC")|" \
        gradle.properties.example > gradle.properties
    ok "wrote gradle.properties (mod_id=${MOD_ID}, license=${MOD_LICENSE})"

    # Update the lang file's tab display name. Lang lives under the un-renamed
    # mod_id dir 'aitemplate' at this point; rename_mod.sh (step 3) handles the
    # directory rename later if mod_id changed.
    LANG_FILE="src/main/resources/assets/aitemplate/lang/en_us.json"
    cat > "$LANG_FILE" <<EOF
{
  "itemGroup.aitemplate.custom": "$(esc_for_json "$TAB_NAME")"
}
EOF
    ok "wrote ${LANG_FILE} (tab='${TAB_NAME}')"

    # Update ModCreativeTab.java's icon. The default ships with Items.BARRIER.
    TAB_JAVA="src/main/java/com/aicreator/aitemplate/ModCreativeTab.java"
    if grep -q 'Items\.BARRIER' "$TAB_JAVA"; then
        sed -i "s|Items\.BARRIER|Items.${TAB_ICON_ENUM}|" "$TAB_JAVA"
        ok "set creative-tab icon → Items.${TAB_ICON_ENUM} in ${TAB_JAVA##*/}"
    else
        # Already customized; leave alone.
        skip "${TAB_JAVA##*/} icon already changed from BARRIER — leaving alone (edit by hand if you want '${TAB_ICON_ENUM}')"
    fi

    # Heads-up if license differs from what's shipped in the repo's LICENSE file.
    if [[ "$MOD_LICENSE" != "MIT" ]]; then
        echo "  Note: repo ships with an MIT LICENSE file. You picked mod_license='${MOD_LICENSE}'."
        echo "        The in-game Mods list will show '${MOD_LICENSE}', but the LICENSE file at the"
        echo "        repo root is unchanged — edit / replace it yourself if you want the file to match."
    fi
fi

# ----------------------------------------------------------------------------
# 2. config.sh — local paths
# ----------------------------------------------------------------------------
log "[2/4] local paths → config.sh"
if [[ -f config.sh && $FORCE -eq 0 ]]; then
    skip "config.sh already exists (use --force to regenerate)"
else
    # ----- helper: is this MultiMC/Prism instance compatible? (MC 1.21.1 + NeoForge) -----
    is_compatible_instance() {
        local instance_root="$1"
        local pack="$instance_root/mmc-pack.json"
        [[ -f "$pack" ]] || return 1
        python3 - "$pack" <<'PYEOF' >/dev/null 2>&1
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    comps = data.get('components', [])
    mc_ok = any(c.get('uid') == 'net.minecraft' and c.get('version') == '1.21.1' for c in comps)
    nf_ok = any(c.get('uid') == 'net.neoforged' for c in comps)
    sys.exit(0 if (mc_ok and nf_ok) else 1)
except Exception:
    sys.exit(1)
PYEOF
    }

    # ----- discover instances and filter to compatible -----
    ALL_INSTANCES=()
    for guess in "$HOME"/.local/share/multimc/instances/*/ \
                 "$HOME"/.local/share/PrismLauncher/instances/*/ \
                 "$HOME"/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances/*/; do
        [[ -d "${guess}.minecraft/mods" ]] && ALL_INSTANCES+=("${guess%/}")
    done

    COMPAT_MODS=()
    for inst in "${ALL_INSTANCES[@]}"; do
        if is_compatible_instance "$inst"; then
            COMPAT_MODS+=("${inst}/.minecraft/mods")
        fi
    done

    # Reusable step-by-step for creating a 1.21.1 + NeoForge instance
    # (we print this any time the user lacks a usable instance).
    print_instance_create_steps() {
        echo "  → Step-by-step (5 minutes, one-time per host):"
        echo "      1. Open your launcher (Prism or MultiMC)"
        echo "      2. Add Instance → Custom → Minecraft  1.21.1"
        echo "      3. Add Loader → NeoForge → 21.1.230   (any 21.1.x works)"
        echo "      4. Name it anything, e.g. \"AI mobs creator\" → Create"
        echo "      5. Log in with your Microsoft / Mojang account when the launcher prompts"
        echo "      6. Re-run scripts/setup.sh — it will auto-detect the new instance"
    }

    if [[ ${#ALL_INSTANCES[@]} -eq 0 ]]; then
        echo "  No MultiMC or Prism Launcher instances detected on this host."
        echo "  This scaffold targets NeoForge 1.21.1."
        echo
        echo "  Install a launcher first (Prism recommended — active fork of MultiMC):"
        echo "    flatpak install -y flathub org.prismlauncher.PrismLauncher       # recommended"
        echo "    sudo apt install multimc                                          # older MultiMC"
        echo
        print_instance_create_steps
        echo
        MULTIMC_MODS_DIR=$(prompt "MULTIMC_MODS_DIR (enter manually for now)" \
            "$HOME/.local/share/multimc/instances/<INSTANCE>/.minecraft/mods")
    elif [[ ${#COMPAT_MODS[@]} -eq 0 ]]; then
        echo "  Found ${#ALL_INSTANCES[@]} instance(s), but none are MC 1.21.1 + NeoForge."
        echo "  This scaffold's mod won't load on Fabric, Forge, vanilla, or non-1.21.1 instances."
        echo
        print_instance_create_steps
        echo
        MULTIMC_MODS_DIR=$(prompt "MULTIMC_MODS_DIR (enter manually for now)" \
            "$HOME/.local/share/multimc/instances/<INSTANCE>/.minecraft/mods")
    else
        echo "  Detected ${#COMPAT_MODS[@]} compatible 1.21.1 + NeoForge instance(s):"
        for i in "${!COMPAT_MODS[@]}"; do
            # ${path}.minecraft/mods → instance name = basename of the path two dirs up
            inst_path="${COMPAT_MODS[$i]}"
            inst_name=$(basename "${inst_path%/.minecraft/mods}")
            # Shorten the launcher prefix for readability
            launcher_hint="MultiMC"
            [[ "$inst_path" == *"PrismLauncher"* ]] && launcher_hint="Prism"
            printf "    %2d) %s  (%s)\n" $((i+1)) "$inst_name" "$launcher_hint"
        done
        OTHER=$((${#COMPAT_MODS[@]}+1))
        printf "    %2d) Enter a different path manually\n" $OTHER
        read -r -p "  Selection [1-$OTHER]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#COMPAT_MODS[@]} )); then
            MULTIMC_MODS_DIR="${COMPAT_MODS[$((choice-1))]}"
        else
            MULTIMC_MODS_DIR=$(prompt "MULTIMC_MODS_DIR" "$HOME/.local/share/multimc/instances/<INSTANCE>/.minecraft/mods")
        fi
    fi

    PREVIEW_OUTPUT_DIR=$(prompt "PREVIEW_OUTPUT_DIR (where Blender preview JPGs land)" "$HOME/Desktop")

    cat > config.sh <<EOF
# Generated by scripts/setup.sh — edit freely.
export MULTIMC_MODS_DIR="${MULTIMC_MODS_DIR}"
export PREVIEW_OUTPUT_DIR="${PREVIEW_OUTPUT_DIR}"
EOF
    ok "wrote config.sh"

    # ----- ensure runtime deps (GeckoLib + corelib) live in the selected instance -----
    if [[ -d "$MULTIMC_MODS_DIR" ]]; then
        echo
        log "      verifying runtime mods in $MULTIMC_MODS_DIR"
        MC_VER=$(grep '^minecraft_version=' gradle.properties | cut -d= -f2)
        GECKO_VER=$(grep '^geckolib_version=' gradle.properties | cut -d= -f2)
        CORE_VER=$(grep '^corelib_version=' gradle.properties | cut -d= -f2)

        ensure_jar() {
            local pattern="$1" url="$2" name="$3"
            if compgen -G "${MULTIMC_MODS_DIR}/${pattern}" > /dev/null 2>&1; then
                local existing
                existing=$(ls -t "${MULTIMC_MODS_DIR}"/${pattern} 2>/dev/null | head -1)
                ok "${name} already present ($(basename "$existing"))"
            else
                local dest="${MULTIMC_MODS_DIR}/$(basename "$url")"
                note "downloading ${name} → $(basename "$dest")"
                if curl -fsSL -o "$dest" "$url"; then
                    ok "${name} installed ($(du -h "$dest" | cut -f1))"
                else
                    err "${name} download failed from $url"
                    err "    manually grab the jar from CurseForge / Modrinth and drop it in $MULTIMC_MODS_DIR"
                fi
            fi
        }

        ensure_jar "geckolib-neoforge-*.jar" \
            "https://dl.cloudsmith.io/public/geckolib3/geckolib/maven/software/bernie/geckolib/geckolib-neoforge-${MC_VER}/${GECKO_VER}/geckolib-neoforge-${MC_VER}-${GECKO_VER}.jar" \
            "GeckoLib ${GECKO_VER}"
        ensure_jar "corelib-*.jar" \
            "https://maven.maxhenkel.de/repository/public/de/maxhenkel/corelib/corelib/${CORE_VER}/corelib-${CORE_VER}.jar" \
            "corelib ${CORE_VER}"
    fi
fi

# ----------------------------------------------------------------------------
# 3. (optional) mod rename
# ----------------------------------------------------------------------------
log "[3/4] rename mod_id throughout the source tree (optional)"
# detect current mod_id in gradle.properties
CURRENT_MOD_ID=$(grep '^mod_id=' gradle.properties | cut -d= -f2)
if [[ "$CURRENT_MOD_ID" == "aitemplate" ]]; then
    skip "mod_id is still 'aitemplate' — nothing to rename. (You can run scripts/rename_mod.sh later if you change mod_id in gradle.properties.)"
else
    # The renames need to happen against the source files which still say "aitemplate"
    if grep -rq "aitemplate" src/ tools/ 2>/dev/null; then
        echo "  Detected mod_id=${CURRENT_MOD_ID} in gradle.properties but source still references 'aitemplate'."
        read -r -p "  Run scripts/rename_mod.sh to update source? [Y/n]: " ans
        if [[ "$ans" != "n" && "$ans" != "N" ]]; then
            CURRENT_GROUP=$(grep '^mod_group_id=' gradle.properties | cut -d= -f2)
            "$REPO_ROOT/scripts/rename_mod.sh" "$CURRENT_MOD_ID" "$CURRENT_GROUP"
            ok "source renamed to mod_id=${CURRENT_MOD_ID}, group=${CURRENT_GROUP}"
        else
            skip "user declined rename — source still references 'aitemplate'"
        fi
    else
        ok "source already uses '${CURRENT_MOD_ID}'"
    fi
fi

# ----------------------------------------------------------------------------
# 4. (optional) Blender MCP host setup
# ----------------------------------------------------------------------------
log "[4/4] headless Blender + BlenderMCP host setup (optional)"
echo "  If you plan to use Tier B (polygonal mob rendering), you need Blender + the"
echo "  patched BlenderMCP installed on this host. scripts/install_blender_mcp.sh handles it."
read -r -p "  Run the Blender MCP installer now? [y/N]: " ans
if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    "$REPO_ROOT/scripts/install_blender_mcp.sh"
else
    skip "deferred — run scripts/install_blender_mcp.sh later when ready"
fi

echo
echo "=========================================================="
echo "Setup complete. Next steps:"
echo "  source config.sh           # load MULTIMC_MODS_DIR + PREVIEW_OUTPUT_DIR"
echo "  ./gradlew build            # build the mod"
echo "  cp build/libs/*.jar \"\$MULTIMC_MODS_DIR\"   # deploy to your instance"
echo
echo "Read README.md for the full workflow."
echo "=========================================================="
