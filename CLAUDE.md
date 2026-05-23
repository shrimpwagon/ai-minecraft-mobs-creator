# CLAUDE.md — agent instructions for this repo

**You are reading this because you're working in `ai-minecraft-mobs-creator`. Read this file fully, then read [DEVELOPMENT.md](DEVELOPMENT.md) before doing anything else. Together these two docs are enough — you should not need to "poke around" the codebase to figure out the workflow.**

## Important framing: helpers stay narrow, you stay in charge of geometry

The repo gives you exactly two Python helpers, both narrow:

- **`tools/codex_image.py`** — wrapper around the `codex` CLI's `image_gen` tool. Handles all four codex landmines (stdin DEVNULL, `--ephemeral`, `--json` + `thread_id` parsing, downscale). Use it whenever you need an AI-generated texture.
- **`tools/corelib_obj_export.py`** — a Blender-Python module that the installer symlinks into `~/.config/blender/<version>/scripts/modules/`. From inside any Blender Python call you make via the `mcp__blender__*` tools, you can `from corelib_obj_export import export_corelib_obj` and write a corelib-compatible OBJ in one line. It handles face triplets, UV V-flip, triangulation, and runs a CCW-outward winding sanity check.

That's everything. **There is no mesh-building helper, no per-mob driver script, no preview-rendering wrapper, no PARTS-list convention.** For Tier B (polygonal) mobs, **you drive Blender directly via the `mcp__blender__execute_blender_code` tool**: bmesh whatever geometry you want — rotated boxes, scaled cylinders, joined primitives, edited verts, anything Blender can express — then call `export_corelib_obj(path='...')`. You also render previews in the same `execute_blender_code` call (or a follow-up one) using `bpy.ops.render.render(write_still=True)`.

The **technical constraints** that DO bind you:

- For corelib (Tier B) OBJs: the four gotchas (face triplet `v/vt/vn`, V-flip, triangulation, CCW outward). `corelib_obj_export.export_corelib_obj()` handles them all — use it. If you hand-write an OBJ for some reason, address all four yourself; see DEVELOPMENT.md "The four critical OBJ gotchas."
- The rendering libraries are fixed by `build.gradle` — GeckoLib (Tier A cubes with skeletal animation), corelib (Tier B static / whole-model-animated polygonal). Picking anything else means adding a dependency.
- Mod registration goes through `ModBlocks` / `ModEntities` / `ModItems` / `ModCreativeTab` / `MyFirstMod.java` and the lang file at `assets/<mod_id>/lang/en_us.json`. Structural, not optional.

Everything else — mesh shape, part count, UV layout, texture style, animation, render camera setup — is your judgment call. You have full Blender expressiveness.

## What this repo is

A tooling scaffold for AI-assisted creation of custom Minecraft mobs, blocks, items, weapons, and armor on NeoForge 1.21.1. The repo ships with no example assets — every mob, block, and item is built fresh from the user's prompt. The user asks for something ("build a hovering crystal pet that gives Speed II nearby," "add a flaming sword," "create a teleporting block"), and you:

1. Ask the clarifying questions (visual style + — for Tier B mobs only — detail level + texture method; see below).
2. Generate the texture (default: `codex image_gen` via `tools/codex_image.py`; fall back to hand-coded Pillow only when the user asks for pixel-by-pixel control).
3. For mobs:
   - **Tier A (GeckoLib):** write `.geo.json` + `.animation.json` + Java entity/model/renderer/registration.
   - **Tier B (corelib):** drive Blender via `mcp__blender__execute_blender_code` — build the mesh, assign UVs, export OBJ via `corelib_obj_export`, render preview JPGs, **pause for user creative review**, then write Java entity + renderer + registration.
4. For blocks / items / weapons / armor: write the Java + JSON directly (no helpers).
5. Register in the appropriate `Mod*.java` + add the lang line + creative-tab line.
6. `./gradlew build && cp build/libs/*.jar "$MULTIMC_MODS_DIR"` → user tests in-game.

For Tier B mobs specifically, **step 3 has a mandatory pause** — see "Preview + pause for user review" below. The user must confirm the model looks right before you commit to writing Java.

DEVELOPMENT.md has the full technical reference; this file has only the *behaviors* the user expects from you.

## REQUIRED: clarify before building any new mob, block, item, weapon, or armor

Whenever the user prompts for a new asset of any kind, **ALWAYS** confirm the clarifying-question answers before writing any code or generating any textures. The default is to ask the full questionnaire via **AskUserQuestion**, but if `.claude/mob_preferences.md` exists from a prior session you can short-circuit that with a single confirmation — see "Saved preferences across sessions" below. Phrase any questions you do ask in simple everyday language — no jargon, no "Tier A/B", no library names in the question itself. The user explicitly asked for "like how an 8 year old might understand."

### Saved preferences across sessions

Mob builds tend to be repeat work — once a user has answered Q1/Q1b/Q1c/Q2 for one mob, they usually want the same answers for the next few. Save and re-use them via `.claude/mob_preferences.md` (gitignored, per-project, per-user):

1. **Before asking any clarifying questions for a new mob build, Read `.claude/mob_preferences.md`.**
2. **If it exists**, ask ONE question via `AskUserQuestion`: *"Use last preferences for this `<thing>`? [`<one-line summary of saved answers>`]"* — two options:
   - "Yes, same as last time" → skip the full questionnaire, use the saved answers verbatim, proceed.
   - "Change something" → ask the full Q1/Q1b/Q1c/Q2 questionnaire as normal.
3. **If it does not exist** (first-ever mob, or user deleted it), ask the full questionnaire.
4. **After every successful build**, overwrite the file with the answers that were *actually* used (not what the user first picked if you talked them out of it — record the final decision). Format:
   ```markdown
   # Mob build preferences (auto-saved)

   The agent reads this at the start of every new mob build and asks "same as last time, or change something?" instead of re-asking the full questionnaire. Edit by hand to change defaults. Delete to force a fresh questionnaire.

   ## Most recent build — YYYY-MM-DD

   **Mob:** <name>
   **Visual style (Q1):** <plain-words answer>
   **Detail level (Q1b):** <answer, or "N/A — not Tier B">
   **Style bias (Q1c):** <answer, or "N/A — not Tier B">
   **Sizing (Q1d):** <tiny / small / standard humanoid / large / huge / massive — and the final dimensions you actually built to, in blocks>
   **Texture method (Q2):** <answer>
     - <optional note if the agent switched method for technical reasons, e.g. "user picked AI but agent switched to Pillow because of Tier A UV-cell bleed">
   ```

The file is a single-snapshot, not a history log — each new build overwrites. If the user wants per-mob history they can grep `git log` for the mob name in their commits.

### Don't infer answers from existing mobs in the repo

The scaffold ships with **no example mobs or blocks** in `src/` — that's deliberate, so you can't subconsciously inherit a prior asset's tier choice, proportions, or palette. After one or more mobs have been built in a session, the temptation will return: *"the existing mob is Tier A, so this new one should be Tier A too,"* or *"the last mob used spheres, so I'll do spheres here."* **No.** Existing files in the repo (whether shipped or built by a prior session) are reference material for **Java/JSON skeleton shape only** — never use them as a visual / geometric / personality / tier-choice / detail-level reference. Each new mob is built fresh from the user's answers (or saved preferences in `.claude/mob_preferences.md`). If you catch yourself thinking *"the existing mobs are mostly X, so X is a safe default,"* stop — that's exactly the bias the user wants you to drop. Drive every visual decision from user input, not from what's already in the repo.

