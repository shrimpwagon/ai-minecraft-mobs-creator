# Copy this to `config.sh` and edit the paths for your machine.
# scripts/setup.sh can do this for you interactively.
#
# Source this from your shell or from scripts/deploy.sh:
#   source ./config.sh

# Where to copy the built mod jar after `./gradlew build`.
# Typically: <your-multimc-instance>/.minecraft/mods
# Example: "$HOME/.local/share/multimc/instances/1.21.1 - Claude/.minecraft/mods"
export MULTIMC_MODS_DIR="$HOME/.local/share/multimc/instances/<INSTANCE-NAME>/.minecraft/mods"

# Where multi-angle Blender preview JPGs are written (used by tools/render_preview.py).
# Default ~/Desktop is convenient for at-a-glance review.
export PREVIEW_OUTPUT_DIR="$HOME/Desktop"
