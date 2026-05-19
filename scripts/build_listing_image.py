#!/usr/bin/env python3
"""
build_listing_image.py - Generate resources/file-exchange-listing.png,
                         the 160x120 landscape thumbnail shown next to
                         the toolbox title on MATLAB Central File
                         Exchange search results.

Why separate from build_icon.py?
  * Different aspect ratio (landscape vs. square) → different composition.
  * The square toolbox-icon.png is the canonical image embedded in the
    .mltbx; this 160x120 file is metadata-only and uploaded to the
    File Exchange listing form, never bundled.
  * Decoupling the two prevents accidental cross-tuning: editing the
    listing thumbnail will never alter the in-product icon.

Design rationale
  * Composition is a split layout: the stylised quantum chandelier
    silhouette on the LEFT, brand wordmark + tagline stacked on the
    RIGHT. At the small displayed size of FX search results this is
    far more readable than a centred icon with text below.
  * Same visual vocabulary as the square toolbox icon — vertical
    chandelier with warm-gold top disc, cool-silver lower stages,
    cyan qubit chip glow at the bottom — so the two assets reinforce
    each other in the shopper's eye.
  * Background: identical vertical gradient + rounded card + top
    highlight + hairline border as the square icon, scaled down.

Output: resources/file-exchange-listing.png (160x120, RGBA).

Run: python3 scripts/build_listing_image.py
"""

from __future__ import annotations

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("PIL not available. Install with: pip install --user Pillow")


# ---- Design parameters --------------------------------------------------

WIDTH           = 160
HEIGHT          = 120
CORNER_RADIUS   = 18
CARD_PADDING    = 6

CARD_TOP        = (40, 47, 60, 255)
CARD_BOTTOM     = (18, 22, 30, 255)
CARD_BORDER     = (255, 255, 255, 36)
CARD_BORDER_W   = 1
HIGHLIGHT_COLOR = (255, 255, 255, 32)
HIGHLIGHT_INSET = 3
HIGHLIGHT_W     = 1

# ── Left column: chandelier silhouette ───────────────────────────────────

CHAND_CX        = 38
GOLD_RGB        = (212, 168, 71)

DISC_TOP        = (22,  24, 8, (*GOLD_RGB, 225), 1)
DISC_2          = (44,  18, 6, (255, 255, 255, 160), 1)
DISC_3          = (66,  12, 5, (255, 255, 255, 140), 1)
DISC_CHIP       = (82,   7, 4, (255, 255, 255, 175), 1)

WIRE_TOP        = (22, 44, 22, 16, 10, (255, 222, 160, 140))
WIRE_MID        = (44, 66, 16, 11,  7, (255, 255, 255, 105))
WIRE_BOT        = (66, 82, 11,  6,  5, (255, 255, 255,  90))

CHIP_GLOW_CY    = 96
DOT_ACCENT_RGB  = (94, 234, 255)
DOT_CORE_R      = 4
DOT_RING_R      = 7
DOT_HALO_R      = 13
DOT_HALO_ALPHA  = 180
DOT_RING_ALPHA  = 215
DOT_BLUR_RADIUS = 4

# ── Right column: brand lockup ───────────────────────────────────────────

LOCKUP_LEFT_X   = 78
LOCKUP_RIGHT_X  = WIDTH - CARD_PADDING - 4
LOCKUP_CX       = (LOCKUP_LEFT_X + LOCKUP_RIGHT_X) // 2

TITLE_TEXT      = "QTAU"
TITLE_COLOR     = (255, 255, 255, 250)
TITLE_FIT_RATIO = 0.78
TITLE_MAX_SIZE  = 34
TITLE_MIN_SIZE  = 14
TITLE_CY        = 48

DIVIDER_COLOR   = (255, 255, 255, 80)
DIVIDER_WIDTH   = 1
DIVIDER_RATIO   = 0.55
DIVIDER_Y       = 70

