# CLAUDE.md — agent instructions for this repo

**You are reading this because you're working in `ai-minecraft-mobs-creator`. Read this file fully before doing anything else. It's the complete reference — behavioral rules at the top, technical depth at the bottom — and you should not need to "poke around" the codebase to figure out the workflow. Human-facing how-to (Blender install, build commands, file layout) is in [README.md](README.md) if you need to point the user at it.**

## Important framing: helpers stay narrow, you stay in charge of geometry

The repo gives you exactly two Python helpers, both narrow:

- **`tools/codex_image.py`** — wrapper around the `codex` CLI's `image_gen` tool. Handles all four codex landmines (stdin DEVNULL, `--ephemeral`, `--json` + `thread_id` parsing, downscale). Use it whenever you need an AI-generated texture.
- **`tools/corelib_obj_export.py`** — a Blender-Python module that the installer symlinks into `~/.config/blender/<version>/scripts/modules/`. From inside any Blender Python call you make via the `mcp__blender__*` tools, you can `from corelib_obj_export import export_corelib_obj` and write a corelib-compatible OBJ in one line. It handles face triplets, UV V-flip, triangulation, and runs a CCW-outward winding sanity check.

That's everything. **There is no mesh-building helper, no per-mob driver script, no preview-rendering wrapper, no PARTS-list convention.** For Tier B (polygonal) mobs, **you drive Blender directly via the `mcp__blender__execute_blender_code` tool**: bmesh whatever geometry you want — rotated boxes, scaled cylinders, joined primitives, edited verts, anything Blender can express — then call `export_corelib_obj(path='...')`. You also render previews in the same `execute_blender_code` call (or a follow-up one) using `bpy.ops.render.render(write_still=True)`.

The **technical constraints** that DO bind you:

- For corelib (Tier B) OBJs: the four gotchas (face triplet `v/vt/vn`, V-flip, triangulation, CCW outward). `corelib_obj_export.export_corelib_obj()` handles them all — use it. If you hand-write an OBJ for some reason, address all four yourself; see "The four critical OBJ gotchas (Tier B)" in the Technical reference section below.
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

Behavioral rules are up top; technical depth lives in the "Technical reference" section at the bottom of this file.

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

### Build fresh by default — ASK before using ANY template or existing file as a starting point

The scaffold ships with **no example mobs or blocks** in `src/`, and that's deliberate. After one or more mobs have been built in a session (or in a downstream working repo with many prior builds), the temptation will return: *"the existing mob is Tier A, so this new one should be Tier A too,"* or *"the last mob used spheres, so I'll do spheres here."* **No.** Each new asset is built fresh from the user's answers (or saved preferences in `.claude/mob_preferences.md`). If you catch yourself thinking *"the existing mobs are mostly X, so X is a safe default,"* stop — that's exactly the bias the user wants you to drop.

**Default for Java/JSON skeleton structure: build from scratch.** Use your NeoForge 1.21.1 training, the official docs, and the rules in the Technical reference section below as *reference material* — but do not silently copy-paste from any template (including the "Tier B Java + JSON templates" section below) or any existing in-repo file. Even those templates encode prior structural choices (default goal sets, attribute values, registration patterns, hitbox sizes, parent classes); silently applying them biases the agent toward "standard humanoid mob" shapes regardless of what the user actually asked for.

**ASK the user explicitly before using any pre-existing thing as a starting point.** Offer three named options:

> *"For the structural Java/JSON skeleton, I can:*
>   *(a) **Build from scratch** — lowest bias, I'll write boilerplate from first principles tailored to what you described.*
>   *(b) **Start from the generic template** (Technical reference → "Tier B Java + JSON templates" below) — saves a couple minutes of boilerplate writing; still carries the template's default patterns (humanoid hitbox, standard goal set, etc.) which I'll then tailor.*
>   *(c) **Copy the structure of an existing in-repo entity** (`<X>Entity.java` — because it has `<specific pattern>` that maps to what you asked for) — fastest if the match is close, biggest bias risk if it's not.*
> *Which do you prefer?"*

The recommended default is **(a)**. Offer (b) and (c) only when you have a specific reason to think they'd help. If the user has a saved trust preference (e.g., *"always use option b unless I say otherwise"* in `.claude/mob_preferences.md`), honor it; otherwise ask each time.

Visual / geometric / personality / tier-choice / detail-level reference from existing files is **never** allowed regardless of the user's structural-template choice — those answers always come from user input.

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
- "**Articulated toy / nutcracker / ball-joint doll / plushy** — smooth primitives, but with **visible part boundaries** (sphere head sitting on torso, cylinder arms with ball-joint shoulders, cylinder legs ending where boots begin). Reads as 'assembled from parts.'" → discrete `bmesh.ops.create_uvsphere` / `create_cone` placed at coordinates, **no bridging between primitives**. Good for robots, toy soldiers, plushies, mechanical mobs, action figures, dolls.
- "**Sculpted continuous body** — no visible part boundaries: limbs taper into wrists, neck blends into head, the whole body reads as one piece (think Pixar character, PS3-era 3D human, sculpted-clay aesthetic). NOT a collection of parts; a continuous form." → discrete primitives PLUS `bmesh.ops.bridge_loops` between adjacent primitives' edge rings + `f.smooth = True` per face + a Subsurf modifier (1–2 levels) applied before export + ring-vertex tapering along limb length. **See "Sculpted vs assembled Tier B looks (the nutcracker trap)" in the Technical reference below — this is the technique-heavy option and the agent has historically defaulted to the articulated path when this was actually wanted.**

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
- **Don't open any existing `.obj` / `.geo.json` / entity Java for style cues** — even if a prior session built one. Use the copy-paste templates further down (Technical reference → "Tier B Java + JSON templates") for structural skeleton, and build the mesh fresh from the user's Q1c answer + visual description.
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
# Bbox of the IN-SCENE bmesh:
#   - If you're using pattern (A) [build Z-up + rotate-at-export]: scene is Z-up here, so
#     in-scene "height" = extent.z (becomes Y in the final OBJ after the rotate step).
#   - If you're using pattern (B) [Y-up throughout]: scene is Y-up here, so height = extent.y.
# Either way, compute this sizing check BEFORE the export rotation so the values
# represent the actual in-scene mesh you can still tweak.
height = extent.z   # ← pattern (A); change to extent.y if you're using pattern (B)
width  = max(extent.x, extent.y)   # ← pattern (A); max(extent.x, extent.z) for pattern (B)
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

