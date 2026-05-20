#!/usr/bin/env python3
"""
build_icon.py - Generate resources/toolbox-icon.png for the QTAU
                Connector Workbench .mltbx packaging step.

Why a script and not a static PNG checked in?
  * Reproducibility: anyone with Python + PIL can regenerate.
  * Tunability: design parameters (colors, sizes, fonts) live in
    code so a brand refresh is a 5-line diff.

Design rationale (v3 — quantum-hardware silhouette)
  * The icon depicts a stylised dilution refrigerator — the iconic
    "quantum chandelier" photographed in every IBM Quantum / Google
    Quantum AI press shot. This is the universally recognisable image
    of quantum-computing HARDWARE (vs. the abstract physics orbital,
    which is used by every other quantum SDK icon).
  * Vertical tapered stack of horizontal cooling plates (discs),
    connected by fanning wire bundles — the visual signature of the
    real instrument. Top disc is warmest (room-temperature interface,
    rendered in gold #D4A847), lower stages cool down through silver
    tones, and the chip platform at the bottom hosts the qubit glow.
  * A cyan (#5EEAFF) qubit emits a Gaussian-blurred halo at the
    bottom of the stack — semantically meaningful: that is literally
    where qubits live (~15 millikelvin, the coldest engineered point
    in the universe).
  * Below the silhouette: a thin divider rule, the prominent QTAU
    wordmark (carrying the brand letter the symbol now sheds), and
    the SQK CLOUD tagline with spec-sheet tracking.
  * Background uses a vertical gradient (lifted top, deep bottom)
    plus a subtle top inner highlight to give the card depth.

Output: resources/toolbox-icon.png (256x256, RGBA, transparent
        corners outside the rounded-square card).

Run: python3 scripts/build_icon.py
"""

from __future__ import annotations

import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("PIL not available. Install with: pip install --user Pillow")


# ---- Design parameters --------------------------------------------------

CANVAS_SIZE     = 256                          # output: 256x256 px
CORNER_RADIUS   = 56                           # iOS/macOS-style rounded square
CARD_PADDING    = 16                           # gutter outside the rounded card

# Vertical gradient gives depth ("light from above") — anchored on Theme.NAV_BG.
CARD_TOP        = (40, 47, 60, 255)            # #282F3C - lifted top
CARD_BOTTOM     = (18, 22, 30, 255)            # #12161E - deep bottom
CARD_BORDER     = (255, 255, 255, 36)          # ~14% alpha white outline
CARD_BORDER_W   = 1
# Inner top highlight — simulates a soft specular along the top arc.
HIGHLIGHT_COLOR = (255, 255, 255, 32)          # ~12% alpha white
HIGHLIGHT_INSET = 4                            # inset from card edge
HIGHLIGHT_W     = 2

# ── Symbol: stylised dilution-refrigerator chandelier ────────────────────
#
# Composition (top → bottom of the symbol):
#   • 4 horizontal cooling plates ("discs") tapering inward
#   • Wire bundles fanning between each adjacent disc pair
#   • A cyan qubit glow centred below the lowest plate
#
# All discs share the canvas centre column. Each tier's geometry
# (y-position, half-width, stroke colour, wire count) is kept in a
# DISCS list so the silhouette is one edit away from rebalancing.

SYMBOL_CX       = CANVAS_SIZE // 2             # always horizontally centred

# Discs — (y_center, half_width, ellipse_height, stroke_color, stroke_w).
# Ordered top to bottom. Top disc carries the warm gold (room-temperature
# interface); lower discs fade to cool silver as the cryostat cools.
GOLD_RGB        = (212, 168, 71)               # #D4A847 (warm gold)
DISC_TOP        = (46,  72, 12, (*GOLD_RGB, 220), 2)
DISC_2          = (84,  52,  9, (255, 255, 255, 150), 2)
DISC_3          = (118, 36,  6, (255, 255, 255, 130), 2)
DISC_CHIP       = (140, 20,  4, (255, 255, 255, 165), 2)

# Optional thin gold highlight along the bottom of the TOP disc — gives
# the "warm metal lip" of the room-temperature flange.
TOP_HIGHLIGHT_ALPHA = 80

# Wire bundles — (y_start, y_end, x_half_start, x_half_end, count, color).
# x_half is the half-width of the bundle's lateral spread at that y.
# count is the number of parallel wires; they fan inward as the bundle
# descends so the silhouette tapers like the real chandelier.
WIRE_COLOR_TOP    = (255, 222, 160, 130)       # warm gold-tinted, recedes
WIRE_COLOR_MID    = (255, 255, 255,  90)       # cooler down the stack
WIRE_COLOR_BOT    = (255, 255, 255,  75)
BUNDLE_1          = (46, 84,  60, 44, 16, WIRE_COLOR_TOP)
BUNDLE_2          = (84, 118, 44, 30, 12, WIRE_COLOR_MID)
BUNDLE_3          = (118, 140, 30, 16,  8, WIRE_COLOR_BOT)