SUBTITLE_TEXT   = "SQK CLOUD"
SUB_COLOR       = (255, 255, 255, 190)
SUB_FIT_RATIO   = 0.85
SUB_MAX_SIZE    = 12
SUB_MIN_SIZE    = 8                            # PIL+Helvetica.ttc throws div/0 below 8pt
SUB_LETTERSPACE = 3
SUB_TOP_Y       = 78


# ---- Font discovery -----------------------------------------------------

TITLE_FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/STIXGeneralBol.otf",
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


def find_font(candidates: list[str]) -> str:
    for path in candidates:
        if os.path.isfile(path):
            return path
    raise FileNotFoundError(f"None of these fonts exist: {candidates}")


# ---- Helpers ------------------------------------------------------------

def _measure_text(draw, text, font):
    return draw.textbbox((0, 0), text, font=font)


def _measure_subtitle(draw, font):
    char_widths = []
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


def _autofit_font(draw, font_path, target_w, lo, hi, measure):
    """Binary-search the largest font size that fits target_w. Treats
    PIL OSError (some TTC fonts throw div/0 at tiny sizes) as 'too
    small' so the search recovers gracefully."""
    best = ImageFont.truetype(font_path, lo)
    while lo <= hi:
        mid = (lo + hi) // 2
        try:
            candidate = ImageFont.truetype(font_path, mid)
            w = measure(candidate)
        except OSError:
            lo = mid + 1
            continue
        if w <= target_w:
            best = candidate
            lo = mid + 1
        else:
            hi = mid - 1
    return best


def _draw_disc(draw, disc):
    cy, half_w, ell_h, color, stroke_w = disc
    draw.ellipse(
        [CHAND_CX - half_w, cy - ell_h / 2,
         CHAND_CX + half_w, cy + ell_h / 2],
        outline=color,
        width=stroke_w,
    )


def _draw_wire_bundle(draw, bundle):
    y_start, y_end, x_half_start, x_half_end, count, color = bundle
    if count <= 0:
        return
    for i in range(count):
        t = i / (count - 1) if count > 1 else 0.5
        x_top = CHAND_CX + (-x_half_start + 2 * x_half_start * t)
        x_bot = CHAND_CX + (-x_half_end   + 2 * x_half_end   * t)
        draw.line([(x_top, y_start), (x_bot, y_end)], fill=color, width=1)


# ---- Render -------------------------------------------------------------