When the user doesn't specify, use AI-generated textures via `tools/codex_image.py` — it's the right default for most blocks, items, weapons, armor, and Tier B mob textures. The library handles all four codex landmines automatically. **Multiple textures can be generated in parallel safely** — see "Generating AI textures" further down for the parallel batching pattern.

Use hand-coded Pillow only when:
- The user explicitly asked for "pixel-by-pixel" / "let me paint it"
- You need exact pixel control (e.g. a known-shape icon, palette texture, UV-aligned skin)
- The codex output doesn't render correctly and you need a fallback

**For Tier A mob skins specifically** (cube-model UV-mapped 64×64 PNGs in vanilla Steve layout), Pillow is usually better — codex `image_gen` doesn't respect UV cell boundaries reliably. Documented in your global `feedback_minecraft_skins.md` memory.

### Codex transparency-checkerboard trap (item icons that need real alpha)

**Codex routinely paints the editor's transparency-indicator checkerboard pattern as actual opaque pixels** when you ask it for a transparent-background icon. The PNG ships with a baked-in grey-checker rectangle where transparency was supposed to be — looks normal in some image viewers but renders as a visible checker texture in the inventory slot in-game. Caught post-deploy on the cheese-powder-packet icon (2026-05-23).

**Why visual self-eval misses it:** some image viewers render the baked checkerboard the same way they'd render real transparency (with their own UI checker behind the alpha channel), so the agent can't reliably tell from a Read of the PNG whether the checker is real transparency or opaque pixels. The user opening the file in a tool that handles alpha correctly catches the difference instantly.

**How to apply:**

1. **Don't ask codex for "transparent background"** in the prompt — that phrasing triggers the checkerboard-as-pixels failure. Ask for a SOLID color background instead (white, single color, neutral), then flood-fill it to transparent in Pillow post-processing:
   ```python
   from PIL import Image, ImageDraw
   im = Image.open(path).convert("RGBA")
   ImageDraw.floodfill(im, (0, 0), (0, 0, 0, 0), thresh=30)
   im.save(path)
   ```
2. **For pixel-art icons ≤ 32×32, prefer hand-drawn Pillow** over codex. Guarantees real transparency + crisp pixel boundaries, and codex's value-add at that small a canvas is low anyway. The mac-n-cheese powder-packet icon's second attempt switched to Pillow and was clean in one pass.
3. **At Gate 2, explicitly invite the user to check transparency** on each item icon — *"the spawn-egg box and powder packet are at `<path>`; please verify the backgrounds are actually transparent (open in an image viewer that respects alpha) — codex sometimes bakes the editor's transparency checker as opaque pixels and I can't always tell."* This counts as one of the bundled visual assets per the Gate 2 rule.

## How to build a Tier B (polygonal) mob — direct Blender MCP flow

This replaces every old "PARTS list" / "obj_writer" / "per-mob driver script" pattern. You drive Blender directly. **Read this section carefully before your first Tier B build.**

### Don't crib from any existing files in the repo

The scaffold ships with no example mobs and the geometry of any mob built by a prior session must NOT be read as a style template — not the `.obj`, not the `.geo.json`, not the entity Java. The user wants every new Tier B mob built fresh from their Q1c answer + visual description.

**For the structural Java/JSON skeleton, default to building from scratch** — see "Build fresh by default — ASK before using ANY template or existing file as a starting point" above. The Tier B templates in the Technical reference section below and any existing in-repo entity file are all opt-in starting points that require explicit user consent before use.

### Entity coordinate convention

