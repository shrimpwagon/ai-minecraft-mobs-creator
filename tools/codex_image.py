#!/usr/bin/env python3
"""Python wrapper around the codex CLI's image_gen tool.

Bakes in the four landmines from the codex-image-generation guide so callers
don't have to re-discover them:

  1. stdin must be /dev/null — otherwise codex hangs forever waiting for EOF
     when invoked non-interactively. (subprocess.run with stdin=DEVNULL.)
  2. --ephemeral — without it, session state bleeds between calls and you
     ask for a "dragon" and get a "mouse" because the previous call generated
     a mouse.
  3. --json — emits {"thread_id":"..."} on the first stdout line, so we know
     exactly which subdirectory under ~/.codex/generated_images/ holds this
     call's output. (Snapshot-diff races under concurrency; thread_id doesn't.)
  4. Multi-line prompts can be partially-processed — flatten to one line.

Two public entry points:

  generate(prompt, out_path, target_size, ...)
    One codex call → one image. Default for single textures (mob skin,
    one block face, one item icon).

  generate_sheet(regions, cell_size, grid, out_dir, ...)
    ONE codex call → ONE patchwork sheet → sliced into per-region PNGs.
    Use this for BATCHES (multi-block, multi-item, mob variants). Wins:
      - 1 wait instead of N (codex is the long pole at 30–120s per call).
      - Stylistic consistency across cells for free — codex paints them
        all in one composition so palette / lighting / scale all match.
      - Lower codex quota usage.
    Cost: less control over individual cells, occasional slicing misalign
    if codex ignores the requested grid. Mitigated by upscale + gap pixels.

Usage:
    from codex_image import generate, generate_sheet
    generate(prompt="A glowing emerald block face...", out_path="...png", target_size=(16,16))
    generate_sheet(
        regions=[
            {"name": "iron_ore",    "prompt": "stone block face with metallic iron specks"},
            {"name": "gold_ore",    "prompt": "stone block face with golden specks"},
            {"name": "diamond_ore", "prompt": "stone block face with cyan diamond facets"},
            {"name": "coal_ore",    "prompt": "stone block face with black coal flecks"},
        ],
        cell_size=(16, 16),
        out_dir="src/main/resources/assets/aitemplate/textures/block",
    )
"""

import math
import os
import re
import shutil
import subprocess
from pathlib import Path


def _run_codex(full_prompt: str, timeout: int = 360) -> Path:
    """Internal: invoke codex image_gen with a complete prompt; return the raw PNG path.

    Callers own the prompt entirely — including the leading "Call image_gen once: …"
    instruction and any trailing "Reply DONE." — so they can tune aspect, style,
    or composition for their use case.
    """
    one_line = re.sub(r'\s+', ' ', full_prompt).strip()
    args = [
        'codex', 'exec',
        '--skip-git-repo-check',
        '--dangerously-bypass-approvals-and-sandbox',
        '--ephemeral',
        '--json',
        '--cd', '/tmp',
        one_line,
    ]

    # stdin=DEVNULL is THE critical fix — non-interactive codex hangs otherwise.
    proc = subprocess.run(
        args, stdin=subprocess.DEVNULL,
        capture_output=True, text=True, timeout=timeout,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"codex exit {proc.returncode}: {proc.stderr[-500:].strip()}"
        )

    m = re.search(r'"thread_id":"([^"]+)"', proc.stdout)
    if not m:
        raise RuntimeError(
            f"no thread_id in codex stdout (first 500 chars): {proc.stdout[:500]}"
        )
    thread_id = m.group(1)

    gen_dir = Path.home() / ".codex" / "generated_images" / thread_id
    pngs = sorted(gen_dir.glob("ig_*.png"))
    if len(pngs) != 1:
        raise RuntimeError(
            f"expected 1 image in {gen_dir}, got {len(pngs)}"
        )
    return pngs[0]


def generate(prompt: str, out_path: str, target_size=None, timeout: int = 360):
    """Generate one image via codex image_gen.

    prompt: natural-language prompt (will be flattened to one line internally).
    out_path: absolute path to write the final PNG.
    target_size: optional (w, h). If given, the raw image is center-cropped to
        square then resized with Pillow NEAREST for crisp pixel-art look.
    timeout: max seconds to wait for codex (default 6 min; image_gen is bursty).

    Returns the out_path on success. Raises RuntimeError if codex fails or no
    image is produced.
    """
    full = f"Call image_gen once with square aspect: {prompt} Reply DONE."
    raw = _run_codex(full, timeout=timeout)

    out_path = str(out_path)
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)

    if target_size:
        from PIL import Image
        img = Image.open(raw).convert("RGBA")
        w, h = img.size
        side = min(w, h)
        left = (w - side) // 2
        top = (h - side) // 2
        sq = img.crop((left, top, left + side, top + side))
        sq.resize(tuple(target_size), Image.NEAREST).save(out_path)
    else:
        shutil.copy(raw, out_path)

    return out_path


