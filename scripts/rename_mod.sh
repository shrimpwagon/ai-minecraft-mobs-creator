#!/usr/bin/env bash
# rename_mod.sh — rename the mod from `aitemplate` to a new id/group across the entire source tree.
#
# Touches:
#   - src/main/java/<old-group-dirs>/<old-id>/   →   src/main/java/<new-group-dirs>/<new-id>/
#   - Every .java file: `package`, `import`, and the MODID literal "aitemplate"
#   - src/main/resources/assets/aitemplate/       →   src/main/resources/assets/<new-id>/
#   - src/main/resources/data/aitemplate/        →   src/main/resources/data/<new-id>/
#   - Every "aitemplate:..." string in JSON / .mcmeta / .toml files
#   - tools/build-*-atlas.py and tools/entities/*.py asset path strings
#
# Usage:
#   scripts/rename_mod.sh <new_mod_id> <new_mod_group_id>
#   e.g.   scripts/rename_mod.sh cool_mobs com.alice
#
# Idempotent: if the source already uses the new id, it's a no-op.
# Reversible by running again with the old values.

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <new_mod_id> <new_mod_group_id>" >&2
    echo "  e.g. $0 cool_mobs com.alice" >&2
    exit 1
fi

NEW_ID="$1"
NEW_GROUP="$2"
OLD_ID="aitemplate"
OLD_GROUP="com.aicreator"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Validate new_id
if [[ ! "$NEW_ID" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "error: mod_id must be lowercase alphanumeric + underscores, starting with a letter" >&2
    exit 1
fi
if [[ ! "$NEW_GROUP" =~ ^[a-z][a-z0-9.]*$ ]]; then
    echo "error: mod_group_id must be lowercase reverse-DNS (e.g. com.you.modname)" >&2
    exit 1
fi

log() { printf "\033[1;36m[rename]\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m  ✓\033[0m %s\n" "$*"; }

OLD_GROUP_PATH="${OLD_GROUP//.//}"
NEW_GROUP_PATH="${NEW_GROUP//.//}"

# 1. Move the Java package dir
log "moving src/main/java/${OLD_GROUP_PATH}/${OLD_ID}/ → src/main/java/${NEW_GROUP_PATH}/${NEW_ID}/"
if [[ -d "src/main/java/${OLD_GROUP_PATH}/${OLD_ID}" ]]; then
    mkdir -p "src/main/java/${NEW_GROUP_PATH}"
    mv "src/main/java/${OLD_GROUP_PATH}/${OLD_ID}" "src/main/java/${NEW_GROUP_PATH}/${NEW_ID}"
    # try to clean up empty parent dirs from the old group path
    find "src/main/java/${OLD_GROUP_PATH%/*}" -depth -type d -empty -delete 2>/dev/null || true
    ok "moved Java package"
else
    ok "Java package already moved (or never at default path)"
fi

# 2. Patch every .java file (package, imports, MODID literal)
log "patching .java files"
find src/main/java -type f -name '*.java' -print0 | xargs -0 sed -i \
    -e "s|${OLD_GROUP}\\.${OLD_ID}|${NEW_GROUP}.${NEW_ID}|g" \
    -e "s|\"${OLD_ID}\"|\"${NEW_ID}\"|g"
ok "patched .java files"

# 3. Move asset + data resource dirs
for kind in assets data; do
    if [[ -d "src/main/resources/${kind}/${OLD_ID}" ]]; then
        log "moving src/main/resources/${kind}/${OLD_ID}/ → src/main/resources/${kind}/${NEW_ID}/"
        mv "src/main/resources/${kind}/${OLD_ID}" "src/main/resources/${kind}/${NEW_ID}"
        ok "moved ${kind}/${OLD_ID}"
    fi
done

# 4. Patch every JSON, .mcmeta, .toml file under src/ and tools/ — the "aitemplate:" prefix
log "patching JSON / mcmeta / toml / py files for \"${OLD_ID}:\" strings"
find src/main/resources tools -type f \( -name '*.json' -o -name '*.mcmeta' -o -name '*.toml' -o -name '*.py' \) -print0 \
    | xargs -0 sed -i "s|${OLD_ID}|${NEW_ID}|g"
ok "patched resource files"

# 5. Verify nothing references the old id anymore
log "verifying"
LEFTOVERS=$(grep -rln "${OLD_ID}" src/ tools/ 2>/dev/null || true)
if [[ -n "$LEFTOVERS" ]]; then
    echo
    echo "  WARNING: these files still reference '${OLD_ID}' — review:" >&2
    echo "$LEFTOVERS" | sed 's/^/    /' >&2
    echo
fi
LEFTOVERS_GROUP=$(grep -rln "${OLD_GROUP}" src/ tools/ 2>/dev/null || true)
if [[ -n "$LEFTOVERS_GROUP" ]]; then
    echo "  WARNING: these files still reference group '${OLD_GROUP}' — review:" >&2
    echo "$LEFTOVERS_GROUP" | sed 's/^/    /' >&2
fi

echo
echo "Rename complete:"
echo "  mod_id:       ${OLD_ID}     → ${NEW_ID}"
echo "  mod_group_id: ${OLD_GROUP}  → ${NEW_GROUP}"
echo
echo "Try: ./gradlew build"