- **Y is up. Forward is -Z.** (Minecraft convention.) **The OBJ exporter writes Blender coordinates verbatim — it does NOT remap axes.** Your bmesh MUST be in Y-up convention (feet at Y=0, head at Y+, mob faces -Z) by the time you call `export_corelib_obj(...)`. Skipping this ships a mob that spawns **face-down** in-game (height along Z = a horizontal axis in Minecraft → mob lies on its side). Caught 2026-05-23 on Sailor Moon + Luna's first deploy.
- **Two valid build patterns** (pick one and stick with it through the whole script):
  - **(A) Build Z-up in Blender, rotate-to-Y-up just before export** (recommended — Blender's primitives, gizmo, and preview cameras all default to Z-up, so the in-scene work is natural):
    ```python
    import mathutils
    # After all geometry + UVs are set on `bm`, immediately before `bm.to_mesh(...)`:
    R = mathutils.Matrix(((-1, 0, 0, 0),    # (x, y, z) → (-x, z, y)
                          ( 0, 0, 1, 0),    # Blender Z-up / forward -Y  →  MC Y-up / forward -Z
                          ( 0, 1, 0, 0),
                          ( 0, 0, 0, 1)))
    bmesh.ops.transform(bm, matrix=R, verts=bm.verts[:])
    # Recompute Y-axis bbox after the rotation to verify height landed where you wanted:
    lo_y = min(v.co.y for v in bm.verts); hi_y = max(v.co.y for v in bm.verts)
    print(f"post-rotate height (Y span): {hi_y - lo_y:.2f}b  feet at Y={lo_y:.2f}")
    ```
  - **(B) Build Y-up from the start** — treat Y as vertical from the first vertex, never use Blender's default Z-up primitives without rotating them. Working reference: `mac_n_cheese_plush.obj` was built this way (its Y span is the height, Z span is the depth). Awkward because Blender's gizmo still shows Z as up — you're constantly translating between "what Blender shows me" and "what coords mean in my script."
- **Origin at the entity's feet** — the entity's `BoundingBox` extends UP from (0, 0, 0) in the FINAL Y-up OBJ. Don't put parts below Y=0 (in final coords) or they'll clip into the floor.
- **Typical humanoid mob size (in final Y-up coords):** roughly `0.6 × 1.8 × 0.4` (width × height × depth) → put parts in approximately `x ∈ [-0.35, 0.35]`, `y ∈ [0, 1.85]`, `z ∈ [-0.25, 0.25]`. Scale down for smaller mobs, scale up for bigger ones (2-block-tall ogre, etc.).
- **The entity's `sized(width, height)` in `ModEntities` must match** — this is the hitbox, not the visual mesh. After pattern (A)'s rotation OR pattern (B)'s build, use width = max horizontal extent (max of X-span and Z-span), height = Y-span. Round generously (e.g. mesh up to Y=1.83 → register as `sized(0.7F, 1.95F)`).
- **Sanity check before export:** print `min/max` along each axis. If `height = Y-span` and `feet ≈ 0` and `max(X-span, Z-span) ≈ visual_width`, you're shipping upright. If `height = Z-span`, you forgot the rotation and the mob ships face-down.

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

# --- 4. ROTATE to Y-up just before export. The exporter writes Blender coords
#       verbatim — it does NOT remap axes. The in-scene mesh above is Z-up
#       (Blender default), so we rotate each part's bmesh to Y-up here so the
#       OBJ ships upright in Minecraft. Skipping this = mob spawns face-down.
#       See "Entity coordinate convention" earlier in this doc.
import mathutils
R = mathutils.Matrix(((-1, 0, 0, 0),    # (x, y, z) → (-x, z, y)
                      ( 0, 0, 1, 0),    # Blender Z-up / forward -Y  →  MC Y-up / forward -Z
                      ( 0, 1, 0, 0),
                      ( 0, 0, 0, 1)))
for o in parts:
    bm2 = bmesh.new()
    bm2.from_mesh(o.data)
    bmesh.ops.transform(bm2, matrix=R, verts=bm2.verts[:])
    bm2.to_mesh(o.data)
    bm2.free()
# (Single-bmesh builds: apply R to the single bm right before `bm.to_mesh(me)`
#  using `bmesh.ops.transform(bm, matrix=R, verts=bm.verts[:])`.)

# --- 5. export OBJ — the helper handles the 4 corelib gotchas. ---
OBJ_PATH = "/home/<user>/repos/<this_repo>/src/main/resources/assets/<mod_id>/models/entity/<name>.obj"
export_corelib_obj(path=OBJ_PATH)

# --- 6. render multi-angle previews. The user reviews these BEFORE you
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

### Build Tier B mobs as a SINGLE bmesh — not many juggled Blender objects

For any non-trivial Tier B build (>~5 parts), build the whole mob as **one** bmesh, then convert to one Object, instead of creating many separate Blender objects with `bpy.ops.mesh.primitive_*_add` and juggling them. The multi-object pattern is fragile in headless `-b` mode and burned through 3+ iteration cycles in a prior build (mac-n-cheese plushy, 2026-05-23; Sailor Moon repeated the same bugs the next session) before this was understood.

> **Important:** the single-bmesh skeleton below produces the **articulated / assembled** aesthetic (discrete primitives at coordinates → visible part boundaries → nutcracker / toy-soldier look). That's the right default for Q1c = "Articulated toy / nutcracker / plushy" but the wrong default for Q1c = "Sculpted continuous body." For sculpted, this skeleton is only the FIRST step — you must then apply the bridging + smoothing techniques in "Sculpted vs assembled Tier B looks" below. Don't ship a sculpted-character build that's only used this skeleton; it'll come out as a nutcracker.

**Failure modes the multi-object pattern hits:**

1. **`bpy.data.objects[-1]` doesn't return the most-recently-added object.** It's alphabetically sorted, not insertion-ordered. After `primitive_cube_add(name="torso") ; primitive_cylinder_add(name="arm")`, `objects[-1]` is `torso` (alphabetically last), not `arm`. Grabbing it then setting `scale`/`rotation_euler` rotates/scales the WRONG part. Manifests as: legs at the origin un-transformed, body floating into the sky, geometry scattered.
2. **Stale-vertex reads after `v.co =` writes.** If you write to `v.co` in a bmesh, then read `obj.data.vertices` to compute a bbox or `dy` floor-drop, you get the PRE-write coords because the mesh wasn't `update()`-ed. Bbox-driven scaling then computes the wrong scale factor and the mob comes out wrong-sized.
3. **`mathutils.Matrix.Scale(f, 4)` combined with translation can produce non-uniform results.** When you build `Matrix.Translation(...) @ Matrix.Scale(f, 4)` and apply it, the translation itself gets scaled in ways that break the "uniform scale around origin" expectation.
4. **Object name collisions silently rename.** `primitive_cylinder_add(name="leg_l")` after a prior `cylinder_add` may produce a name like `leg_l.001` or fall back to `Cylinder` — and your subsequent lookup by name fails. The stray default-named object then floats in the scene contributing to the rendered image.

**The single-bmesh pattern that avoids all four:**

```python
import bpy, bmesh, mathutils
from corelib_obj_export import export_corelib_obj

# Wipe scene as usual…

# Single bmesh — every part is geometry inside this one mesh.
bm = bmesh.new()

def place_sphere(bm, center, radius=0.25, segments=16, ring_count=8):
    """Add a uv-sphere to bm at `center` (mathutils.Vector). Returns the new faces."""
    pre = set(bm.faces)
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=ring_count,
                              radius=radius,
                              matrix=mathutils.Matrix.Translation(center))
    return [f for f in bm.faces if f not in pre]

def place_cylinder(bm, center, radius=0.10, depth=0.6, axis="Z"):
    """Cylinder = cone with equal radii. `axis` rotates the default Z-up cylinder."""
    M = mathutils.Matrix.Translation(center)
    if   axis == "X": M = M @ mathutils.Euler((0, math.radians(90), 0)).to_matrix().to_4x4()
    elif axis == "Y": M = M @ mathutils.Euler((math.radians(90), 0, 0)).to_matrix().to_4x4()
    pre = set(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12,
                          radius1=radius, radius2=radius, depth=depth, matrix=M)
    return [f for f in bm.faces if f not in pre]

def place_box(bm, center, size=(1,1,1), rot=(0,0,0)):
    M = (mathutils.Matrix.Translation(center) @
         mathutils.Euler(tuple(math.radians(a) for a in rot)).to_matrix().to_4x4() @
         mathutils.Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
    pre = set(bm.faces)
    bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    return [f for f in bm.faces if f not in pre]

# Tag each part's faces so you can per-face-UV later (e.g. eyes get black, body gets atlas region).
face_eye_left  = set(place_sphere(bm, mathutils.Vector((-0.06, -0.20, 1.65)), radius=0.015))
face_eye_right = set(place_sphere(bm, mathutils.Vector(( 0.06, -0.20, 1.65)), radius=0.015))
face_head      = set(place_sphere(bm, mathutils.Vector(( 0.00,  0.00, 1.60)), radius=0.18))
# … etc for body / arms / legs / accessories …

# Scale + drop-to-floor in ONE vertex pass — bm is the single source of truth, no stale reads.
lo_y = min(v.co.z for v in bm.verts)  # Z is up in Blender scene
hi_y = max(v.co.z for v in bm.verts)
target_height = 1.95  # from Q1d
factor = target_height / (hi_y - lo_y)
for v in bm.verts:
    v.co = mathutils.Vector((v.co.x * factor, v.co.y * factor, (v.co.z - lo_y) * factor))

# Recalc outward normals once at the end so the exporter's winding check passes.
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

# Per-face UV assignment using the tagged sets:
uv_layer = bm.loops.layers.uv.verify()
for f in bm.faces:
    if f in face_eye_left or f in face_eye_right:
        for loop in f.loops: loop[uv_layer].uv = (0.0, 0.0)  # black pixel
    else:
        # planar-project onto the atlas region for that body part
        for loop in f.loops: loop[uv_layer].uv = (loop.vert.co.x * 0.5 + 0.5,
                                                  loop.vert.co.z * 0.5 + 0.5)

# Build one Object from the bmesh, link to scene.
me = bpy.data.meshes.new("plushy_mesh")
bm.to_mesh(me); bm.free()
plushy = bpy.data.objects.new("plushy", me)
bpy.context.scene.collection.objects.link(plushy)

# Export — pass `objects=` explicitly so the ground/preview plane isn't included.
export_corelib_obj(path=OBJ_PATH, objects=[plushy])
```

Notes:
- `bmesh.ops.create_*` operates on the bmesh directly (no Blender object needed). Use `matrix=` to place/orient/scale at create-time.
- For curved tubes (a noodle, tail, ponytail, horn), generate vertex rings parametrically along a curve and bridge them: `bmesh.ops.bridge_loops(bm, edges=[…])` joins ring loops with quads.
- Cylinders aren't a separate primitive — use `create_cone` with equal radii.
- Scale + translate everything in one vertex pass at the end. Reads `bm.verts` directly — no `mesh.update()` dance.
- `bmesh.ops.recalc_face_normals` once at the end fixes any CCW/CW issues before export.

**Camera aiming caveat.** `to_track_quat`'s second arg is an axis string, restricted to `'X' / '-X' / 'Y' / '-Y' / 'Z' / '-Z'`. Passing a Vector raises `argument 2 must be str, not Vector`. For arbitrary up vectors (a tilted look-at, an offset top-down) build the look-at matrix by hand: `right = forward.cross(up).normalized(); up = right.cross(forward).normalized()`, then assemble a 3×3 from columns `[right, up, -forward]` and convert to Euler.

### Sculpted vs assembled Tier B looks (the "nutcracker trap")

The single-bmesh pattern above — `bmesh.ops.create_uvsphere` + `bmesh.ops.create_cone` placed at coordinates — produces an **assembled / articulated** aesthetic by default: visible part boundaries, ball-joint shoulders, cylinder-arm meets cylinder-bicep at a hard seam, head sits on torso without a neck, legs stop where boots begin. **This is the nutcracker / toy-soldier / ball-joint-doll look.** Three prior mobs (Nutcracker, Jester, Sailor Moon's first iteration) all came out with this aesthetic — even when the user picked the "modern video-game character" or "smooth/sculpted" option — because the agent reflexively places discrete primitives and stops there.

**This look is right for some mobs.** Articulated robots, wooden toys, plushies, action figures, ball-joint dolls, mechanical creatures — anywhere the user wants visible "parts." **It's wrong for anything organic** — humans, anime characters, animals, monsters with continuous bodies. If the user picked "Sculpted continuous body" in Q1c, the discrete-primitives-only pattern is a regression to nutcracker; you need the bridging + smoothing techniques below.

#### Decision: which aesthetic does the build need?

Match the Q1c answer:

| Q1c answer | Aesthetic | Technique |
|---|---|---|
| "Articulated toy / nutcracker / plushy" | assembled, visible seams | Discrete primitives at coordinates. Stop after `recalc_face_normals`. |
| "Sculpted continuous body" | continuous, no visible part boundaries | Discrete primitives **+ bridge loops + shade smooth + Subsurf + limb tapering** (below). |

#### Technique for the sculpted look

After placing the discrete primitives (sphere head, cylinder neck, cylinder arms, sphere shoulder joints, etc.), add these four steps before exporting:

**1. Bridge adjacent primitives' edge loops.** Find the ring of edges on each primitive that faces its neighbor (e.g., the bottom ring of the shoulder sphere + the top ring of the bicep cylinder) and join them with `bmesh.ops.bridge_loops`. The seam fills with quads and the two primitives become one continuous surface:

```python
# Helper: get the edge ring at a given Z (or X / Y) coordinate on a set of new faces.
def ring_edges_at_z(faces, z, eps=1e-4):
    ring = set()
    for f in faces:
        for e in f.edges:
            za, zb = e.verts[0].co.z, e.verts[1].co.z
            if abs(za - z) < eps and abs(zb - z) < eps:
                ring.add(e)
    return list(ring)

# After placing shoulder_sphere + bicep_cylinder, with shoulder at z=1.5 and bicep top at z=1.5:
shoulder_bottom_ring = ring_edges_at_z(shoulder_faces, z=1.5 - radius_s)
bicep_top_ring       = ring_edges_at_z(bicep_faces,    z=1.5)
bmesh.ops.bridge_loops(bm, edges=shoulder_bottom_ring + bicep_top_ring)
# Shoulder now flows continuously into bicep with quads — no visible seam.
```

For this to work cleanly the two rings must have **the same vertex count** — match `u_segments` on the sphere to `vertices` on the cone/cylinder (typically 12 or 16 for both). If counts differ, use `bmesh.ops.subdivide_edges` on the smaller ring first to match.

**2. Shade Smooth on every face.** Flips per-face normals to per-vertex normals; kills the flat-shaded facets that scream "polygonal model":

```python
for f in bm.faces:
    f.smooth = True
```

**3. Subdivision Surface modifier**, 1–2 levels, applied before export. Doubles or quadruples the vertex count and smooths the silhouette into Pixar-ish curves:

```python
# After bm.to_mesh(me) and creating the Object:
character = bpy.data.objects.new("character", me)
bpy.context.scene.collection.objects.link(character)
sub = character.modifiers.new("subsurf", type="SUBSURF")
sub.levels = 2                                       # 1 = subtle, 2 = strong, 3 = mushy
bpy.context.view_layer.objects.active = character
bpy.ops.object.modifier_apply(modifier="subsurf")    # apply before export — modifiers don't carry to OBJ
```

**4. Taper limbs along their length** instead of leaving constant-radius cylinders. The cylinder primitive gives you a tube; real arms/legs narrow toward the wrist/ankle. Walk the ring vertices and shrink XY based on Z (along-the-limb position):

```python
# For a vertical-axis limb spanning [z_min, z_max], narrow to e.g. 55% at the top.
for v in limb_verts:
    t = (v.co.z - z_min) / max(z_max - z_min, 1e-6)
    narrowing = 1.0 - 0.45 * t           # tweak per limb: 0.45 = strong taper, 0.15 = subtle
    v.co.x *= narrowing
    v.co.y *= narrowing
```

Do this BEFORE the subsurf step so the smoother sees a tapered base. Apply the same idea to: hair pigtails (narrow toward the tip), the neck (narrow between head and shoulders), the waist (narrow between torso and hips), the fingers (narrow toward the tip).

**Smell check before export (sculpted builds):** if your `execute_blender_code` script has no `bmesh.ops.bridge_loops` calls and no `Subsurf` modifier and Q1c was "sculpted continuous body," you're about to ship a nutcracker. Stop and add the techniques above.

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
Render the six-angle preview grid (front / 90° side / 180° behind / three-quarter / close face / top-down — all tiled into `<name>_preview_grid.jpg` via ImageMagick) and look at it. Read ONLY the composite, not the individuals, to keep image-token cost low; open an individual only if the grid surfaces something you need to inspect at full res. Catches *technical* bugs. The **two recurring failure modes** you must check every time:

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

## Commit + push policy — per-session trust, ASK by default

**The default for any fresh session in this repo is to ASK before committing.** After a logical unit of work, surface a clear *"ready to commit — should I push?"* prompt with the draft commit message. Wait for explicit go-ahead.

**Per-session trust may be granted.** When the user says *"yes always commit and push any changes,"* *"you can auto-commit in this session,"* etc.:
- That session may auto-commit + push at logical checkpoints WITHOUT asking each time
- The trust is **session-scoped** — it does NOT carry to a different session, even on the same repo, even minutes later, even with the same user
- Other concurrently-running sessions on the same repo still default to ASK

**Guards that apply even with auto-commit trust:**

1. **`git status --short` first.** If unexpected uncommitted files show up (especially in `src/`, `CLAUDE.md`, docs), they may be another concurrent session's in-progress work or your own forgotten edits. Read each one and decide deliberately whether to include — don't just sweep them in. This bit a 2026-05-23 build: one session's `git add -A` swept up a second session's CLAUDE.md edit into a "fix textures" commit with a wrong message.
2. **Stage by explicit file name, never `git add -A` / `git add .`.** Bulk-add is what lets parallel work get committed under the wrong message. Concretely relevant in this scaffold because the user often runs multiple Claude sessions concurrently on the same working tree.
3. **Group by logical change, not by file count.** One commit per coherent unit of work.
4. **These still need explicit per-instance consent** even with auto-commit trust: force push, `--no-verify` (hook skip), `--no-gpg-sign`, `git reset --hard` on shared branches, deleting branches, amending pushed commits.

## Do not commit

- `gradle.properties` (per-host; `.example` is the committed template)
- `config.sh` (per-host paths; `.example` is the committed template)
- `build/`, `runs/`, `.gradle/`, `__pycache__/`, `*.pyc`
- Anything under `.claude/` (project-local agent config)

All of these are in `.gitignore`.

---

# Technical reference

(Below: agent-facing technical depth that used to live in `DEVELOPMENT.md`. Folded in 2026-05-23 so the agent has one canonical doc to load per session. Human-facing how-to — Blender install, build commands, file layout — lives in [README.md](README.md).)

## How to build a Tier A (cube-based, GeckoLib) mob

GeckoLib 4.8.4 + Blockbench `.geo.json`. Axis-aligned cuboids, bone hierarchy, Bedrock-style animation. Used by Mowzie's Mobs, Alex's Mobs, Dragon Survival (yes — even their dragon body is cuboid GeckoLib; the smooth look is clever cube layouts + textures, not polygons).

### Tier A sub-tier — simple vs. detailed cubes

Same pipeline, different modeling discipline. Same `.geo.json` schema, same renderer, same texture-atlas approach, same Java — only the **cube count and size** change.

- **Simple cubes (~5–15 large cuboids):** vanilla-shaped mobs — Steve, pig, cow, zombie. Each body part is one big cuboid (head = 8×8×8 model units, torso = 8×12×4, leg = 4×12×4). Modeling time: minutes.
- **Detailed cubes (~30–100+ small cuboids):** Alex's Mobs / Mowzie's Mobs aesthetic. Same axis-aligned cuboids, just many small ones approximating organic shapes — a head might be 12 cubes for snout + cheeks + brow + jaw + ears + eye sockets, sized 1–3 model units each. Modeling time: hours.

Don't reach for Tier B just because the user wants more detail; well-laid detailed cubes look great and skip all the OBJ gotchas.

**Texture sizing rule of thumb:** simple cubes → 64×64 atlas. Detailed cubes → 128×128 or 256×256.

### Tier A workflow

1. **Model:** write `assets/<mod_id>/geo/entity/<name>.geo.json` in Blockbench format (cube hierarchy + bones + UVs).
2. **Texture:** generate a 64×64 (simple) or 128×128 / 256×256 (detailed) PNG atlas matching the UV plan. Use `tools/codex_image.py` for AI-generated textures, or Pillow for hand-pixel work.
3. **Animations:** write `assets/<mod_id>/animations/entity/<name>.animation.json` — idle/walk/attack keyframes.
4. **Entity class:** implement `software.bernie.geckolib.animatable.GeoEntity`; provide `AnimatableInstanceCache` + `registerControllers()`. Subclass `Monster` / `Animal` / `PathfinderMob` as appropriate.
5. **Renderer:** extend `software.bernie.geckolib.renderer.GeoEntityRenderer<T>`. Register in `MyFirstMod.ClientEvents.onRegisterRenderers`.

**Visual verification before in-game testing:** open the `.geo.json` in Blockbench (`flatpak install flathub net.blockbench.Blockbench` if you don't have it). Drag-drop the texture PNG onto the model to confirm UV alignment.

## Tier B — corelib library + limitations

`de.maxhenkel.corelib:corelib` provides `OBJEntityRenderer<T extends Entity>` — true polygonal Wavefront `.obj` meshes rendered via `VertexConsumer`. Wired up in `build.gradle` (Maven repo: `https://maven.maxhenkel.de/repository/public/`). Used in production by Henkel's `ultimate-car-mod`, `smallships`, etc.

**Limitations:**
- Wavefront `.obj` only — no glTF, no skeletal/rigged animation. Animation is whole-model transforms only (spin wheels, bob, sway), driven from the renderer's `render()` override or the per-model `RenderListener<T>`.
- Models must be triangulated (the exporter does this for you).
- Texture is referenced via `OBJModelOptions` (a `ResourceLocation`), NOT via the `.obj`'s `mtllib`/`usemtl` lines.
- OBJ goes in `assets/<mod_id>/models/entity/<name>.obj`; texture in `assets/<mod_id>/textures/entity/<name>.png`.

**Out of scope:** Pixelmon-quality skeletal-rigged glTF with bone-skinned animation. That requires BlazeRod (LGPL multi-format model lib in `TouchController/TouchController`). Its render layer targets MC 1.21.8 — would be a version bump or ~200-line port to backport to 1.21.1.

## The four critical OBJ gotchas (Tier B)

**These are baked into `tools/corelib_obj_export.py` — if you call `export_corelib_obj()` you don't have to think about them.** If you ever hand-write an OBJ outside the helper, you must address all four yourself.

1. **Face triplet required** (will crash with `ArrayIndexOutOfBoundsException: Index 2 out of bounds for length 2` on first render). corelib's `OBJModel.render` unconditionally accesses `face[N][2]` for the normal index. So **every face vertex MUST have all three components: `pos_idx/uv_idx/normal_idx`**. The compact `f a/uv b/uv c/uv` form will compile fine and crash at render time. Declare normals (`vn x y z`) and emit faces as `f a/uv/n b/uv/n c/uv/n`.
2. **UV convention — no V-flip needed.** Blender, standard OBJ, and corelib all agree: `v=0` at image bottom, `v=1` at image top. So Blender's UVs go straight into the OBJ verbatim — `corelib_obj_export.export_corelib_obj()` defaults to `v_flip=False`. The flag is an escape hatch for the rare case of UVs authored with the opposite convention; you almost never want to set it True. (Note: an earlier release defaulted `v_flip=True` based on a misread of corelib's behavior. That caused in-game textures to render mirrored vertically while Blender previews looked correct — every body-part's texture sampled the wrong region. Fixed 2026-05-20.)
3. **Triangulation.** corelib expects triangles. The helper triangulates a bmesh copy of each object before writing. If you hand-write OBJ from non-triangular Blender meshes, you'll need to triangulate manually.
4. **Face winding must be CCW outward** — otherwise the mob looks see-through in-game. Minecraft's `ENTITY_CUTOUT_TRIANGLES` render path backface-culls based on triangle winding order in screen space. If your triangles are wound clockwise outward, every visible-from-outside face gets culled and you see only the *inside surface of the opposite face* through the missing front. **Blender Cycles preview will NOT catch this** because Cycles renders both sides by default — the preview looks fine while the in-game model is hollow. The helper sanity-checks the first face after writing and raises `ValueError` if normals are flipped. If it raises: in Blender, recalculate face normals (`bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])`) before re-exporting.

## Headless Blender landmines

These bit during initial setup. Documented so future Tier B builds don't re-hit them.

1. **`bpy.context.active_object` doesn't exist in `-b` mode.** Code like `bpy.ops.mesh.primitive_cube_add(); obj = bpy.context.active_object` raises `AttributeError`. Use `bpy.context.view_layer.objects.active` instead — or better, **use the single-bmesh pattern** above, which avoids per-object `bpy.ops` calls entirely.
2. **Built-in exporters (`wm.obj_export`, `export_scene.gltf`, `wm.stl_export`) are GUI-bound and fail headless.** They poll for window state and internally call `context.window.cursor_set('WAIT')`. `bpy.context.temp_override(...)` gets past the active_object check but not the window check. **This is why `corelib_obj_export.py` exists** — a manual exporter that reads `obj.evaluated_get(depsgraph).to_mesh()` + iterates a bmesh copy. Always use it; don't try to use the built-in exporters in `-b` mode.
3. **`bpy.ops.render.render(write_still=True)` works fine in headless** — Cycles CPU renders cleanly. Just don't expect viewport screenshots to work.
4. **AMD GPU (RDNA2) needs HIP/ROCm for Cycles GPU.** If ROCm isn't installed, stick with `scn.cycles.device = 'CPU'`. CPU on a modern Ryzen is fast enough (~3.6s for 960×540 @ 32 samples).
5. **Blender preview ≠ in-game render.** Cycles renders backfaces by default, Minecraft culls them. A model with inverted winding will look fine in Blender and broken in-game. The exporter's winding check catches whole-mesh flips; for per-face flips, recalc normals before export. (Gotcha #4 above also covers this.)

## Tier B Java + JSON templates (opt-in starting points)

**Per the "Build fresh by default" rule near the top: these are OPT-IN.** Default to writing the Java/JSON from scratch; offer these templates as choice (b) in the structural-template question only if the user wants to save boilerplate-writing time. They encode default patterns (hostile-Monster goal set, ZOMBIE_AMBIENT sound, generic spawn-egg, walking-bob animation) that may not fit the asset the user described.

Placeholders: `{Name}` PascalCase, `{name}` snake_case, `{NAME_UPPER}` UPPER_SNAKE, `{display_name}` human-readable, `{mod_id}`, `{group_path}` (e.g. `com/aicreator`), `{group_path_dots}` (e.g. `com.aicreator`), `{width}` / `{height}` hitbox in blocks.

### Entity class — `src/main/java/{group_path}/{mod_id}/entity/{Name}Entity.java`

```java
package {group_path_dots}.{mod_id}.entity;

import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.RandomLookAroundGoal;
import net.minecraft.world.entity.ai.goal.WaterAvoidingRandomStrollGoal;
import net.minecraft.world.entity.ai.goal.target.HurtByTargetGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;   // or Animal for friendly
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;

public class {Name}Entity extends Monster {
    public {Name}Entity(EntityType<? extends Monster> type, Level level) { super(type, level); }
    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 16.0)
                .add(Attributes.MOVEMENT_SPEED, 0.28)
                .add(Attributes.ATTACK_DAMAGE, 3.0)
                .add(Attributes.FOLLOW_RANGE, 20.0);
    }
    @Override protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.0, true));
        this.goalSelector.addGoal(5, new WaterAvoidingRandomStrollGoal(this, 1.0));
        this.goalSelector.addGoal(6, new LookAtPlayerGoal(this, Player.class, 8.0F));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));
        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }
    @Override protected SoundEvent getAmbientSound()              { return SoundEvents.ZOMBIE_AMBIENT; }
    @Override protected SoundEvent getHurtSound(DamageSource src) { return SoundEvents.ZOMBIE_HURT; }
    @Override protected SoundEvent getDeathSound()                { return SoundEvents.ZOMBIE_DEATH; }
}
```

### Renderer — `src/main/java/{group_path}/{mod_id}/client/{Name}Renderer.java`

```java
package {group_path_dots}.{mod_id}.client;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Axis;
import {group_path_dots}.{mod_id}.MyFirstMod;
import {group_path_dots}.{mod_id}.entity.{Name}Entity;
import de.maxhenkel.corelib.client.obj.OBJEntityRenderer;
import de.maxhenkel.corelib.client.obj.OBJModel;
import de.maxhenkel.corelib.client.obj.OBJModelInstance;
import de.maxhenkel.corelib.client.obj.OBJModelOptions;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.resources.ResourceLocation;
import org.joml.Vector3d;
import java.util.List;

public class {Name}Renderer extends OBJEntityRenderer<{Name}Entity> {
    private static final ResourceLocation MODEL_LOC =
            ResourceLocation.fromNamespaceAndPath(MyFirstMod.MODID, "models/entity/{name}.obj");
    private static final ResourceLocation TEXTURE_LOC =
            ResourceLocation.fromNamespaceAndPath(MyFirstMod.MODID, "textures/entity/{name}.png");
    private final List<OBJModelInstance<{Name}Entity>> models;
    public {Name}Renderer(EntityRendererProvider.Context ctx) {
        super(ctx);
        this.shadowRadius = 0.3f;
        OBJModel objModel = new OBJModel(MODEL_LOC);
        OBJModelOptions<{Name}Entity> opts = new OBJModelOptions<>(TEXTURE_LOC, new Vector3d(0.0, 0.0, 0.0));
        this.models = List.of(new OBJModelInstance<>(objModel, opts));
    }
    @Override public List<OBJModelInstance<{Name}Entity>> getModels({Name}Entity entity) { return models; }
    @Override
    public void render({Name}Entity entity, float yaw, float partialTicks,
                       PoseStack ms, MultiBufferSource buffer, int packedLight) {
        // Optional whole-model animation. corelib doesn't do per-bone rigging,
        // so any motion lives here as PoseStack transforms. The walk-bob/sway
        // below is one example — tailor or remove for the actual mob.
        float age = entity.tickCount + partialTicks;
        float limbSwing = entity.walkAnimation.position(partialTicks);
        float limbSpeed = Math.min(entity.walkAnimation.speed(partialTicks), 1.0f);
        ms.pushPose();
        float idleBob = Math.abs((float) Math.sin(age * 0.20f)) * 0.03f;
        float walkBob = Math.abs((float) Math.sin(limbSwing * 0.6f)) * 0.06f * limbSpeed;
        ms.translate(0.0, idleBob + walkBob, 0.0);
        float walkSway = (float) Math.sin(limbSwing * 0.3f) * 4.0f * limbSpeed;
        ms.mulPose(Axis.ZP.rotationDegrees(walkSway));
        super.render(entity, yaw, partialTicks, ms, buffer, packedLight);
        ms.popPose();
    }
}
```

### `ModEntities.java` — add this entry to the existing file

```java
public static final Supplier<EntityType<{Name}Entity>> {NAME_UPPER} =
        ENTITY_TYPES.register("{name}", () -> EntityType.Builder
                .of({Name}Entity::new, MobCategory.MONSTER)
                .sized({width}, {height})
                .clientTrackingRange(8)
                .build(ResourceLocation.fromNamespaceAndPath(MyFirstMod.MODID, "{name}").toString()));
```
Plus `import {group_path_dots}.{mod_id}.entity.{Name}Entity;`

### `MyFirstMod.java` — three additions

```java
// In onAttributeCreation:
event.put(ModEntities.{NAME_UPPER}.get(), {Name}Entity.createAttributes().build());

// In onSpawnPlacementRegister (skip for spawn-egg-only mobs):
event.register(ModEntities.{NAME_UPPER}.get(),
        net.minecraft.world.entity.SpawnPlacementTypes.ON_GROUND,
        Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
        Monster::checkAnyLightMonsterSpawnRules,   // or Animal::checkAnimalSpawnRules for friendly
        RegisterSpawnPlacementsEvent.Operation.REPLACE);

// In ClientEvents.onRegisterRenderers:
event.registerEntityRenderer(ModEntities.{NAME_UPPER}.get(), {Name}Renderer::new);
```
Plus imports for `{Name}Entity` and `{Name}Renderer`.

### `ModItems.java` — spawn egg

```java
public static final DeferredItem<DeferredSpawnEggItem> {NAME_UPPER}_SPAWN_EGG =
        ITEMS.register("{name}_spawn_egg",
                () -> new DeferredSpawnEggItem(ModEntities.{NAME_UPPER},
                        0xAABBCC, 0x112233,         // primary, secondary hex RGB — match the texture
                        new Item.Properties()));
```
Add to creative tab: `output.accept(ModItems.{NAME_UPPER}_SPAWN_EGG.get());`

### `assets/{mod_id}/lang/en_us.json` — two entries

```json
"entity.{mod_id}.{name}": "{display_name}",
"item.{mod_id}.{name}_spawn_egg": "{display_name} Spawn Egg",
```

### `assets/{mod_id}/models/item/{name}_spawn_egg.json`

```json
{ "parent": "minecraft:item/template_spawn_egg" }
```

### `data/{mod_id}/loot_table/entities/{name}.json` — fill in drops

```json
{
  "type": "minecraft:entity",
  "pools": [{
    "rolls": 1.0,
    "entries": [{
      "type": "minecraft:item",
      "name": "minecraft:rotten_flesh",
      "functions": [
        { "function": "minecraft:set_count", "count": { "type": "minecraft:uniform", "min": 0.0, "max": 2.0 } }
      ]
    }]
  }]
}
```

## Generating AI textures — codex landmines + batch + parallel patterns

`tools/codex_image.py` wraps the `codex` CLI's `image_gen` tool. Free under the user's ChatGPT subscription — no API key, no per-image cost.

### Single texture: `generate()`

```python
from codex_image import generate
generate(
    prompt="A glowing emerald block face, vanilla Minecraft pixel-art style…",
    out_path="/path/to/my_block.png",
    target_size=(16, 16),   # downscales raw codex output to 16x16 nearest-neighbor for crisp pixel art
)
```

The wrapper handles all four codex CLI landmines automatically:

1. **stdin must be `/dev/null`** — codex hangs forever waiting for stdin EOF when invoked non-interactively. The wrapper uses `subprocess.run(..., stdin=subprocess.DEVNULL)`.
2. **`--ephemeral`** — without it, session state bleeds between calls (ask for a dragon, get a mouse because the previous call generated a mouse).
3. **`--json` + `thread_id` parsing** — codex emits `{"thread_id":"..."}` on stdout's first line. The wrapper parses this and reads exclusively from `~/.codex/generated_images/<thread_id>/` rather than snapshotting the parent dir (which races under concurrency — see parallel section below).
4. **Flatten multi-line prompts** — single-line invocations process reliably; multi-line sometimes truncate.

### Batch generation: `generate_sheet`

For batch workflows — "add 8 new ore blocks," "make 5 variants of this mob skin," "generate the whole mod's item icons in one pass" — prefer `generate_sheet` over N separate `generate` calls:

```python
from codex_image import generate_sheet
generate_sheet(
    regions=[
        {"name": "iron_ore",    "prompt": "stone block face with metallic iron specks scattered through gray rock"},
        {"name": "gold_ore",    "prompt": "stone block face with golden specks"},
        {"name": "diamond_ore", "prompt": "stone block face with cyan diamond facets"},
        {"name": "coal_ore",    "prompt": "stone block face with black coal flecks"},
    ],
    cell_size=(16, 16),
    out_dir="src/main/resources/assets/<mod_id>/textures/block",
)
# → writes iron_ore.png, gold_ore.png, diamond_ore.png, coal_ore.png + _sheet.png (debug)
```

**Why this beats N calls:** 1 codex call instead of N (long pole is 30–120s per call); stylistic consistency across all cells (codex paints them in one composition so palette/lighting/scale match); 1× quota usage.

**How it works:** auto-picks a square grid that holds all N regions, renders each cell at `cell_size × upscale` (default 4×), slices with NEAREST downsample to `cell_size`. Cells are separated by `gap_px` solid-black gridlines (default 2px) — gives codex a strong visual cue to respect cell boundaries. Intermediate sheet saved to `out_dir/_sheet.png` for slicing debug.

**When NOT to use it:**
- Single-texture workflows (one mob skin, one block) — use `generate` instead.
- More than ~16 regions in one sheet — each cell gets less codex attention and detail mushes. Split into multiple sheet calls.
- Cells with very different style needs (e.g., a realistic 256×256 portrait next to a 16×16 pixel-art icon). Group same-style cells per sheet.

**Quality caveat:** codex doesn't always perfectly respect the grid. Check `_sheet.png` after a run — if a cell ignored the gridlines or bled across, re-roll or fall back to per-region `generate` for that one piece.

### Parallel codex calls (independent textures)

Parallel codex calls work and are ~25% faster than sequential at N=2, scale cleanly to N=4. The `~/.codex/generated_images/` dir is shared across concurrent calls, but the `--json` + `thread_id` approach in `codex_image.py` sidesteps the race because each call's output lives at `~/.codex/generated_images/<thread_id>/` exclusively.

To generate N textures in parallel from Python: `concurrent.futures.ThreadPoolExecutor(max_workers=4)` over `codex_image.generate(...)` calls. Each call is fully self-contained, the wrapper does the right thing.

**Sweet spot: N ≤ 4.** Beyond that, variance in per-call duration (image_gen is bursty by nature — 17–55 seconds per call regardless of concurrency) eats the wall-clock benefit. For a single texture, sequential is fine and simpler. Subscription quota isn't exposed via the CLI; if you hit silent throttling, check `chat.openai.com` in the user's browser.

### Pillow (Python, hand-coded) — fallback

Use when:
- You need exact pixel control (palette textures, UV-aligned skins, known-shape icons).
- The user explicitly asked for "pixel-by-pixel" / "paint it myself with Python."
- AI output doesn't render correctly and you need a deterministic fallback.
- The icon is ≤32×32 pixel art (codex's value-add at that size is low; Pillow gives crisp pixel boundaries + real transparency).

Rule of thumb: **AI for blocks, items, weapons, armor, and Tier B entity textures.** **Pillow for Tier A entity skins** (vanilla cube UV layout) and exact palette swatches.

## Project conventions (quick reference)

- **Mod loader:** NeoForge 1.21.1 (NOT Fabric, NOT legacy Forge).
- **Java:** JDK 21 (Mojang's runtime since 1.20.5).
- **Mappings:** Parchment (human-readable parameter names).
- **Mod ID:** defaults to `aitemplate`; rename via `scripts/rename_mod.sh` or `scripts/setup.sh`.
- **Base package:** `com.aicreator.aitemplate` by default; renamed by the same script.
- **Registry pattern:** `DeferredRegister` for items, blocks, entities, creative tabs.
- **Structure:** official NeoForge MDK layout.