def generate_sheet(
    regions: list,
    cell_size=(16, 16),
    grid=None,
    out_dir: str = ".",
    upscale: int = 4,
    gap_px: int = 2,
    style_prefix: str = "Vanilla Minecraft pixel-art style, sharp pixels, no anti-aliasing, flat colors with no gradients.",
    timeout: int = 360,
    save_sheet: bool = True,
) -> dict:
    """Generate ONE combined sheet via codex, slice into per-region PNGs.

    Args:
        regions: list of {"name": str, "prompt": str} dicts in reading order
            (left to right, top to bottom). Each prompt describes ONE cell's
            content only — put shared style guidance in ``style_prefix``.
        cell_size: (w, h) of each FINAL output PNG. Default (16, 16) — vanilla block.
        grid: (rows, cols). If None, auto-picks the smallest square that holds
            all regions. Extra slots become solid-black placeholders.
        out_dir: directory for the sliced PNGs (and the debug sheet if
            ``save_sheet=True``). Created if missing.
        upscale: per-cell upscale factor for the intermediate sheet. Higher =
            more detail captured before NEAREST-downsample to final size.
            Default 4× (so 16×16 cells render at 64×64 in the sheet).
        gap_px: solid-black gridline pixels between cells in the intermediate
            sheet. Default 2 — gives codex a strong visual cue to respect cell
            boundaries and gives slicing some tolerance.
        style_prefix: shared style guidance applied to the whole sheet so all
            cells share aesthetic. Override for non-Minecraft sheets.
        timeout: codex timeout (default 6 min).
        save_sheet: if True, keep the resized intermediate sheet at
            ``out_dir/_sheet.png`` for debugging slicing alignment.

    Returns:
        {name: path} mapping each region name to its sliced PNG path.

    Raises:
        ValueError on bad args (n < 2 — use generate() for single textures,
        or grid too small for regions).
        RuntimeError if codex fails.

    Notes on quality:
        - Codex doesn't always perfectly respect the grid. The gap_px gridlines
          are the main mitigation; if cells come out wrong, check ``_sheet.png``
          to see what codex actually produced.
        - Non-square user-specified grids (e.g. 1×4 strip) work but the codex
          output (square) is center-cropped to the target aspect first, so some
          source pixels are discarded.
        - For best results: keep regions ≤ 16 per sheet. More cells means each
          gets less codex attention and detail tends to mush.
    """
    from PIL import Image

    n = len(regions)
    if n < 2:
        raise ValueError(
            "generate_sheet needs >=2 regions; use generate() for a single texture"
        )

    if grid is None:
        side_count = math.ceil(math.sqrt(n))
        grid = (side_count, side_count)
    rows, cols = grid
    if rows * cols < n:
        raise ValueError(
            f"grid {rows}x{cols} has {rows*cols} slots, can't fit {n} regions"
        )

    cw_out, ch_out = cell_size
    cw_up, ch_up = cw_out * upscale, ch_out * upscale
    sheet_w = cols * cw_up + (cols + 1) * gap_px
    sheet_h = rows * ch_up + (rows + 1) * gap_px

    # Per-cell descriptions, in reading order. Unused grid slots get a
    # "leave blank" placeholder so codex doesn't invent unrequested content.
    descriptions = []
    for slot in range(rows * cols):
        r = slot // cols
        c = slot % cols
        pos_parts = []
        if rows > 1:
            pos_parts.append(f"row {r + 1}")
        if cols > 1:
            pos_parts.append(f"column {c + 1}")
        pos = " ".join(pos_parts) if pos_parts else "the single cell"
        if slot < n:
            cell_prompt = regions[slot]['prompt'].strip().rstrip('.')
            descriptions.append(f"({pos}) {cell_prompt}")
        else:
            descriptions.append(f"({pos}) leave this cell solid black (unused placeholder)")

    full_prompt = (
        f"Call image_gen once: "
        f"A {sheet_w}x{sheet_h} pixel-art texture sheet arranged as a {rows}-row by {cols}-column grid. "
        f"Each cell is exactly {cw_up}x{ch_up} pixels, separated by {gap_px}-pixel-wide "
        f"solid black gridlines between cells and around the perimeter. "
        f"Cells in reading order (left to right, top to bottom): "
        + "; ".join(descriptions)
        + f". {style_prefix} "
        f"Each cell's content must stay strictly within its grid boundaries — no bleeding across gridlines. "
        f"Reply DONE."
    )

    os.makedirs(out_dir, exist_ok=True)
    raw = _run_codex(full_prompt, timeout=timeout)

    # Codex output is approximately square (~1024x1024). Match target aspect
    # via center-crop first, then NEAREST-resize to exact sheet dimensions.
    img = Image.open(raw).convert("RGBA")
    img = _aspect_crop(img, sheet_w, sheet_h)
    sheet = img.resize((sheet_w, sheet_h), Image.NEAREST)

    if save_sheet:
        sheet.save(os.path.join(out_dir, "_sheet.png"), "PNG")

    # Slice each region out, downsample to cell_size, save.
    results = {}
    for i, region in enumerate(regions):
        r = i // cols
        c = i % cols
        x0 = (c + 1) * gap_px + c * cw_up
        y0 = (r + 1) * gap_px + r * ch_up
        cell = sheet.crop((x0, y0, x0 + cw_up, y0 + ch_up))
        cell = cell.resize((cw_out, ch_out), Image.NEAREST)
        out_path = os.path.join(out_dir, f"{region['name']}.png")
        cell.save(out_path, "PNG")
        results[region['name']] = out_path

    return results


def _aspect_crop(img, target_w, target_h):
    """Center-crop ``img`` to match (target_w / target_h) aspect ratio."""
    src_w, src_h = img.size
    target_aspect = target_w / target_h
    src_aspect = src_w / src_h
    if abs(target_aspect - src_aspect) < 0.01:
        return img
    if src_aspect > target_aspect:
        # source wider — crop sides
        new_w = int(src_h * target_aspect)
        x_off = (src_w - new_w) // 2
        return img.crop((x_off, 0, x_off + new_w, src_h))
    else:
        # source taller — crop top/bottom
        new_h = int(src_w / target_aspect)
        y_off = (src_h - new_h) // 2
        return img.crop((0, y_off, src_w, y_off + new_h))
