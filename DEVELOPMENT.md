# Development guide

Everything you need to know to actually build mobs and blocks with this scaffold. The public-facing intro is in [README.md](README.md); this doc is the reference manual.

## Project conventions

- **Mod loader:** NeoForge 1.21.1 (NOT Fabric, NOT legacy Forge).
- **Java:** JDK 21 (Mojang's runtime since 1.20.5).
- **Mappings:** Parchment (human-readable parameter names).
- **Mod ID:** defaults to `aitemplate`; rename via `scripts/rename_mod.sh` or `scripts/setup.sh`.
- **Base package:** `com.aicreator.aitemplate` by default; renamed by the same script.
- **Registry pattern:** `DeferredRegister` for items, blocks, entities, creative tabs.
- **Structure:** official NeoForge MDK layout.

## Entity rendering tiers

This is the most important decision when adding a new mob. There are two workable in-scope approaches; pick the one that matches the look you want.

### Decision rubric

- **"Like a Minecraft mob" + animatable limbs (walks, attacks, sits)** → Tier A (GeckoLib).
  - "Big blocks, vanilla-shaped" → Tier A simple.
  - "Lots of small blocks, more detail, still blocky" → Tier A detailed (Alex's Mobs style).
- **Unusual shape — tilted parts / curves / non-axis-aligned geometry / sculpted mesh — but moves as one piece** → Tier B (corelib polygonal OBJ).
- **Pixelmon-quality skeletal-rigged glTF with bone-skinned animation** → none of the above are sufficient. You'd need BlazeRod (LGPL multi-format model lib in `TouchController/TouchController`). Its render layer targets MC 1.21.8, so that's either a version bump or a ~200-line port. Not in scope.

If the user's request is ambiguous (e.g. "low poly" can mean either chunky-cubes or PSX-style polygonal), ask which they mean — same phrase, two different aesthetics.

### Tier A — cube-based (GeckoLib)

GeckoLib 4.8.4 + Blockbench `.geo.json`. Axis-aligned cuboids, bone hierarchy, Bedrock-style animation. Used by Mowzie's Mobs, Alex's Mobs, Dragon Survival (yes — even their dragon body is cuboid GeckoLib; the smooth look is clever cube layouts + textures, not polygons).

#### Tier A sub-tier — simple vs. detailed cubes

Same pipeline, different modeling discipline. Same `.geo.json` schema, same renderer, same texture atlas approach, same Java — only the **cube count and size** change.

- **Simple cubes (~5–15 large cuboids):** vanilla-shaped mobs — Steve, pig, cow, zombie. Each body part is one big cuboid (head = 8×8×8 model units, torso = 8×12×4, leg = 4×12×4). Modeling time: minutes.
- **Detailed cubes (~30–100+ small cuboids):** Alex's Mobs / Mowzie's Mobs aesthetic. Same axis-aligned cuboids, just many small ones approximating organic shapes — a head might be 12 cubes for snout + cheeks + brow + jaw + ears + eye sockets, sized 1–3 model units each. Modeling time: hours.

Don't reach for Tier B just because the user wants more detail; well-laid detailed cubes look great and skip all the OBJ gotchas.

**Texture sizing rule of thumb:** simple cubes → 64×64 atlas. Detailed cubes → 128×128 or 256×256.

#### Tier A workflow

1. **Model:** write `assets/<mod_id>/geo/entity/<name>.geo.json` in Blockbench format (cube hierarchy + bones + UVs).
2. **Texture:** generate a 64×64 (simple) or 128×128 / 256×256 (detailed) PNG atlas matching the UV plan. Use `tools/codex_image.py` for AI-generated textures, or Pillow for hand-pixel work.
3. **Animations:** write `assets/<mod_id>/animations/entity/<name>.animation.json` — idle/walk/attack keyframes.
4. **Entity class:** implement `software.bernie.geckolib.animatable.GeoEntity`; provide `AnimatableInstanceCache` + `registerControllers()`. Subclass Monster/Animal/PathfinderMob as appropriate.
5. **Renderer:** extend `software.bernie.geckolib.renderer.GeoEntityRenderer<T>`. Register in `MyFirstMod.ClientEvents.onRegisterRenderers`.

**Visual verification before in-game testing:** open the `.geo.json` in Blockbench (`flatpak install flathub net.blockbench.Blockbench` if you don't have it). Drag-drop the texture PNG onto the model to confirm UV alignment.

### Tier B — polygonal (henkelmax/corelib)

`de.maxhenkel.corelib:corelib` provides `OBJEntityRenderer<T extends Entity>` — true polygonal Wavefront `.obj` meshes rendered via `VertexConsumer`. Wired up in `build.gradle` (Maven repo: `https://maven.maxhenkel.de/repository/public/`). Used in production by Henkel's `ultimate-car-mod`, `smallships`, etc.

**Limitations:**
- Wavefront `.obj` only — no glTF, no skeletal/rigged animation. Animation is whole-model transforms only (spin wheels, bob, sway), driven from the renderer's `render()` override or the per-model `RenderListener<T>`.
- Models must be triangulated (the exporter does this for you).
- Texture is referenced via `OBJModelOptions` (a `ResourceLocation`), NOT via the `.obj`'s `mtllib`/`usemtl` lines.
- OBJ goes in `assets/<mod_id>/models/entity/<name>.obj`; texture in `assets/<mod_id>/textures/entity/<name>.png`.

#### Tier B workflow — direct Blender MCP

You drive Blender directly via the `mcp__blender__execute_blender_code` tool. There are no per-mob driver scripts, no PARTS list, no cube-only constraints. Build whatever Blender can express, export via `corelib_obj_export.export_corelib_obj(path=...)`, render previews in the same call, show the user, then write Java.

The canonical example (build → export → render) is in [CLAUDE.md](CLAUDE.md) under "How to build a Tier B (polygonal) mob — direct Blender MCP flow." That section is the authoritative template; copy from there for each new Tier B mob.

High-level steps:
1. Confirm the Blender MCP socket is reachable (`mcp__blender__get_scene_info`). If not, start `scripts/blender_mcp_start_headless.sh` in the background.
2. In one `execute_blender_code` call:
   - Wipe the scene.
   - Build parts with `bpy.ops.mesh.primitive_cube_add` / `_uv_sphere_add` / `_cylinder_add` / `_cone_add`, or with `bmesh` for custom topology. Apply rotations and scales as you go.
   - Assign UVs (per-face, per-loop) — flat-color palette, structured atlas, or full unwrap, your call.
   - `from corelib_obj_export import export_corelib_obj; export_corelib_obj(path='<repo>/src/main/resources/assets/<mod_id>/models/entity/<name>.obj')`.
   - Set up a camera + sun + material, render 3 angles (front, three-quarter, close-face) to JPG, write to `$PREVIEW_OUTPUT_DIR` or `~/Desktop`.
3. Self-eval the JPGs (Gate 1 — see checklist below). Fix any technical issues, re-export, re-render.
4. **Pause** and show the user the JPG paths (Gate 2 — REQUIRED). Wait for approval before writing Java.
5. Write the entity class (`extends Animal` / `Monster` / `PathfinderMob`), the renderer (`extends OBJEntityRenderer<YourEntity>` with `getModels(entity)`), register attributes + spawn placement + renderer in `MyFirstMod.java`, add a spawn-egg item, lang entry, creative-tab entry, loot table.

#### The four critical OBJ gotchas

**These are baked into `tools/corelib_obj_export.py` — if you call `export_corelib_obj()` you don't have to think about them.** If you ever hand-write an OBJ outside the helper, you must address all four yourself.

1. **Face triplet required (will crash with `ArrayIndexOutOfBoundsException: Index 2 out of bounds for length 2` on first render).** corelib's `OBJModel.render` unconditionally accesses `face[N][2]` for the normal index. So **every face vertex MUST have all three components: `pos_idx/uv_idx/normal_idx`**. The compact `f a/uv b/uv c/uv` form will compile fine and crash at render time. Declare normals (`vn x y z`) and emit faces as `f a/uv/n b/uv/n c/uv/n`.

2. **UV convention — no V-flip needed.** Blender, standard OBJ, and corelib all agree: `v=0` at image bottom, `v=1` at image top. So Blender's UVs go straight into the OBJ verbatim — `corelib_obj_export.export_corelib_obj()` defaults to `v_flip=False`. The flag is an escape hatch for the rare case of UVs authored with the opposite convention; you almost never want to set it True. (Note: an earlier release defaulted `v_flip=True` based on a misread of corelib's behavior. That caused in-game textures to render mirrored vertically while Blender previews looked correct — every body-part's texture sampled the wrong region. Fixed 2026-05-20.)

3. **Triangulation.** corelib expects triangles. The helper triangulates a bmesh copy of each object before writing. If you hand-write OBJ from non-triangular Blender meshes, you'll need to triangulate manually.

4. **Face winding must be CCW outward — otherwise the mob looks see-through in-game.** Minecraft's `ENTITY_CUTOUT_TRIANGLES` render path backface-culls based on triangle winding order in screen space. If your triangles are wound clockwise outward, every visible-from-outside face gets culled and you see only the *inside surface of the opposite face* through the missing front. **Blender Cycles preview will NOT catch this** because Cycles renders both sides by default — the preview looks fine while the in-game model is hollow. The helper sanity-checks the first face after writing and raises `ValueError` if normals are flipped. If it raises: in Blender, recalculate face normals (`bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])`) before re-exporting.

#### Tier B mob — Java + JSON templates (starting points, NOT constraints)

These are **skeletons, not requirements** — paste them in, change anything that doesn't fit the mob the user described. The walk-bob / sway / attack values / hitbox size / sound choices / parent class (`Monster` vs `Animal`) / goal set / damage / behavior are all knobs, not contracts. Adapt freely. The templates exist only to save you from re-deriving the structural shape of an `OBJEntityRenderer`-rendered NeoForge mob; they take no position on what the mob *is*.

The scaffold ships with no example mobs in `src/` — these templates are the canonical reference. If a prior session has built a mob and the file exists, **do not** open its `.obj` / `.geo.json` / Java for "style cues"; each new mob is built fresh from the user's clarifying answers (or saved preferences in `.claude/mob_preferences.md`).

Placeholders to find/replace:
- `{Name}` — PascalCase (e.g. `FrogWarrior`)
- `{name}` — snake_case (e.g. `frog_warrior`)
- `{NAME_UPPER}` — UPPER_SNAKE (e.g. `FROG_WARRIOR`)
- `{display_name}` — human-readable (e.g. `Frog Warrior`)
- `{mod_id}` — your mod_id from gradle.properties (e.g. `aitemplate`)
- `{group_path}` — your `mod_group_id` with dots → slashes (e.g. `com/aicreator`)
- `{width}` / `{height}` — entity hitbox in blocks (humanoid mob defaults: `0.6F` / `1.95F`; scale down for smaller mobs, scale up for big ones)

##### 1. Entity class — `src/main/java/{group_path}/{mod_id}/entity/{Name}Entity.java`

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

    public {Name}Entity(EntityType<? extends Monster> type, Level level) {
        super(type, level);
    }

    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
                .add(Attributes.MAX_HEALTH, 16.0)
                .add(Attributes.MOVEMENT_SPEED, 0.28)
                .add(Attributes.ATTACK_DAMAGE, 3.0)
                .add(Attributes.FOLLOW_RANGE, 20.0);
    }

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(2, new MeleeAttackGoal(this, 1.0, true));
        this.goalSelector.addGoal(5, new WaterAvoidingRandomStrollGoal(this, 1.0));
        this.goalSelector.addGoal(6, new LookAtPlayerGoal(this, Player.class, 8.0F));
        this.goalSelector.addGoal(7, new RandomLookAroundGoal(this));

        this.targetSelector.addGoal(1, new HurtByTargetGoal(this));
        this.targetSelector.addGoal(2, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    // ADD SPECIAL BEHAVIOR HERE if the user asked for it (aura effects, on-death
    // particles, hop intervals, etc.). Keep it tight — only what was requested.

    @Override protected SoundEvent getAmbientSound()         { return SoundEvents.ZOMBIE_AMBIENT; }
    @Override protected SoundEvent getHurtSound(DamageSource src) { return SoundEvents.ZOMBIE_HURT; }
    @Override protected SoundEvent getDeathSound()           { return SoundEvents.ZOMBIE_DEATH; }
}
```

##### 2. Renderer — `src/main/java/{group_path}/{mod_id}/client/{Name}Renderer.java`

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
        OBJModelOptions<{Name}Entity> opts =
                new OBJModelOptions<>(TEXTURE_LOC, new Vector3d(0.0, 0.0, 0.0));
        this.models = List.of(new OBJModelInstance<>(objModel, opts));
    }

    @Override
    public List<OBJModelInstance<{Name}Entity>> getModels({Name}Entity entity) {
        return models;
    }

    /**
     * Optional whole-model animation. corelib doesn't do per-bone rigging, so
     * any "animation" lives in this render() override as PoseStack transforms.
     *
     * The bob/sway below is ONE example pattern — useful for many mobs but
     * not mandatory. Other patterns: idle tilt (mulPose ZP), head-tracking
     * lean toward target, spin (mulPose YP) for floating mobs, jump-arc lift
     * tied to deltaMovement.y, attack-windup tilt during MeleeAttackGoal,
     * recoil shake on hurtTime > 0. Match the motion to the mob's personality
     * or skip animation entirely (just call super.render and return) — a
     * static mesh is a fine default for many mobs.
     */
    @Override
    public void render({Name}Entity entity, float yaw, float partialTicks,
                       PoseStack ms, MultiBufferSource buffer, int packedLight) {
        float age = entity.tickCount + partialTicks;
        float limbSwing = entity.walkAnimation.position(partialTicks);
        float limbSpeed = Math.min(entity.walkAnimation.speed(partialTicks), 1.0f);

        ms.pushPose();

        // Vertical bob: idle breath + walk bounce
        float idleBob = Math.abs((float) Math.sin(age * 0.20f)) * 0.03f;
        float walkBob = Math.abs((float) Math.sin(limbSwing * 0.6f)) * 0.06f * limbSpeed;
        ms.translate(0.0, idleBob + walkBob, 0.0);

        // Side sway when walking
        float walkSway = (float) Math.sin(limbSwing * 0.3f) * 4.0f * limbSpeed;
        ms.mulPose(Axis.ZP.rotationDegrees(walkSway));

        super.render(entity, yaw, partialTicks, ms, buffer, packedLight);
        ms.popPose();
    }
}
```

##### 3. `ModEntities.java` — add this entry to the existing file

```java
public static final Supplier<EntityType<{Name}Entity>> {NAME_UPPER} =
        ENTITY_TYPES.register("{name}", () -> EntityType.Builder
                .of({Name}Entity::new, MobCategory.MONSTER)
                .sized({width}, {height})
                .clientTrackingRange(8)
                .build(ResourceLocation.fromNamespaceAndPath(MyFirstMod.MODID, "{name}").toString())
        );
```

Add the import: `import {group_path_dots}.{mod_id}.entity.{Name}Entity;`

##### 4. `MyFirstMod.java` — three additions to the existing file

```java
// In onAttributeCreation:
event.put(ModEntities.{NAME_UPPER}.get(), {Name}Entity.createAttributes().build());

// In onSpawnPlacementRegister:
event.register(ModEntities.{NAME_UPPER}.get(),
        net.minecraft.world.entity.SpawnPlacementTypes.ON_GROUND,
        Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
        Monster::checkAnyLightMonsterSpawnRules,   // or Animal::checkAnimalSpawnRules for friendly
        RegisterSpawnPlacementsEvent.Operation.REPLACE);

// In ClientEvents.onRegisterRenderers:
event.registerEntityRenderer(ModEntities.{NAME_UPPER}.get(), {Name}Renderer::new);
```

Add imports: `import {group_path_dots}.{mod_id}.entity.{Name}Entity;` and `import {group_path_dots}.{mod_id}.client.{Name}Renderer;`

##### 5. `ModItems.java` — spawn egg

```java
public static final DeferredItem<Item> {NAME_UPPER}_SPAWN_EGG =
        ITEMS.registerItem("{name}_spawn_egg",
                props -> new DeferredSpawnEggItem(ModEntities.{NAME_UPPER}, 0xAABBCC, 0x112233, props));
                                                              // primary color, secondary color (hex RGB)
```

Pick colors that match the texture. Add to creative tab in `ModCreativeTab.java`:

```java
output.accept(ModItems.{NAME_UPPER}_SPAWN_EGG.get());
```

##### 6. `assets/{mod_id}/lang/en_us.json` — add two entries

```json
"entity.{mod_id}.{name}": "{display_name}",
"item.{mod_id}.{name}_spawn_egg": "{display_name} Spawn Egg",
```

##### 7. `assets/{mod_id}/models/item/{name}_spawn_egg.json`

```json
{
  "parent": "minecraft:item/template_spawn_egg"
}
```

##### 8. `data/{mod_id}/loot_table/entities/{name}.json` — fill in drops

```json
{
  "type": "minecraft:entity",
  "pools": [
    {
      "rolls": 1.0,
      "entries": [
        {
          "type": "minecraft:item",
          "name": "minecraft:rotten_flesh",
          "functions": [
            { "function": "minecraft:set_count", "count": { "type": "minecraft:uniform", "min": 0.0, "max": 2.0 } }
          ]
        }
      ]
    }
  ]
}
```

#### Tier B preview-eval checklist (Gate 1 — your self-eval before showing the user)

When to do it:
- New polymesh mob → yes
- Repositioning parts → yes
- Adding new features (eyes, accessories) → yes
- Color/palette only → skip (Blender sRGB vs in-game lighting differ — tune in game)
- Animation/renderer code only → skip (preview is static)

Six angles to render (Cycles 32 samples CPU, ~2s each, ~12–15s total — the canonical template in CLAUDE.md renders all six and tiles them with ImageMagick into a single `<name>_preview_grid.jpg` for review):
1. **Front, eye level** — symmetry, face features visible, no missing pieces.
2. **90° side** — silhouette read, depth proportions, hat/weapon/accessory extent in profile.
3. **180° behind** — back-of-head detail, ponytail/cape/spine seam, anything that was hidden in the front view.
4. **Three-quarter** — gaps between parts show clearly at this angle.
5. **Close-up of face/head** — eyes/mouth/details actually ON the head, not embedded behind it.
6. **Top-down (map view)** — overall footprint vs. the entity's `sized(width, depth)` hitbox, foot placement, hat brim extent.

**Always read the grid composite first, not the individuals.** One image read instead of six saves significant image tokens, and the grid is dense enough to surface every common issue. Open an individual full-res JPG only if the grid reveals something you need to inspect closer.

Read-off questions before showing the user:
- **Connection-graph walk:** for every adjacent pair the user would expect to touch (head↔neck, neck↔torso, shoulder↔upper arm, elbow↔forearm, wrist↔hand, hip↔thigh, knee↔calf, ankle↔foot, plus any accessories↔body), is there visible empty space between them on the three-quarter and side renders? **Disconnected parts are the #1 recurring Tier B failure** — the agent's eye misses gaps the user catches instantly. If any pair has a gap, the parent part needs to extend further OR the child needs to be repositioned to overlap by at least a few pixels. Re-render.
- **Flat-color parts (Q1b = Detailed or Maximum only):** any part rendered as a uniform solid color while the rest of the mesh has visible texture detail means that part's UVs got collapsed to one pixel. Fix the UV layer for that object so it spans a content-bearing atlas region. Re-export, re-render.
- Is each named feature (eyes, mouth, mustache, buckle…) visible from at least one angle?
- Does it read as the intended thing without context?
- Are the proportions natural, or robotic-blocky? (If the user asked for "less rigid" — are parts actually tilted, asymmetric, organic-feeling?)

**Cycles silently hides winding bugs.** Trust the helper's winding check — if it doesn't raise, you're fine on that front.

## Texture generation

Two patterns. **Default to codex `image_gen` for most textures** — it produces vanilla-style 16×16s and patterned atlases consistently. Hand-coded Pillow is the fallback when you need exact pixel control or codex output doesn't fit.

### Codex `image_gen` via `tools/codex_image.py` (default)

Free under the user's ChatGPT subscription — no API key, no per-image cost. Wrapped by `tools/codex_image.py`:

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
3. **`--json` + `thread_id` parsing** — codex emits `{"thread_id":"..."}` on stdout's first line. The wrapper parses this and reads exclusively from `~/.codex/generated_images/<thread_id>/` rather than snapshotting the parent dir (which races under concurrency — see below).
4. **Flatten multi-line prompts** — single-line invocations process reliably; multi-line sometimes truncate.

### Batch generation: one sheet sliced into N textures (`generate_sheet`)

For batch workflows — "add 8 new ore blocks," "make 5 variants of this mob skin," "generate the whole mod's item icons in one pass" — prefer **`generate_sheet`** over N separate `generate` calls.

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

**Why this is faster + better:**
- **1 codex call instead of N.** codex is the long pole at 30–120s per call; one wait covers the whole batch.
- **Stylistic consistency for free.** codex paints all cells in one composition, so palette / lighting / scale / pixel-art conventions all match. Independent calls drift in style across pieces.
- **Lower codex quota usage.** One call = one charge.

**How it works:**
- Auto-picks a square grid that holds all N regions (extra slots get "leave blank" placeholders). Override with `grid=(rows, cols)`.
- Each cell is rendered at `cell_size × upscale` in the intermediate sheet (default 4× → 16×16 cells become 64×64 in the sheet), then NEAREST-downsampled to `cell_size` after slicing for crisp pixel-art output.
- Cells are separated by `gap_px` solid-black gridlines (default 2px) — gives codex a strong visual cue to respect cell boundaries.
- The intermediate sheet is saved to `out_dir/_sheet.png` for slicing debug; delete if not needed.

**When NOT to use it:**
- Single-texture workflows (one mob skin, one block) — use `generate` instead. The single-mob atlas case is already one codex call internally.
- More than ~16 regions in one sheet — each cell gets less codex attention and detail mushes. Split into multiple sheet calls.
- Cells with very different style needs (e.g., a realistic 256×256 portrait next to a 16×16 pixel-art icon). Group same-style cells per sheet.

**Quality caveats:**
- Codex doesn't always perfectly respect the grid. Check `_sheet.png` after a run — if a cell ignored the gridlines or bled across, re-roll or fall back to per-region `generate` for that one piece.
- Non-square user-specified grids (e.g. 1×4 strip) work but the codex output (square) is center-cropped to target aspect first, so some source pixels are discarded. Square-ish grids waste less.

### Parallelizing AI texture generation safely

**Parallel codex calls work and are ~25% faster than sequential at N=2, and scale cleanly to at least N=4.** Verified in production. The trick is that `~/.codex/generated_images/` is shared across concurrent calls — if two workers both snapshot the dir before their calls and diff after, they each see *both* generated images and might claim each other's output. The `--json` + `thread_id` approach (already baked into `codex_image.py`) sidesteps this because each call's output lives at `~/.codex/generated_images/<thread_id>/` exclusively, no matter how many workers run concurrently.

To generate N textures in parallel from Python, run multiple `codex_image.generate(...)` calls under `concurrent.futures.ThreadPoolExecutor(max_workers=4)`. Each call is fully self-contained and the wrapper does the right thing.

Practical guidance:
- **N ≤ 4** is the sweet spot. Beyond that you'll start hitting variance in per-call duration (image_gen is bursty by nature — 17–55 seconds per call regardless of concurrency) without much wall-clock benefit.
- For a single texture, sequential is fine and simpler.
- Per-call duration is unpredictable, not caused by concurrency — sequential calls show the same spread.

Subscription quota isn't exposed via the CLI; if you hit silent throttling, check `chat.openai.com` in the user's browser.

### Pillow (Python, hand-coded) — fallback

Use this when:
- You need exact pixel control (palette textures, UV-aligned skins, known-shape icons).
- The user explicitly asked for "pixel-by-pixel" / "paint it myself with Python."
- AI output doesn't render correctly and you need a deterministic fallback.

**For Tier A mob skins specifically** (cube model entities with 64×64 UV-mapped textures in vanilla Steve layout), Pillow is the better default — `image_gen` doesn't respect the strict 8×8 UV cell boundaries that vanilla skins require. Hand-pixel them into the layout. (Documented in the user's `feedback_minecraft_skins.md` memory.)

Rule of thumb: **AI for blocks, items, weapons, armor, and Tier B entity textures** (patterned material swatches, palette atlases, even full unwraps when you want a painterly look). **Pillow for Tier A entity skins** (vanilla cube UV layout) and exact palette swatches.

## Headless Blender + BlenderMCP (Tier B only)

The Tier B build pipeline requires a running headless Blender exposing the BlenderMCP socket on TCP 9876.

### One-time host setup

```sh
scripts/install_blender_mcp.sh           # interactive — installs Blender, addon, launcher, registers MCP, symlinks corelib_obj_export
scripts/install_blender_mcp.sh --check   # report what's installed, change nothing
```

This installs:
- Blender 5.x at `/opt/blender/`, symlinked to `/usr/local/bin/blender` (apt's is too old; snap is disabled on Mint).
- The patched BlenderMCP addon from `shrimpwagon/blender-mcp` (branch `headless-bg-mode-timer-fix`, upstream PR #252) at `~/.config/blender/<version>/scripts/addons/blender_mcp.py`.
- `uv` (if missing) — needed for `uvx blender-mcp`.
- **Symlinks `tools/corelib_obj_export.py` into `~/.config/blender/<version>/scripts/modules/`** so any Blender Python script can `from corelib_obj_export import export_corelib_obj` without sys.path fiddling.
- (Already checked-in) the project-local launcher at `scripts/blender_mcp_start_headless.{sh,py}`. No per-host copy — the installer just verifies it's present and executable.
- The MCP server registered with Claude Code at user scope (`uvx blender-mcp` with `DISABLE_TELEMETRY=true`).

### Running the server

```sh
nohup scripts/blender_mcp_start_headless.sh > /tmp/blender-mcp.log 2>&1 &     # background
ss -tlnp | grep 9876                                                            # verify
pkill -f "blender -b --python.*blender_mcp_start_headless"                      # stop
```

### Why a patched fork

Upstream `ahujasid/blender-mcp` dispatches commands via `bpy.app.timers.register()`, which **never fires in `blender -b` mode** because there's no event loop running when the `--python` script blocks the main thread. Every MCP command hangs forever. The patched fork runs `_server_loop()` and `_handle_client()` inline on the main thread when `bpy.app.background` is True, bypassing the timer indirection. If upstream merges PR #252 you can switch back to upstream; check with `gh pr view 252 --repo ahujasid/blender-mcp --json state` before assuming the patch is still needed.

### Headless Blender landmines

These bit during initial setup. Documented here so future development doesn't hit them again.

1. **`bpy.context.active_object` doesn't exist in `-b` mode.** Code like `bpy.ops.mesh.primitive_cube_add(); obj = bpy.context.active_object` raises `AttributeError`. Use `bpy.data.objects[-1]` (the most-recently-added object) or `bpy.context.view_layer.objects.active` instead. The CLAUDE.md canonical example uses `bpy.data.objects[-1]`.
2. **Built-in exporters (`wm.obj_export`, `export_scene.gltf`, `wm.stl_export`) are GUI-bound and fail headless.** They poll for window state and internally call `context.window.cursor_set('WAIT')`. `bpy.context.temp_override(...)` gets past the active_object check but not the window check. **This is why `corelib_obj_export.py` exists** — a manual exporter that reads `obj.evaluated_get(depsgraph).to_mesh()` + iterates a bmesh copy.
3. **`bpy.ops.render.render(write_still=True)` works fine in headless** — Cycles CPU renders cleanly. Just don't expect viewport screenshots to work.
4. **AMD GPU (RDNA2) needs HIP/ROCm for Cycles GPU.** If ROCm isn't installed, stick with `scn.cycles.device = 'CPU'`. CPU on a modern Ryzen is fast enough (~3.6s for 960×540 @ 32 samples).
5. **Blender preview ≠ in-game render.** Specifically: Cycles renders backfaces by default, Minecraft culls them. A model with inverted winding will look fine in Blender and broken in-game. The exporter's winding check catches whole-mesh flips; for per-face flips, recalc normals before export.

## Build & deploy

```sh
source config.sh                     # exports MULTIMC_MODS_DIR + PREVIEW_OUTPUT_DIR
./gradlew build                      # produces build/libs/<mod_id>-<version>.jar
cp build/libs/*.jar "$MULTIMC_MODS_DIR"
```

You also need GeckoLib + corelib runtime jars in your MultiMC mods folder. Both are declared as Maven deps for the build, but they're runtime mods — your instance needs them present. The `scripts/setup.sh` script offers to download and install them automatically.

## File layout cheat-sheet

```
.
├── README.md, DEVELOPMENT.md, CLAUDE.md, LICENSE
├── build.gradle, settings.gradle, gradle.properties.example, config.example.sh
├── gradle/, gradlew, gradlew.bat                  # gradle wrapper
├── src/main/java/com/<group>/<mod_id>/            # Java source
│   ├── entity/                                    # mob entity classes
│   ├── block/                                     # block classes
│   ├── client/                                    # model + renderer classes
│   ├── ModEntities.java, ModItems.java, ModBlocks.java, ModCreativeTab.java
│   └── MyFirstMod.java                            # mod entry point
├── src/main/resources/
│   ├── META-INF/neoforge.mods.toml
│   ├── assets/<mod_id>/
│   │   ├── animations/entity/<name>.animation.json
│   │   ├── geo/entity/<name>.geo.json             # Tier A
│   │   ├── models/entity/<name>.obj               # Tier B
│   │   ├── models/{block,item}/*.json
│   │   ├── textures/{block,item,entity}/*.png
│   │   ├── blockstates/*.json
│   │   └── lang/en_us.json
│   └── data/<mod_id>/
│       └── loot_table/{blocks,entities}/*.json
├── tools/
│   ├── codex_image.py                             # AI texture generator (codex image_gen wrapper)
│   └── corelib_obj_export.py                      # Blender-Python module: format-only OBJ exporter (symlinked into Blender's modules dir by the installer)
└── scripts/
    ├── setup.sh                                   # one-shot first-time setup
    ├── rename_mod.sh                              # rename mod_id throughout source
    ├── install_blender_mcp.sh                     # one-time Blender MCP host setup (includes corelib_obj_export symlink)
    └── blender_mcp_start_headless.{sh,py}         # checked-in Blender server launcher; install_blender_mcp.sh just verifies presence
```