# Qubit chip glow — the coldest point of the cryostat, where qubits live.
CHIP_GLOW_CY    = 158
DOT_ACCENT_RGB  = (94, 234, 255)               # cyan #5EEAFF (IBM Quantum family)
DOT_CORE_R      = 6
DOT_RING_R      = 10
DOT_HALO_R      = 18
DOT_HALO_ALPHA  = 175
DOT_RING_ALPHA  = 210
DOT_BLUR_RADIUS = 6

# ── Lockup: divider + wordmark + tagline (bottom strip) ──────────────────

DIVIDER_COLOR   = (255, 255, 255, 70)          # ~27% alpha white
DIVIDER_WIDTH   = 1
DIVIDER_RATIO   = 0.38                         # fraction of inner card width
DIVIDER_Y       = 184                          # absolute y in canvas

TITLE_TEXT      = "QTAU"
TITLE_COLOR     = (255, 255, 255, 245)
TITLE_FIT_RATIO = 0.36                         # larger now: wordmark carries the brand letter
TITLE_MAX_SIZE  = 44
TITLE_MIN_SIZE  = 16
DIV_TO_TITLE    = 8                            # gap between divider and title top

SUBTITLE_TEXT   = "SQK CLOUD"
SUB_COLOR       = (255, 255, 255, 180)
SUB_FIT_RATIO   = 0.42
SUB_MAX_SIZE    = 16
SUB_MIN_SIZE    = 9
SUB_LETTERSPACE = 5
TITLE_TO_SUB    = 5                            # gap between title bottom and subtitle top


# ---- Font discovery -----------------------------------------------------

def find_font(candidates: list[str]) -> str:
    for path in candidates:
        if os.path.isfile(path):
            return path
    raise FileNotFoundError(f"None of these fonts exist: {candidates}")


TITLE_FONT_CANDIDATES = [
    # STIX Bold matches the SVG logo's STIX Two Text aesthetic exactly.
    "/System/Library/Fonts/Supplemental/STIXGeneralBol.otf",
    # Fallbacks in order of aesthetic closeness.
    "/Library/Fonts/STIXGeneralBol.otf",
    "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf",
    "/Library/Fonts/Times New Roman Bold.ttf",
    "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
    "/Library/Fonts/Georgia Bold.ttf",
]

SUB_FONT_CANDIDATES = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Georgia.ttf",
]


# ---- Helpers ------------------------------------------------------------

def _measure_text(draw: ImageDraw.ImageDraw, text: str,
                  font: ImageFont.FreeTypeFont) -> tuple[int, int, int, int]:
    """Tight bbox (x0, y0, x1, y1) of `text` for `font`."""
    return draw.textbbox((0, 0), text, font=font)


def _measure_subtitle(draw: ImageDraw.ImageDraw,
                      font: ImageFont.FreeTypeFont) -> tuple[int, list[int], int, int]:
    """Total width (with letter-spacing), per-char widths, ascent, descent."""
    char_widths: list[int] = []
    total = 0
    ascent = 0
    descent = 0
    for ch in SUBTITLE_TEXT:
        cbox = draw.textbbox((0, 0), ch, font=font)
        cw = cbox[2] - cbox[0]
        char_widths.append(cw)
        total += cw
        ascent = max(ascent, -cbox[1])
        descent = max(descent, cbox[3])
    total += SUB_LETTERSPACE * (len(SUBTITLE_TEXT) - 1)
    return total, char_widths, ascent, descent


def _autofit_font(draw: ImageDraw.ImageDraw, font_path: str, target_w: int,
                  lo: int, hi: int, measure) -> ImageFont.FreeTypeFont:
    """Binary-search the largest font size whose rendered width fits target_w."""
    best = ImageFont.truetype(font_path, lo)
    while lo <= hi:
        mid = (lo + hi) // 2
        candidate = ImageFont.truetype(font_path, mid)
        w = measure(candidate)
        if w <= target_w:
            best = candidate
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def _draw_disc(draw: ImageDraw.ImageDraw, disc) -> None:
    """Draw a horizontal cooling plate (ellipse outline)."""
    cy, half_w, ell_h, color, stroke_w = disc
    draw.ellipse(
        [SYMBOL_CX - half_w, cy - ell_h / 2,
         SYMBOL_CX + half_w, cy + ell_h / 2],
        outline=color,
        width=stroke_w,
    )