### For a new mob

**Q1 — what should it look like?**
- "A regular Minecraft mob that walks/moves its arms and legs — made of big blocks" → Tier A simple (GeckoLib few large cuboids, fully animatable)
- "Like a Minecraft mob but with more detail, still made of blocks, walks and moves" → Tier A detailed (GeckoLib many small cuboids)
- "Unusual shape — not just plain blocks, can be tilted / angled / curved / organic — moves as one piece (no separate arm/leg animation)" → Tier B (corelib polygonal, built freely in Blender)

**Q1b — Tier B only: how detailed should it be?**

If they picked Tier B in Q1, you MUST also ask this — otherwise you'll default to "simple cube character" and the user will come back disappointed asking for more detail. Tier B's whole point is unlocking the higher end of visual complexity; don't waste the tier on a plain build.

- "Simple — about a dozen parts, flat colors per part, just enough to read as the character" → ~10–20 primitives, **single-cell UVs are fine here** (one atlas pixel per part = one solid color per part). Use this for cartoony / icon-style mobs.
- "Detailed — many small parts with recognizable features (separate fingers, 3D nose, brow ridge, ears, accessories like belts/horns)" → ~30–60 primitives. **Every visible part gets a textured region** — not a flat single pixel. Body, arms, legs, hands, head, ears, nose ALL get meaningful texture content. Modest UV work but no part is left flat-colored.
- "Maximum — many parts AND a painted skin texture with shading, muscle definition, scars/dirt/wood-grain baked in across the whole body" → ~30–60+ primitives + per-part UV unwrap + an AI-generated detailed texture covering every visible part. Biggest visual leap. Iteration is ~3× slower because tweaks may require re-painting the texture, not just moving parts.

Keep wording in simple language — no "UV unwrap" / "bevel" / "subdivision" jargon in the question itself; bury those in the option *description* if you must mention them.

**Q1c — Tier B only: how "Minecraft-y" should the shape look?**

If they picked Tier B in Q1, you MUST also ask this — alongside Q1b in the same `AskUserQuestion` call. **This is the #1 recurring Tier B failure**: the agent unconsciously defaults to axis-aligned cubes with mild rotations even when the user wanted something organic. The user almost always picks Tier B *precisely to escape the Minecraft cube look* — don't drag them back into it by reflex. The answer here changes which Blender primitives you reach for. It must be a real question; don't assume.

- "Keep it Minecraft-style — blocky parts, just tilted / angled / asymmetric (no curves)" → mostly `primitive_cube_add` with `rotation_euler`. Palette-color textures. Same aesthetic as Tier A but with rotation freedom.
- "In-between — Minecraft-style pixel-art textures, but with rounded/organic body shapes (sphere head, tapered limbs)" → `primitive_uv_sphere_add` for heads, `primitive_cylinder_add` for limbs, bmesh-tapered cube torsos. Keep low-res pixel-art textures.
- "Modern video-game character — sphere head, curved/tapered limbs, real proportions, smooth surfaces, painted-looking skin (PS2/PS3-era character — NOT blocky at all)" → spheres + cylinders + bmesh edits + optional Subsurf modifier. Full per-part UV unwrap with detailed textures. The biggest visual departure from Minecraft.

**Wording for the user (no jargon, 8-year-old language):**
- "Made of square Minecraft-style blocks, just allowed to be tilted or angled"
- "Half-and-half — pixely square-looking skin, but rounder body shapes (like a round head and arms)"
- "Like a normal video-game character — round head, smooth arms and legs, painted-on skin (not made of squares at all)"

**When to skip Q1c:** If the prompt names a recognizable polygonal-game character ("Link," "Mario," "Goku," "Lara Croft"), default to "modern video-game character" and state it in one line before asking the remaining questions. If a reference image is clearly pixel-art / Minecraft mod artwork → default to "Minecraft-style." If the reference is a render from a game like Zelda/Mario/Final Fantasy → default to "modern video-game character." Otherwise ask.

#### Don't default to axis-aligned cubes for Tier B

Even after the user answers Q1c, the agent has strong gravitational pull back toward `primitive_cube_add` everywhere. **Resist it.** Concretely, for "in-between" or "modern video-game character":

- **Heads** should almost never be a single cube. Use `primitive_uv_sphere_add(segments=12, ring_count=8)`, scale to taste, optionally bmesh-edit verts for chin / brow ridge / cheekbones.
- **Limbs** → `primitive_cylinder_add(vertices=8)`; for the modern tier, use bmesh to taper (scale the top vert loop smaller than the bottom). NOT stacked cubes.
- **Joints** (shoulders / hips / knees) → small spheres at the limb radius. Eliminates the visible cube-edge seam where parts meet.
- **Torsos** → start from a cube, enter bmesh, scale top/bottom face loops to taper. A pure axis-aligned cube torso always reads as Minecraft.
- **Don't open any existing `.obj` / `.geo.json` / entity Java for style cues** — even if a prior session built one. Use the copy-paste templates in DEVELOPMENT.md for structural skeleton, and build the mesh fresh from the user's Q1c answer + visual description.
- **Smell check before exporting:** if your `execute_blender_code` call has 15+ consecutive `primitive_cube_add` lines and Q1c was NOT "Minecraft-style," stop and rewrite the affected parts with spheres/cylinders/bmesh. That pattern is the bias surfacing — catch it before showing the user.

#### When iterating: regenerate the WHOLE atlas in one call

If the user reviews the preview and asks for texture changes ("the body needs more detail," "make the hands match," "darker overall"), do NOT make a fresh codex call for just the missing region and patch it onto the existing PNG. Codex has no memory of what the previous atlas looked like — palette, lighting, line weight, and pixel-art conventions will all drift between calls and the result looks visibly mismatched (the recurring "face is one style, body is another" failure).

Instead: **regenerate the entire atlas in one codex call** with the full updated prompt covering every part (face, body, hands, etc.). Use `generate_sheet` if the atlas is multi-region. The whole texture lands in one composition with consistent palette and style. Yes, this re-rolls parts that looked fine — that's the price of consistency, and codex is fast enough that one extra call beats three iterations chasing a mismatch.

The only exception: if the user is happy with most of the texture and only wants a small fix you can clearly do with Pillow (recolor a region, sharpen edges), do it in Pillow on the existing PNG. Don't go back to codex for a partial.

#### When to ask about stylistic appearance

Most prompts already telegraph aesthetic: "medieval knight" → fantasy, "cyberpunk drone" → futuristic, "Victorian ghost" → period. **Do NOT ask a stylistic question when the prompt already carries the signal** — it's wasted friction.

Ask only when the prompt is genuinely style-ambiguous (a plain noun like "lizard" or "robot" — could be realistic, cartoony, fantasy, mechanical, painterly). If you do ask, options like *whimsical / realistic / fantasy / futuristic / medieval / painterly* in plain language. Skip the question entirely if the user supplied a reference image — the image carries style, palette, proportions, and embellishment vibe all in one input.

#### Texture-coverage rule for Detailed and Maximum