def main() -> int:
    title_font_path = find_font(TITLE_FONT_CANDIDATES)
    sub_font_path   = find_font(SUB_FONT_CANDIDATES)
    print(f"  title font: {title_font_path}")
    print(f"  sub   font: {sub_font_path}")

    canvas = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))

    grad = Image.new("RGBA", (WIDTH, HEIGHT))
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        c = tuple(int(CARD_TOP[i] * (1 - t) + CARD_BOTTOM[i] * t) for i in range(4))
        grad.paste(c, (0, y, WIDTH, y + 1))

    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [CARD_PADDING, CARD_PADDING, WIDTH - CARD_PADDING, HEIGHT - CARD_PADDING],
        radius=CORNER_RADIUS,
        fill=255,
    )
    canvas.paste(grad, (0, 0), mask)

    draw = ImageDraw.Draw(canvas)
    card_box = [CARD_PADDING, CARD_PADDING,
                WIDTH - CARD_PADDING, HEIGHT - CARD_PADDING]

    inset = HIGHLIGHT_INSET
    draw.rounded_rectangle(
        [card_box[0] + inset, card_box[1] + inset,
         card_box[2] - inset, card_box[3] - inset],
        radius=CORNER_RADIUS - inset,
        outline=HIGHLIGHT_COLOR,
        width=HIGHLIGHT_W,
    )

    draw.rounded_rectangle(
        card_box, radius=CORNER_RADIUS,
        outline=CARD_BORDER, width=CARD_BORDER_W,
    )

    # Chandelier (left column)
    for bundle in (WIRE_TOP, WIRE_MID, WIRE_BOT):
        _draw_wire_bundle(draw, bundle)
    for disc in (DISC_TOP, DISC_2, DISC_3, DISC_CHIP):
        _draw_disc(draw, disc)

    cy, half_w, ell_h, _c, _s = DISC_TOP
    draw.arc(
        [CHAND_CX - half_w + 1, cy - ell_h / 2 + 1,
         CHAND_CX + half_w - 1, cy + ell_h / 2 + 3],
        start=10, end=170,
        fill=(*GOLD_RGB, 95),
        width=1,
    )

    halo_layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    ImageDraw.Draw(halo_layer).ellipse(
        [CHAND_CX - DOT_HALO_R, CHIP_GLOW_CY - DOT_HALO_R,
         CHAND_CX + DOT_HALO_R, CHIP_GLOW_CY + DOT_HALO_R],
        fill=(*DOT_ACCENT_RGB, DOT_HALO_ALPHA),
    )
    halo_layer = halo_layer.filter(ImageFilter.GaussianBlur(radius=DOT_BLUR_RADIUS))
    canvas.alpha_composite(halo_layer)

    draw.ellipse(
        [CHAND_CX - DOT_RING_R, CHIP_GLOW_CY - DOT_RING_R,
         CHAND_CX + DOT_RING_R, CHIP_GLOW_CY + DOT_RING_R],
        fill=(*DOT_ACCENT_RGB, DOT_RING_ALPHA),
    )
    draw.ellipse(
        [CHAND_CX - DOT_CORE_R, CHIP_GLOW_CY - DOT_CORE_R,
         CHAND_CX + DOT_CORE_R, CHIP_GLOW_CY + DOT_CORE_R],
        fill=(*DOT_ACCENT_RGB, 255),
    )

    # Brand lockup (right column)
    right_w = LOCKUP_RIGHT_X - LOCKUP_LEFT_X

    title_target = int(right_w * TITLE_FIT_RATIO)
    title_font = _autofit_font(
        draw, title_font_path, title_target,
        TITLE_MIN_SIZE, TITLE_MAX_SIZE,
        lambda f: (_measure_text(draw, TITLE_TEXT, f)[2]
                   - _measure_text(draw, TITLE_TEXT, f)[0]),
    )
    print(f"  title size: {title_font.size}pt")

    sub_target = int(right_w * SUB_FIT_RATIO)
    sub_font = _autofit_font(
        draw, sub_font_path, sub_target,
        SUB_MIN_SIZE, SUB_MAX_SIZE,
        lambda f: _measure_subtitle(draw, f)[0],
    )
    print(f"  sub   size: {sub_font.size}pt")

    tbox = _measure_text(draw, TITLE_TEXT, title_font)
    title_w = tbox[2] - tbox[0]
    title_h = tbox[3] - tbox[1]
    tx = LOCKUP_CX - title_w / 2 - tbox[0]
    ty = TITLE_CY - title_h / 2 - tbox[1]
    draw.text((tx, ty), TITLE_TEXT, font=title_font, fill=TITLE_COLOR)

    div_w = int(right_w * DIVIDER_RATIO)
    div_x0 = LOCKUP_CX - div_w // 2
    draw.line([(div_x0, DIVIDER_Y), (div_x0 + div_w, DIVIDER_Y)],
              fill=DIVIDER_COLOR, width=DIVIDER_WIDTH)

    sub_total_w, char_widths, _sa, _sd = _measure_subtitle(draw, sub_font)
    cursor = LOCKUP_CX - sub_total_w / 2
    for ch, cw in zip(SUBTITLE_TEXT, char_widths):
        cbox = draw.textbbox((0, 0), ch, font=sub_font)
        draw.text((cursor - cbox[0], SUB_TOP_Y - cbox[1]), ch,
                  font=sub_font, fill=SUB_COLOR)
        cursor += cw + SUB_LETTERSPACE

    # Output
    out_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "resources",
        "file-exchange-listing.png",
    )
    canvas.save(out_path, "PNG", optimize=True)

    chk = Image.open(out_path)
    assert chk.mode == "RGBA",          f"Expected RGBA, got {chk.mode}"
    assert chk.size == (WIDTH, HEIGHT), f"Expected {WIDTH}x{HEIGHT}, got {chk.size}"
    print(f"  written: {out_path}  ({chk.size})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