def _draw_wire_bundle(draw: ImageDraw.ImageDraw, bundle) -> None:
    """Draw `count` parallel-ish wires fanning from (cx ± x_half_start)
    at y_start to (cx ± x_half_end) at y_end. The wires tilt inward
    as the bundle descends, building the chandelier's tapered cage.
    """
    y_start, y_end, x_half_start, x_half_end, count, color = bundle
    if count <= 0:
        return
    for i in range(count):
        t = i / (count - 1) if count > 1 else 0.5
        # Map t∈[0,1] linearly to x∈[-half, +half] for both ends.
        x_top = SYMBOL_CX + (-x_half_start + 2 * x_half_start * t)
        x_bot = SYMBOL_CX + (-x_half_end   + 2 * x_half_end   * t)
        draw.line([(x_top, y_start), (x_bot, y_end)], fill=color, width=1)


def _draw_top_disc_highlight(draw: ImageDraw.ImageDraw) -> None:
    """A faint gold under-curve along the bottom of the top disc —
    the warm-metal lip of the room-temperature flange."""
    cy, half_w, ell_h, _color, _stroke = DISC_TOP
    draw.arc(
        [SYMBOL_CX - half_w + 2, cy - ell_h / 2 + 1,
         SYMBOL_CX + half_w - 2, cy + ell_h / 2 + 4],
        start=10, end=170,
        fill=(*GOLD_RGB, TOP_HIGHLIGHT_ALPHA),
        width=1,
    )