A recurring failure mode: the agent picks "Maximum" in Q1b, then textures only the face on the first pass — leaving body / arms / hands / ears as flat solid colors. The user then has to push back ("more texture") repeatedly across 2-3 rebuild rounds. Don't be that agent. **If Q1b = Detailed or Maximum:**

- Every visible Blender object must have UVs that span a **distinct, content-bearing region** of the texture atlas — not all collapsed to a single pixel.
- A quick check before export: `len(set((round(uv[0],3), round(uv[1],3)) for face in bm.faces for loop in face.loops for uv in [loop[uv_layer].uv]))` should equal or exceed the visible part count × 4 (each part needs at least 4 distinct UV corners). If every part collapses to ≤1 UV, you've fallen into the flat-color trap.
- In your texture prompt to `codex_image`, explicitly list **every body part** that needs texture content. *"Texture atlas for a humanoid mob with face, ears, nose, neck, chest, belly, shoulders, biceps, forearms, hands, fingers, hips, thighs, calves, feet, loincloth"* — listing each part forces codex to fill the atlas instead of putting everything in one face zone.
- On the first preview render, scan each angle for any part that looks like a flat block of color (not the rest of the mesh's textured surface). If you see one, fix the UVs / atlas before showing the user.

**Q1d — physical size (all mob tiers, not just Tier B):**

You MUST ask this for every mob build. **Without an explicit size answer, the agent produces mobs that are either oddly tiny or unintentionally huge** — especially when importing existing OBJs (Sketchfab / Pixelmon-style imports often arrive at 100×–1000× the intended Minecraft scale). Pick the tier up front, build to it, and verify with a bounding-box check before showing the user.

Discrete tiers (target height × max horizontal extent, in blocks):

- "Tiny — smaller than a rabbit" → ~0.4–0.7 tall × ~0.4 wide → fairy, sprite, mouse, insect
- "Small — chicken / pig size" → ~0.7–1.0 tall × ~0.6 wide → cat-sized creature
- "Standard humanoid — Steve-sized" → ~1.95 tall × ~0.6 wide → most humanoid mobs; default
- "Large — cow / horse" → ~1.4 tall × ~1.2 wide → bulky beast, big quadruped
- "Huge — Iron Golem / Ravager" → ~2.7 tall × ~1.4 wide → giant, ogre, heavy boss-class
- "Massive — multi-block" → up to ~8 in any dimension → dragon, troll, Pixelmon-scale large pokémon, kaiju

**Wording for the user (plain language, no jargon):**
- "Tiny (smaller than a rabbit)"
- "Small (chicken / pig sized)"
- "Normal player-sized humanoid (like Steve)"
- "Large (cow / horse sized)"
- "Huge (Iron Golem / Ravager sized)"
- "Massive (multi-block — dragon, troll, giant)"

**Hard upper bound: ~10 blocks in any single dimension.** Past that, Minecraft's entity render distance starts clipping the model in and out as the player walks, the hitbox becomes unworkable for combat, and dense scenes drop frames. A troll *can* be 8 blocks tall and that's fine; if the user's prompt or an imported model would push past 10, clamp to 10 and tell them in one line (*"scaled the import down from 14→10 blocks/dim to stay inside Minecraft's render limits — say so if you want to override"*).

**Default if you must skip the question:** "Standard humanoid" — only valid when the prompt clearly implies a player-shape (knight, princess, samurai, etc.). For anything ambiguous, ask.

#### Adhering to the chosen size

For **Tier A** (`.geo.json` cuboid mobs): scale the cuboid coordinates so the bounding box matches the target. Geo coords are in 1/16-block units → "Standard humanoid" parts span roughly `y ∈ [0, 31]` (≈1.95 blocks); "Massive" might span `y ∈ [0, 96]` (6 blocks). Update the `sized(W, H)` entry in `ModEntities` to match.

For **Tier B** (Blender / corelib polygonal mobs): after building the mesh, compute and print the world-space bounding box, then scale if off-target:

```python
import mathutils
bbox_min = mathutils.Vector(( 1e9,  1e9,  1e9))
bbox_max = mathutils.Vector((-1e9, -1e9, -1e9))
for o in parts:
    for c in o.bound_box:
        wc = o.matrix_world @ mathutils.Vector(c)
        bbox_min = mathutils.Vector((min(bbox_min[i], wc[i]) for i in range(3)))
        bbox_max = mathutils.Vector((max(bbox_max[i], wc[i]) for i in range(3)))
extent = bbox_max - bbox_min
# Blender scene is Z-up → Minecraft height = extent.z, footprint = max(extent.x, extent.y).
height = extent.z
width  = max(extent.x, extent.y)
print(f"MESH EXTENT: height={height:.2f}b  width={width:.2f}b  (target tier: <Q1d>)")
# If off-target, uniformly scale every object and re-export:
#   target_height = 1.95   # from Q1d tier
#   factor = target_height / height
#   for o in parts:
#       o.scale = (o.scale[0]*factor, o.scale[1]*factor, o.scale[2]*factor)
#       bpy.context.view_layer.objects.active = o
#       bpy.ops.object.transform_apply(scale=True)
```

For **imported OBJs** (Sketchfab, Pixelmon, hand-imported models): assume scale is wrong. Compute the bbox first, decide a scale factor to hit the user's Q1d tier, then apply uniformly. Modelers typically work in centimeters or meters — never in Minecraft blocks — so a "human" import might land at 170 units tall (cm) when you wanted 1.95 blocks; scale by 0.0115 in that case.

**Set `sized()` to match the FINAL mesh** (the visual mesh, not the original input). `ModEntities` `sized(width, height)` defines the hitbox; pick width = max(extent.x, extent.y) rounded up, height = extent.z rounded up. If you change the scale, change `sized()` too.

**Q2 — how should I make the colors/picture for it?**
- "Let the AI image generator make it" → codex `image_gen` via `tools/codex_image.py` (default — and the only sensible choice if they picked "Maximum" in Q1b)
- "I'll paint it pixel-by-pixel myself with Python" → Pillow (best for the "Simple" Q1b — flat palette swatches)

**Skip Q2 entirely if Q1 = Tier A.** Tier A cube skins use a strict 64×64 vanilla-Steve UV layout, and codex `image_gen` doesn't respect those per-cube cell boundaries reliably — content bleeds across cells and the in-game skin looks scrambled. This is documented in your global `feedback_minecraft_skins.md` memory. Instead of asking, **state the default in one line and proceed**:

> *"For Tier A cube mobs I'll paint the skin with Pillow — codex doesn't respect the 64×64 UV cells reliably, so hand-pixel pixels into the cells is the working path. Say so if you'd rather try AI textures anyway."*

That gives the user override room without making them litigate a question where the answer is already known. Only ask the full Q2 when the user explicitly resists ("can you try AI?") or when it's a Tier B mob or a non-mob asset.

### For a new block, item, weapon, or armor

**Q1 — what kind of thing is it?**
- Block: solid cube same all sides / cube with different sides (like a furnace) / non-cube shape (slab, stairs, fence)
- Item: plain (food, material, decorative) / tool (pickaxe, axe, shovel, hoe) / weapon (sword, bow, custom ranged) / armor piece (helmet, chestplate, leggings, boots)

**Q2 — how should I make the picture for it?**
- "Let the AI image generator make it" → codex `image_gen` via `tools/codex_image.py` (default)
- "I'll paint it pixel-by-pixel myself with Python" → Pillow

**When to skip the questions:** if the user already specified both visual style AND texture method in the same prompt (e.g. "make me a tilted ogre with AI-generated texture," "a flaming sword with AI texture"), don't ask.

### Q3 — drops + effects (universal — applies to mob / block / item / weapon / armor)

After Q1/Q2, ask what the asset should **drop** and what **effects / behaviors** it should have — unless the user's prompt already spelled both out. **Always offer "you pick something sensible" as an explicit option** so the user can be lazy when they don't care about the specifics. Most users would rather get a plausible default than litigate every loot weight.

The question shape changes per asset type:

- **Mob:** drops on death? any drops while alive (per-tick / per-hit)? on-hit effects applied to the target (poison, wither, fire, slowness, levitation)? death effects (particle burst, sound, item rain, brief area-of-effect)? passive / neutral / hostile / helps-the-player?
- **Block:** drops on break (self / nothing / random items)? on-step effects (launch, slow, damage, heal, teleport, ignite)? on-right-click effects? light level? redstone signal? particles when adjacent to a player? does it random-tick?
- **Item:** effects on use (heal, apply potion effect, summon entity, teleport)? stack size? has a glint? takes durability?
- **Weapon:** damage / attack-speed / durability / tier? special on-hit effects (Fire Aspect, knockback, lifesteal, lightning, summon, sweep)?
- **Armor:** defense values per slot / toughness / durability / material? special wear effects (perpetual potion while worn, set bonus, immunity to specific damage types)?

**Question framing** (one `AskUserQuestion` call, two or three options):
- *"I want to specify"* → ask follow-ups, populate fields from user input
- *"You pick something sensible for a `<thing>`"* (offer as the recommended default) → choose drops/effects that match the asset's flavor, **then state your picks in plain language in the next message before writing Java** so the user can override cheaply
- *"Nothing — plain `<thing>`, no drops, no effects"* → minimal asset

**Match picks to flavor** when the user picks "you pick":
- *fire-themed mob* → drops blaze powder + maybe coal; sets attack target on fire 3s; small particle puff on death
- *frost-themed block* → drops 1–2 ice; slows entities standing on it; emits frost particles near players; light level 4
- *glowing crystal item* → eating grants Night Vision 60s + Glowing 60s; small stack (16); has glint
- *legendary sword* → high damage, Fire Aspect II, low knockback, durability ~2× iron
- *necromancer armor set* → standard iron defense; full-set bonus: Regeneration I while wearing all 4

**Skip Q3** when the prompt already supplied both drops AND effects. *"A flaming sword that sets enemies on fire on hit"* → both specified (sword item, sets fire on hit). Skip. *"Make a goblin"* → neither specified. Ask.

**Batch with Q1/Q2 in one `AskUserQuestion` call** when possible (max 4 questions per call). For mobs typically: Q1d sizing + Q2 texture + Q3 drops/effects = 3. For blocks/items: Q1 kind + Q2 texture + Q3 drops/effects = 3.

### Options must be deliverable in roughly tweak-sized work

When using `AskUserQuestion` mid-task (e.g. "the model looks rigid — how should I rebuild it?"), each option should be implementable in roughly the scope the user expects from a "tweak." If an option requires a library swap, a Minecraft version bump, or an upstream fork, **label that cost explicitly in the option's description or don't offer it as a peer option**.

For Tier B mobs, in-style fixes the user usually wants:
- Rotated / tilted parts (now trivially expressible — use `obj.rotation_euler`)
- Asymmetric placement / pose (one arm longer, leaning torso, hunched back)
- Mix of cube + sphere + cylinder primitives where the shape calls for it
- A walk-bob / sway animation in the renderer

Genuine multi-day pivots (label clearly or refuse):
- Switching mesh format (glTF, FBX, USD) — corelib loads OBJ only; would need to fork corelib or jump MC version to use BlazeRod.
- Per-bone skeletal animation on a Tier B mob — corelib does whole-model transforms only; you'd need GeckoLib (Tier A) for that, which means a different geometry pipeline.
- Bumping the Minecraft version.

## First-time setup is user-driven, not agent-driven

Two scripts in this repo are **interactive** (prompt for input + need sudo) and you, the agent, must NEVER run them via the Bash tool — they'll hang waiting for stdin you can't provide:

- `scripts/setup.sh` — prompts for mod metadata + local paths
- `scripts/install_blender_mcp.sh` — sudo, prompts to confirm Blender extract

When the user clones this repo fresh and runs `claude`, they may not have run setup yet. Detect this early:

1. **Is `gradle.properties` missing?** Then setup hasn't been run. **Stop** and ask the user to run it via the bang-prefix command (which Claude Code runs in their interactive shell, where prompts work):
   > Please type this in your prompt: `!scripts/setup.sh`

2. **Is `config.sh` missing?** Same situation — point them at `!scripts/setup.sh`.

3. **Did the user ask for a Tier B (polygonal) mob, but the Blender MCP socket isn't reachable?** Try the cheap fix first — Blender just isn't running:
   - Run in the background: `nohup scripts/blender_mcp_start_headless.sh > /tmp/blender-mcp.log 2>&1 &` (this one is *non-interactive*, safe to Bash-tool it). Wait ~4 seconds, then test with `mcp__blender__get_scene_info`.
   - If THAT fails with `Connection refused` or "blender: command not found", Blender itself isn't installed. Tell the user:
     > Please type this in your prompt: `!scripts/install_blender_mcp.sh`

The bang-prefix runs the command in the user's terminal session so prompts work and sudo can read the password. After they finish, they'll come back and you can continue.

The launcher script (`scripts/blender_mcp_start_headless.sh`) is the only one of the three that's fully non-interactive — it's safe to start from the Bash tool with `run_in_background: true`.

## When the user wants a new block

The repo ships example blocks (in `src/main/java/.../block/`, registered in `ModBlocks.java`). They demonstrate the standard pattern: a Java behavior class + 5 asset/data JSON files + a 16×16 texture + registration in `ModBlocks` / `ModCreativeTab` / `en_us.json`.

**There's no helper script for blocks — write Java + JSON directly.** The JSON shapes are 4-5 lines each, well-known, and Minecraft is forgiving about block JSON (a malformed block doesn't crash, it just doesn't render). Use the existing blocks as templates:

- **Simple solid cube** (most blocks): blockstate + cube_all model + item model + drops-self loot.
- **Translucent**: same as above but the block model adds `"render_type": "minecraft:translucent"`.
- **Multi-face cube** (furnace-style, different top/bottom/sides): use `"parent": "minecraft:block/cube"` and supply textures per face. None of the examples have this yet — vanilla `minecraft:block/furnace` is a reference.
- **Slab / stairs / fence / door / non-cube**: use the vanilla parent models (`minecraft:block/slab`, `minecraft:block/stairs`, etc.) and the matching Java class (`SlabBlock`, `StairBlock`). Multi-state blockstates require the full `"variants": {"facing=north": ..., ...}` form.
- **Block entity** (chests, furnaces, custom GUIs): more involved Java (`EntityBlock` + a `BlockEntityType` registered separately). Asset side is unchanged.

**Per-block file organization:** Java behavior class goes in `src/main/java/<group>/<mod_id>/block/<Name>Block.java`. All blocks live in that one directory. Asset files go where the existing blocks' do — `assets/<mod_id>/blockstates/<name>.json`, `assets/<mod_id>/models/block/<name>.json`, `assets/<mod_id>/models/item/<name>.json`, `assets/<mod_id>/textures/block/<name>.png`, and `data/<mod_id>/loot_table/blocks/<name>.json`.

**Registration:** add a `DeferredBlock<...>` entry to `ModBlocks.java` using its `register()` helper, add a lang entry to `en_us.json`, add a `output.accept(ModBlocks.X.get())` line to `ModCreativeTab.java`'s `displayItems()`.

**Animation opportunity:** see "Animated block + item textures (.mcmeta)" below. Crystals, ores, glowing/luminous blocks, fluid-themed blocks, portals — all read much better with a 4-frame pulse. Proactively offer.

## When the user wants a new item, weapon, or armor

The repo has existing items in `ModItems.java` (spawn eggs, food, drop materials). The pattern is even simpler than blocks. No helper script for items either.

**Common item shapes:**

- **Plain item** (decorative, materials, simple drops): just an `Item` with `Item.Properties()` configured. No Java class needed — declare directly in `ModItems.java`.
- **Food**: `Item.Properties().food(FoodProperties.Builder().nutrition(N).saturationModifier(F).build())`. Add `.effect(...)` for status effects on eat.
- **Sword**: `SwordItem` subclass (or just `new SwordItem(tier, attackDamageBonus, attackSpeed, props)`). Needs a `Tier` (use vanilla `Tiers.IRON` etc., or create a custom `Tier` instance for unique stats). For special effects on hit, override `hurtEnemy()` in a subclass.
- **Pickaxe / Axe / Shovel / Hoe**: `PickaxeItem`, `AxeItem`, `ShovelItem`, `HoeItem`. Same `Tier` requirement.
- **Bow / projectile weapon**: `BowItem` subclass; on release, spawn a projectile entity (vanilla `Arrow` or a custom `EntityType`).
- **Armor piece**: `ArmorItem` subclass with a custom `ArmorMaterial` (defines durability multipliers, defense values per slot, enchantability, equip sound, repair item).

**Per-item file organization:** simple items can live entirely in `ModItems.java` (no separate class). Items that need a Java subclass go in `src/main/java/<group>/<mod_id>/item/<Name>Item.java` (create the `item/` directory if it doesn't exist yet). Texture: `assets/<mod_id>/textures/item/<name>.png` (16×16). Model JSON: `assets/<mod_id>/models/item/<name>.json` — usually `{"parent": "minecraft:item/generated", "textures": {"layer0": "<mod>:item/<name>"}}`. For tools/swords use `"parent": "minecraft:item/handheld"`.

**Registration:** add a `DeferredItem<...>` to `ModItems.java`, lang entry, creative-tab entry. Same shape as blocks.

**Animation opportunity:** see "Animated block + item textures (.mcmeta)" below. Many item types read much better with subtle animation — proactively offer it for the categories listed there.

## Animated block + item textures (.mcmeta)

Minecraft natively animates block and item textures via `.mcmeta` files alongside the PNG. **The user often doesn't think to ask for animation; the agent should proactively offer it when the asset clearly benefits.** A subtle 2–4 frame pulse on a glowing crystal block costs an extra ~5 seconds of texture-generation time and dramatically lifts the asset's perceived quality.

### When to proactively suggest animation

Offer animation as a quick yes/no for these asset categories — phrase it briefly, don't litigate:

- **Crystals / gems / ore variants** — slow pulse, sparkle highlight, or hue shift
- **Glowing / luminous blocks or items** — heartbeat brightness, flicker
- **Fluid-like or fluid-themed blocks** — bubbling, flowing, slosh
- **Magical / arcane items** (potions, scrolls, spell tomes, runes) — spinning glyph, energy spiral, surface swirl
- **Fire / lava / smoke / ember items** — flame flicker, ember rise
- **Portals / gates / nether-like blocks** — swirl, ripple, vortex
- **Glowing weapons / armor** (flaming sword, frost axe, soul-bound helm) — animated glow overlay
- **Frozen / icy items** — gentle frost crystal twinkle

Skip the offer for asset types where animation usually isn't worth it: static building blocks (stone, planks, dirt variants), tools without effects (plain pickaxe, plain shovel), mundane food (bread, apple), plain undecorated armor, basic decorative blocks. The user can still request animation for any of these — just don't volunteer.

### One-question prompt

When suggesting (or when the user asked for animation), use a single `AskUserQuestion` with the framerate options baked in:

- "No — single static texture"
- "Yes — slow subtle (2–3 frames, ~1 second loop)" → soft breathe / blink
- "Yes — medium pulse (4–6 frames, ~0.5 second loop)" → standard pulse / sparkle
- "Yes — fast flicker (8 frames, ~0.4 second loop)" → flame, energy, swirl

Translate the answer to `frametime` (in 1/20-second ticks): slow ≈ 10–20, medium ≈ 4–6, fast ≈ 2–3.

### File format

**The PNG is a vertical strip of square frames stacked top-to-bottom.** For a base 16×16 with 4 frames, the file is **16×64** (16 wide, 64 tall): frame 0 at y=0..15, frame 1 at y=16..31, frame 2 at y=32..47, frame 3 at y=48..63.

Next to the PNG, a sibling file with the same name + `.mcmeta` extension declares the animation:

```json
{
  "animation": {
    "frametime": 4,
    "interpolate": false
  }
}
```

- `frametime` — ticks per frame at 20 ticks/second (`4` = 0.2 s/frame; `20` = 1 s/frame).
- `interpolate: true` — smooth cross-fade between frames. Use for glow pulses, hue shifts, brightness breathes. Bad for sprite-style frame changes where each frame should be a discrete pose.
- `frames` (optional) — array to reorder or hold individual frames. Lets you, e.g., dwell on frame 0 for a long beat then quick-cycle the rest:

  ```json
  {
    "animation": {
      "frames": [
        { "index": 0, "time": 20 },
        { "index": 1, "time": 3 },
        { "index": 2, "time": 3 },
        { "index": 3, "time": 3 }
      ]
    }
  }
  ```

### Generating the strip

Two reliable patterns:

**Codex `generate_sheet`** — ask for N frames as a horizontal sheet, then stack to vertical with Pillow (codex respects cell boundaries better when the sheet is laid out horizontally with visible gridlines, then you re-stack):

```python
from PIL import Image
from codex_image import generate_sheet

generate_sheet(
    regions=[
        {"name": "f0", "prompt": "16x16 glowing crystal block face, dim phase, dark blue glow"},
        {"name": "f1", "prompt": "16x16 glowing crystal block face, mid-bright phase, cyan glow"},
        {"name": "f2", "prompt": "16x16 glowing crystal block face, peak-bright phase, bright cyan-white glow"},
        {"name": "f3", "prompt": "16x16 glowing crystal block face, mid-bright phase fading, cyan glow"},
    ],
    cell_size=(16, 16),
    out_dir="/tmp/anim_frames",
)
# Re-stack the 4 individual frames into a vertical strip
strip = Image.new("RGBA", (16, 64))
for i in range(4):
    frame = Image.open(f"/tmp/anim_frames/f{i}.png").convert("RGBA")
    strip.paste(frame, (0, i * 16))
strip.save("src/main/resources/assets/<mod_id>/textures/block/<name>.png")
```

**Pillow alone** — for simple programmatic animations (hue cycle, brightness pulse) where a hand-coded loop gives crisper, more predictable frame-to-frame deltas than codex. Same Pillow patterns as one-off textures, just N times into a vertical strip.

### Writing the `.mcmeta`

Always pair the PNG with its `.mcmeta`. File name is the PNG name plus `.mcmeta` (so `.png.mcmeta` literally — yes, the `.png` is part of the filename):

```
assets/<mod_id>/textures/block/glowing_crystal.png
assets/<mod_id>/textures/block/glowing_crystal.png.mcmeta
```

```python
import json, pathlib
mc = {"animation": {"frametime": 6, "interpolate": True}}
pathlib.Path(out_png_path + ".mcmeta").write_text(json.dumps(mc, indent=2))
```

Path convention:
- Block animated texture: `assets/<mod_id>/textures/block/<name>.png` + `.mcmeta`
- Item animated texture:  `assets/<mod_id>/textures/item/<name>.png` + `.mcmeta`
- Custom block-side variants (different animation per face): use separate PNGs per face referenced from the block model's `"textures"` map, each with its own `.mcmeta`.

## Default to AI textures (codex image_gen)

When the user doesn't specify, use AI-generated textures via `tools/codex_image.py` — it's the right default for most blocks, items, weapons, armor, and Tier B mob textures. The library handles all four codex landmines automatically. **Multiple textures can be generated in parallel safely** — see DEVELOPMENT.md "Generating AI textures" for the parallel batching pattern.

Use hand-coded Pillow only when:
- The user explicitly asked for "pixel-by-pixel" / "let me paint it"
- You need exact pixel control (e.g. a known-shape icon, palette texture, UV-aligned skin)
- The codex output doesn't render correctly and you need a fallback

**For Tier A mob skins specifically** (cube-model UV-mapped 64×64 PNGs in vanilla Steve layout), Pillow is usually better — codex `image_gen` doesn't respect UV cell boundaries reliably. Documented in your global `feedback_minecraft_skins.md` memory.

## How to build a Tier B (polygonal) mob — direct Blender MCP flow

This replaces every old "PARTS list" / "obj_writer" / "per-mob driver script" pattern. You drive Blender directly. **Read this section carefully before your first Tier B build.**

### Don't crib from any existing files in the repo

The scaffold ships with no example mobs and the geometry of any mob built by a prior session must NOT be read as a style template — not the `.obj`, not the `.geo.json`, not the entity Java. The user wants every new Tier B mob built fresh from their Q1c answer + visual description. Structural skeleton (Java class shape, renderer subclass, registration entries, lang / loot / spawn-egg JSON) comes from the copy-paste templates in [DEVELOPMENT.md → Tier B mob — Java + JSON templates](DEVELOPMENT.md#tier-b-mob--java--json-templates-copy-paste-reference), not from prior mob files.

### Entity coordinate convention

- **Y is up** (Minecraft convention — same as Blender's default Z-up coords get remapped on export, but `corelib_obj_export` keeps Y-up).
- **Origin at the entity's feet** — the entity's `BoundingBox` extends UP from (0, 0, 0). Don't put parts below y=0 or they'll clip into the floor.
- **Forward is -Z** (Minecraft convention; the entity looks toward negative Z).
- **Typical humanoid mob size:** roughly `0.6 × 1.8 × 0.4` (width × height × depth) → put parts in approximately `x ∈ [-0.35, 0.35]`, `y ∈ [0, 1.85]`, `z ∈ [-0.25, 0.25]`. Scale down for smaller mobs, scale up for bigger ones (2-block-tall ogre, etc.).
- **The entity's `sized(width, height)` in `ModEntities` must match** — this is the hitbox, not the visual mesh. Use width = max horizontal extent, height = max vertical extent. Round generously (e.g. mesh up to y=1.83 → register as `sized(0.7F, 1.95F)`).
- For your test mob, set the hitbox first, then build the mesh within it.

### Required: the Blender MCP socket must be running

Before any `mcp__blender__*` call, verify the socket is reachable: `mcp__blender__get_scene_info`. If it fails:
1. Try `nohup scripts/blender_mcp_start_headless.sh > /tmp/blender-mcp.log 2>&1 &` from the Bash tool (background, non-interactive). Wait ~4 seconds, retry.
2. If still failing with connection-refused, Blender itself isn't installed — point the user at `!scripts/install_blender_mcp.sh`.

### The pattern

You'll typically use **two** `mcp__blender__execute_blender_code` calls:

**Call 1 — build the mesh, export OBJ, render preview JPGs.** This is where all the geometry happens.

**The example below is intentionally scaffolding-only.** Step 2 (build geometry) is left empty because the right primitives are entirely a function of the user's Q1c answer — there is no "default mob shape" to start from. **Do not** write an `add_box` (or `add_anything`) helper at the top of your build script; helpers that take one primitive type lock you into it before you've thought about whether that's the right primitive. Call `bpy.ops.mesh.primitive_*_add` directly per part. The vocabulary block under step 2 shows one-line snippets for each primitive type; pick whichever fits the part you're building.

```python
import bpy, bmesh, math, mathutils, os
from corelib_obj_export import export_corelib_obj

# --- 1. wipe scene ---
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.materials):
    bpy.data.materials.remove(m)
for im in list(bpy.data.images):
    bpy.data.images.remove(im)

# --- 2. BUILD YOUR GEOMETRY HERE ---
# Y is up (Minecraft convention); origin at entity's feet; forward is -Z.
# The right primitives are dictated by the user's Q1c answer, not by any
# template. Vocabulary — pick what fits each part, mix freely:
#
#   # rotated cube — good for blocky parts (Q1c = "Minecraft-style")
#   bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 1.5, 0))
#   o = bpy.data.objects[-1]; o.name = "torso"
#   o.scale = (0.4, 0.6, 0.3); o.rotation_euler = (0, 0, math.radians(8))
#   bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
#
#   # UV sphere — good for organic heads, joints (shoulders / hips / knees),
#   # eyes, berries, anything rounded (Q1c = "in-between" or "modern")
#   bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8,
#                                        radius=0.22, location=(0, 1.7, 0))
#
#   # cylinder — good for limbs, necks, fingers, pipes, weapon shafts
#   bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.08, depth=0.6,
#                                       location=(0.3, 1.0, 0))
#
#   # cone — good for hats, horns, spikes, tails, claws
#   bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.18, depth=0.4,
#                                   location=(0, 2.1, 0))
#
#   # bmesh edit — taper a cylinder, pinch a sphere, edit any verts:
#   o = bpy.data.objects[-1]
#   bm = bmesh.new(); bm.from_mesh(o.data)
#   for v in bm.verts:
#       if v.co.z > 0:            # taper the top vert ring
#           v.co.x *= 0.6; v.co.y *= 0.6
#   bm.to_mesh(o.data); bm.free()
#
#   # Subsurf modifier — smooth a low-poly base (Q1c = "modern" only)
#   o.modifiers.new("subsurf", type="SUBSURF").levels = 1
#   bpy.context.view_layer.objects.active = o
#   bpy.ops.object.modifier_apply(modifier="subsurf")
#
# Collect every visible object into `parts` so steps 3 (UVs) and 5 (material)
# can iterate them. Append as you go, don't hard-code a fixed list.
parts = []
# ... your geometry calls go here, appending each created object to parts ...

# --- 3. assign UVs. You decide the texture layout — the exporter writes
#       whatever UVs you set. Simple flat-color layout: every part samples
#       a single pixel of a small palette texture. Detailed layout: each
#       face is unwrapped to a specific region. Up to you.
for o in parts:
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        for loop in face.loops:
            loop[uv].uv = (0.5, 0.5)   # flat color from texture's center pixel
    bm.to_mesh(o.data)
    bm.free()

# --- 4. export OBJ — the helper handles the 4 corelib gotchas. ---
OBJ_PATH = "/home/<user>/repos/<this_repo>/src/main/resources/assets/<mod_id>/models/entity/<name>.obj"
export_corelib_obj(path=OBJ_PATH)

# --- 5. render multi-angle previews. The user reviews these BEFORE you
#       write any Java. Cycles CPU, 32 samples, 720x720, three angles. ---
TEXTURE_PATH = "/home/<user>/repos/<this_repo>/src/main/resources/assets/<mod_id>/textures/entity/<name>.png"
img = bpy.data.images.load(TEXTURE_PATH)
img.colorspace_settings.name = "sRGB"
mat = bpy.data.materials.new("EntTex"); mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
tex_node.image = img
tex_node.interpolation = "Closest"   # crisp pixel-art sampling
mat.node_tree.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.85
for o in parts:
    o.data.materials.append(mat)

bpy.ops.mesh.primitive_plane_add(size=4, location=(0,0,0))   # ground
ground = bpy.data.objects[-1]; ground.name = "Ground"
gmat = bpy.data.materials.new("MG"); gmat.use_nodes = True
gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.93,0.94,0.97,1.0)
ground.data.materials.append(gmat)

bpy.ops.object.camera_add(location=(2.4,-2.4,1.4))
cam = bpy.data.objects[-1]
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type="SUN", location=(3,-2,5))
sun = bpy.data.objects[-1]
sun.data.energy = 5.5
sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(30))

scn = bpy.context.scene
scn.render.engine = "CYCLES"
scn.cycles.device = "CPU"
scn.cycles.samples = 32
scn.render.resolution_x = 720
scn.render.resolution_y = 720
scn.render.image_settings.file_format = "JPEG"
scn.world.use_nodes = True
scn.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62,0.72,0.90,1.0)

OUTPUT_DIR = os.path.expanduser(os.environ.get("PREVIEW_OUTPUT_DIR") or "~/Desktop")
PREFIX = "<name>"
# Six angles. Tuple format: (label, cam_xyz, look_at_xyz, up_axis_str).
# Blender scene is Z-up; mob faces -Y, so cam at -Y is the front view.
# `up_axis_str` is what direction maps to "up in the image" — flipped to "-Y"
# for the top-down view so the mob's front edge sits at the top of the tile.
VIEWS = [
    ("front",      (0.0, -3.0, 1.4),  (0.0, 0.0, 1.0), "Y"),
    ("side",       (3.0,  0.0, 1.4),  (0.0, 0.0, 1.0), "Y"),
    ("behind",     (0.0,  3.0, 1.4),  (0.0, 0.0, 1.0), "Y"),
    ("threeQ",     (2.4, -2.4, 1.4),  (0.0, 0.0, 1.0), "Y"),
    ("close_face", (0.0, -1.0, 1.55), (0.0, 0.0, 1.5), "Y"),
    ("topdown",    (0.0,  0.0, 4.0),  (0.0, 0.0, 1.0), "-Y"),
]
individual = []
for label, cam_loc, look_at, up in VIEWS:
    cam.location = mathutils.Vector(cam_loc)
    cam.rotation_euler = (mathutils.Vector(look_at) - cam.location).to_track_quat("-Z", up).to_euler()
    out_path = os.path.join(OUTPUT_DIR, f"{PREFIX}_{label}.jpg")
    scn.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    individual.append((label, out_path))

# Tile all 6 into one composite for review (3 across, 2 down, labeled).
# Reading one composite costs the agent ~6× fewer image tokens than reading
# six individuals, and is easier on the user too. Individuals are kept on
# disk so you can still open one at full res for detail.
#
# Tiling uses Pillow via the SYSTEM python (not Blender's bundled python,
# which doesn't ship with PIL). Pillow is already a hard dep of this scaffold
# (tools/codex_image.py uses it). This sidesteps the ImageMagick-vs-GraphicsMagick
# split that some Linux distros (Mint, recent Ubuntu) ship with — GraphicsMagick's
# `montage` compat layer is incomplete and silently outputs only one tile.
import subprocess, json
GRID_PATH = os.path.join(OUTPUT_DIR, f"{PREFIX}_preview_grid.jpg")
tile_payload = json.dumps({
    "tiles":  [(label, path) for label, path in individual],
    "out":    GRID_PATH,
    "tile_w": 480, "tile_h": 480,
    "cols":   3,   "rows":   2,
    "gap":    8,
    "label_h": 32,
    "bg":     "#1c1f24",
    "fg":     "white",
})
tile_script = r'''
import json, sys
from PIL import Image, ImageDraw, ImageFont
cfg = json.loads(sys.stdin.read())
TW, TH, GAP, LH = cfg["tile_w"], cfg["tile_h"], cfg["gap"], cfg["label_h"]
COLS, ROWS = cfg["cols"], cfg["rows"]
W = COLS * TW + (COLS + 1) * GAP
H = ROWS * (TH + LH) + (ROWS + 1) * GAP
canvas = Image.new("RGB", (W, H), cfg["bg"])
draw = ImageDraw.Draw(canvas)
font = None
for path in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
             "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
             "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
    try:
        font = ImageFont.truetype(path, 22); break
    except OSError:
        continue
if font is None:
    font = ImageFont.load_default()
for i, (label, path) in enumerate(cfg["tiles"]):
    row, col = divmod(i, COLS)
    x = GAP + col * (TW + GAP)
    y = GAP + row * (TH + LH + GAP)
    tile = Image.open(path).convert("RGB").resize((TW, TH), Image.LANCZOS)
    canvas.paste(tile, (x, y))
    bbox = draw.textbbox((0, 0), label, font=font)
    tw = bbox[2] - bbox[0]
    draw.text((x + (TW - tw) // 2, y + TH + 4), label, fill=cfg["fg"], font=font)
canvas.save(cfg["out"], "JPEG", quality=88)
print(cfg["out"])
'''
result = subprocess.run(
    ["/usr/bin/python3", "-c", tile_script],
    input=tile_payload, text=True, capture_output=True,
)
if result.returncode == 0:
    print("PREVIEW GRID:", result.stdout.strip())
else:
    print("WARNING: grid composite failed:")
    print(result.stderr[:800])
print("INDIVIDUAL RENDERS:", [p for _, p in individual])
```

**Call 2 (optional)** — if a re-render is needed after a tweak, you can repeat the build steps or just adjust object positions / rotations and re-render. Tier B iteration is much faster than the Java edit-build-deploy loop — use it.

### Performance tip — overlap texture gen with the mesh build

`codex image_gen` is the long pole (~30–120 seconds per call); the Blender build+export step is ~5–15 seconds. You can overlap them by firing both tool calls in the same response:

```
Turn 1 (single assistant response, parallel tool calls):
  ┬─ Bash: PYTHONPATH=tools python3 -c "from codex_image import generate; generate(...)"   (run_in_background=true)
  └─ mcp__blender__execute_blender_code:  build mesh + export OBJ ONLY  (no render yet — render needs the texture)

Turn 2: wait for the background Bash to finish, then
  mcp__blender__execute_blender_code: load texture as material + render 3 angles
```

Save the OBJ in Turn 1 so Blender's scene has the geometry persisted. Don't render in Turn 1 — the texture file might not exist yet. Savings: typically 10–20% off the wall-clock for the whole Tier B build. Skip this optimization if you'd rather keep the flow simple; it's not required.

### About UVs and textures

You decide the texture layout. The exporter writes exactly the UVs you set in Blender. Common patterns:

- **Single flat-color palette** (simplest): every face's loop UVs point to one pixel of a small palette PNG. Variations: per-part palette, per-face palette. Works great for cartoony / simple mobs.
- **Standard atlas** (medium): the texture is a structured PNG (e.g. a 4×4 grid of material swatches at 64×64); each part samples a specific cell. You write the UV math.
- **Full UV unwrap** (detailed): use `bpy.ops.uv.smart_project()` or `bpy.ops.uv.cube_project()` to auto-unwrap each part, then either AI-generate or hand-paint a texture matching the unwrap.

The texture itself is generated separately — usually with `tools/codex_image.py`. Save to `src/main/resources/assets/<mod_id>/textures/entity/<name>.png` before the Blender build call (or during, via `subprocess`).

## Preview + pause for user review (Tier B mobs — REQUIRED)

For Tier B mobs the workflow has **TWO review gates** after rendering the multi-angle preview JPGs. Both must pass before you proceed.

**Gate 1 — your self-eval** (technical correctness):
Render the six-angle preview grid (front / 90° side / 180° behind / three-quarter / close face / top-down — all tiled into `<name>_preview_grid.jpg` via ImageMagick) and look at it. Read ONLY the composite, not the individuals, to keep image-token cost low; open an individual only if the grid surfaces something you need to inspect at full res. Catches *technical* bugs — see the full checklist in DEVELOPMENT.md ("Tier B preview-eval checklist"). The **two recurring failure modes** you must check every time:

1. **Disconnected parts.** Adjacent body parts that should touch (head↔neck, neck↔torso, shoulder↔upper arm, elbow↔forearm, wrist↔hand, hip↔thigh, knee↔calf, ankle↔foot) frequently come out with visible gaps in the three-quarter view. The agent's eye misses these more often than the user's. Walk the body's connection graph explicitly on the three-quarter render: for each adjacent pair, is there visible empty space between them? If yes, the parent part needs to extend further OR the child needs to be repositioned to overlap by at least a few pixels. Re-render after fixing.

2. **Flat-colored parts** (if Q1b = Detailed or Maximum). Any part rendered as a uniform solid color block, while the rest of the mesh has visible texture detail, means that part's UVs got collapsed to one pixel. Check the UV layer for that object; fix UVs to span a content-bearing region of the atlas; re-export.

Fix any technical issue you find — adjust the mesh / UVs, re-render, re-check. Don't show Gate 2 to the user until Gate 1 passes.

**Gate 2 — STOP and show the user** (creative match):
Once your self-eval passes, **PAUSE.** List **every generated visual asset path** in the pause message and wait. This is more than just the mob preview grid — bundle the spawn-egg PNG, every generated item icon (powder packet, dropped item, custom weapon/armor icon, etc.), and any other visual asset you produced for this build into one review pass.

**Why bundle everything:** the agent's self-eval on 16×16 / 32×32 pixel-art icons is unreliable. Color hallucination ("the box is blue" when it's actually green), missing fine-print defects, and codex's baked-checkerboard-as-opaque-pixels failure all slip through agent inspection routinely — but a human catches them at a glance. Catching them at Gate 2 means a 30-second texture regen + re-pause; catching them post-deploy means regenerate + rebuild jar + redeploy + retest in MultiMC. Roughly **5× the iteration cost** for the same fix. Bundle the asset list explicitly so the user can review every visual in one pass.

Example: *"Ready for review — please eyeball each of these and tell me if any need tweaks:*
- *Mob preview grid: `~/Desktop/<name>_preview_grid.jpg` (6 angles in one image; full-res individuals in the same dir as `<name>_front.jpg` etc.)*
- *Spawn egg icon: `src/main/resources/assets/<mod_id>/textures/item/<name>_spawn_egg.png`*
- *`<extra_item>` icon: `src/main/resources/assets/<mod_id>/textures/item/<extra_item>.png`*
- *(repeat per generated item)*
*"* Then wait for either:
- "looks good, keep going" → proceed to writing the Java entity class + renderer + registration + build + deploy
- "tweak X" → adjust the mesh in a fresh `execute_blender_code` call, re-export, re-render, re-show. Loop until the user approves.

**Do NOT write the Java entity class or its renderer until the user confirms.** Mesh tweaks are cheap at this stage (seconds). Once you've written Java + run `./gradlew build`, the iteration cost is ~5× higher (rebuild + redeploy + relaunch MultiMC). Catch creative mismatches BEFORE the Java step.

For Tier A mobs, blocks, items, weapons, armor: there's no comparable cheap visual gate. Skip these pause points and let the user catch issues in-game directly.

## When the user wants to change something on an existing mob

For a **Tier B mob**, send a fresh `mcp__blender__execute_blender_code` call that builds the new shape — same pattern as the original build, with adjusted coordinates / rotations / primitives. Re-export the OBJ to the same path. Re-render preview JPGs. Show the user. The OBJ in `src/main/resources/.../models/entity/<name>.obj` is the source of truth in-game; regenerating it overwrites in place.

You do NOT need to keep a per-mob "driver" file in the repo. The build recipe lives in the conversation. If the user iterates, you iterate via repeated MCP calls. If they later come back to revisit the mob and you don't remember the recipe, ask them what they want changed and rebuild fresh — the existing OBJ is your reference for "where things were."

For a **Tier A mob**, edit the `.geo.json` / `.animation.json` / Java directly. No Blender involved.

## Customization workflow for forks

If the user clones this scaffold to start a new mod, the workflow is:
1. `scripts/setup.sh` — interactive prompts for `mod_id`, `mod_name`, `mod_authors`, paths.
2. If `mod_id` changes from the default `aitemplate`, the setup script offers to run `scripts/rename_mod.sh` to rename throughout the source.
3. `scripts/install_blender_mcp.sh` — installs headless Blender + MCP socket + symlinks `corelib_obj_export.py` into Blender's modules dir. Only needed for Tier B mobs.

If they ask you to "rename the mod to X", run `scripts/rename_mod.sh X com.<author>` (after updating `gradle.properties`).

## Do not commit

- `gradle.properties` (per-host; `.example` is the committed template)
- `config.sh` (per-host paths; `.example` is the committed template)
- `build/`, `runs/`, `.gradle/`, `__pycache__/`, `*.pyc`
- Anything under `.claude/` (project-local agent config)

All of these are in `.gitignore`.