def main() -> int:
    title_font_path = find_font(TITLE_FONT_CANDIDATES)
    sub_font_path   = find_font(SUB_FONT_CANDIDATES)
    print(f"  title font: {title_font_path}")
    print(f"  sub   font: {sub_font_path}")

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))

    # 1. Vertical gradient (top lifted, bottom deep) — gives the card depth.
    grad = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE))
    for y in range(CANVAS_SIZE):
        t = y / (CANVAS_SIZE - 1)
        c = tuple(int(CARD_TOP[i] * (1 - t) + CARD_BOTTOM[i] * t) for i in range(4))
        grad.paste(c, (0, y, CANVAS_SIZE, y + 1))

    # 2. Rounded-square mask so the gradient corners are softened.
    mask = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [CARD_PADDING, CARD_PADDING, CANVAS_SIZE - CARD_PADDING, CANVAS_SIZE - CARD_PADDING],
        radius=CORNER_RADIUS,
        fill=255,
    )
    canvas.paste(grad, (0, 0), mask)

    draw = ImageDraw.Draw(canvas)
    card_box = [CARD_PADDING, CARD_PADDING,
                CANVAS_SIZE - CARD_PADDING, CANVAS_SIZE - CARD_PADDING]

    # 3. Subtle top inner highlight — a slightly inset rounded rect, only
    #    the top half is visually present because the bottom half is hidden
    #    by drawing over it with the outline pass.
    inset = HIGHLIGHT_INSET
    draw.rounded_rectangle(
        [card_box[0] + inset, card_box[1] + inset,
         card_box[2] - inset, card_box[3] - inset],
        radius=CORNER_RADIUS - inset,
        outline=HIGHLIGHT_COLOR,
        width=HIGHLIGHT_W,
    )

    # 4. Outer card outline — thin hairline framing the whole card.
    draw.rounded_rectangle(
        card_box,
        radius=CORNER_RADIUS,
        outline=CARD_BORDER,
        width=CARD_BORDER_W,
    )

    inner_w = CANVAS_SIZE - 2 * CARD_PADDING

    # ── 5. Symbol: stylised quantum chandelier ────────────────────────────
    #
    # Draw order (back → front, so each layer occludes the one beneath):
    #   (a) Wire bundles between successive discs (so wire ends are tucked
    #       behind the disc rims drawn next).
    #   (b) Disc outlines (top warm gold, lower stages cool silver).
    #   (c) Faint gold under-curve along the top disc (the "warm flange").
    #   (d) Cyan qubit glow at CHIP_GLOW_CY: blurred halo, mid shell, core.

    # (a) Wire bundles
    for bundle in (BUNDLE_1, BUNDLE_2, BUNDLE_3):
        _draw_wire_bundle(draw, bundle)

    # (b) Discs (top to bottom)
    for disc in (DISC_TOP, DISC_2, DISC_3, DISC_CHIP):
        _draw_disc(draw, disc)

    # (c) Warm gold lip below the top disc
    _draw_top_disc_highlight(draw)

    # (d) Qubit glow — the coldest point of the cryostat
    glow_x = SYMBOL_CX
    glow_y = CHIP_GLOW_CY
    print(f"  chip  pos:  ({glow_x}, {glow_y})")

    # Soft halo (blurred cyan disc) sits behind the core.
    halo_layer = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(halo_layer).ellipse(
        [glow_x - DOT_HALO_R, glow_y - DOT_HALO_R,
         glow_x + DOT_HALO_R, glow_y + DOT_HALO_R],
        fill=(*DOT_ACCENT_RGB, DOT_HALO_ALPHA),
    )
    halo_layer = halo_layer.filter(ImageFilter.GaussianBlur(radius=DOT_BLUR_RADIUS))
    canvas.alpha_composite(halo_layer)

    # Mid-radius shell adds a tiny gradient feel.
    draw.ellipse(
        [glow_x - DOT_RING_R, glow_y - DOT_RING_R,
         glow_x + DOT_RING_R, glow_y + DOT_RING_R],
        fill=(*DOT_ACCENT_RGB, DOT_RING_ALPHA),
    )

    # Bright core — solid cyan disc on top.
    draw.ellipse(
        [glow_x - DOT_CORE_R, glow_y - DOT_CORE_R,
         glow_x + DOT_CORE_R, glow_y + DOT_CORE_R],
        fill=(*DOT_ACCENT_RGB, 255),
    )

    # ── 7. Bottom lockup: divider → wordmark → tagline ────────────────────

    # Auto-fit title font so QTAU spans TITLE_FIT_RATIO of the inner card width.
    title_target = int(inner_w * TITLE_FIT_RATIO)
    def _title_w(f: ImageFont.FreeTypeFont) -> int:
        bb = _measure_text(draw, TITLE_TEXT, f)
        return bb[2] - bb[0]
    title_font = _autofit_font(draw, title_font_path, title_target,
                               TITLE_MIN_SIZE, TITLE_MAX_SIZE, _title_w)
    print(f"  title size: {title_font.size}pt -> width {_title_w(title_font)}px (target {title_target}px)")

    # Auto-fit subtitle font so "SQK CLOUD" with tracking fits SUB_FIT_RATIO.
    sub_target = int(inner_w * SUB_FIT_RATIO)
    def _sub_w(f: ImageFont.FreeTypeFont) -> int:
        return _measure_subtitle(draw, f)[0]
    sub_font = _autofit_font(draw, sub_font_path, sub_target,
                             SUB_MIN_SIZE, SUB_MAX_SIZE, _sub_w)
    print(f"  sub   size: {sub_font.size}pt -> width {_sub_w(sub_font)}px (target {sub_target}px)")

    # Divider — thin centred rule at fixed Y.
    div_w = int(inner_w * DIVIDER_RATIO)
    div_x0 = (CANVAS_SIZE - div_w) // 2
    draw.line([(div_x0, DIVIDER_Y), (div_x0 + div_w, DIVIDER_Y)],
              fill=DIVIDER_COLOR, width=DIVIDER_WIDTH)

    # Wordmark — horizontally centred, anchored below the divider.
    tbox = _measure_text(draw, TITLE_TEXT, title_font)
    title_w = tbox[2] - tbox[0]
    title_h = tbox[3] - tbox[1]
    tx = (CANVAS_SIZE - title_w) / 2 - tbox[0]
    ty = DIVIDER_Y + DIV_TO_TITLE - tbox[1]
    draw.text((tx, ty), TITLE_TEXT, font=title_font, fill=TITLE_COLOR)

    # Tagline — horizontally centred below the wordmark with measured tracking.
    sub_total_w, char_widths, _sa, _sd = _measure_subtitle(draw, sub_font)
    sub_top = DIVIDER_Y + DIV_TO_TITLE + title_h + TITLE_TO_SUB
    cursor = (CANVAS_SIZE - sub_total_w) / 2
    for ch, cw in zip(SUBTITLE_TEXT, char_widths):
        cbox = draw.textbbox((0, 0), ch, font=sub_font)
        draw.text((cursor - cbox[0], sub_top - cbox[1]), ch,
                  font=sub_font, fill=SUB_COLOR)
        cursor += cw + SUB_LETTERSPACE

    # ── Output: master 256x256 plus high-quality downscaled variants ─────
    #
    # MATLAB's Add-Ons UI displays the toolbox image at 64x64; File
    # Exchange uses 256x256 for the listing hero; 160x160 covers the
    # in-between "medium" surfaces. We render the design once at 256x256
    # (the resolution the typography and chandelier were tuned for) and
    # produce the smaller assets via LANCZOS downscaling — the same
    # resampling kernel MATLAB uses internally.

    resources_dir = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "resources",
    )

    outputs = [
        (256, "toolbox-icon.png"),
        (160, "toolbox-icon-160.png"),
        ( 64, "toolbox-icon-64.png"),
    ]

    for size, fname in outputs:
        out_path = os.path.join(resources_dir, fname)
        if size == CANVAS_SIZE:
            img = canvas
        else:
            img = canvas.resize((size, size), resample=Image.LANCZOS)
        img.save(out_path, "PNG", optimize=True)

        chk = Image.open(out_path)
        assert chk.mode == "RGBA",        f"Expected RGBA, got {chk.mode}"
        assert chk.size == (size, size),  f"Expected {size}x{size}, got {chk.size}"
        print(f"  written: {out_path}  ({chk.size})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
