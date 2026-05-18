#!/usr/bin/env python3
"""
build_icon.py - Generate resources/toolbox-icon.png for the QTAU
                Connector Workbench .mltbx packaging step.

Why a script and not a static PNG checked in?
  * Reproducibility: anyone with Python + PIL can regenerate.
  * Tunability: design parameters (colors, sizes, fonts) live in
    code so a brand refresh is a 5-line diff.
  * macOS sips cannot rasterize the SVG path data in
    resources/sqk-logo-kokkos-white1-reordered.svg (produces a blank
    canvas), and no ImageMagick / Inkscape / rsvg-convert / cairosvg
    is available in the dev environment. PIL is the only working
    fallback.

Design rationale
  * The shipped SVG is a wide horizontal banner (273x56) that does
    not square-crop cleanly. A 256x256 toolbox icon needs to be
    composed for the square aspect, not stretched.
  * "QTAU" (the product name end-users see on File Exchange) is the
    primary mark; "SQK CLOUD" appears smaller as the parent-brand
    attribution.
  * Visual treatment mirrors the (?) help-icon ghost style: white
    on dark-navy backdrop, subtle outline, the same NAV_BG used by
    the app's top toolbar.

Output: resources/toolbox-icon.png (256x256, RGBA, transparent
        corners outside the rounded-square card).

Run: python3 scripts/build_icon.py
"""

from __future__ import annotations

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("PIL not available. Install with: pip install --user Pillow")


# ---- Design parameters --------------------------------------------------

CANVAS_SIZE     = 256                          # output: 256x256 px
CORNER_RADIUS   = 48                           # iOS/macOS-style rounded square
CARD_PADDING    = 12                           # gutter outside the rounded card
CARD_BG         = (26, 31, 38, 255)            # #1A1F26 - Theme.NAV_BG
CARD_BORDER     = (255, 255, 255, 28)          # 11% alpha white outline
CARD_BORDER_W   = 2

TITLE_TEXT      = "QTAU"
TITLE_FONT_SIZE = 108                          # tuned for 4-letter STIX bold
TITLE_COLOR     = (255, 255, 255, 255)
TITLE_NUDGE_Y   = -14                          # shift up to leave room for subtitle

SUBTITLE_TEXT   = "SQK CLOUD"
SUB_FONT_SIZE   = 22
SUB_COLOR       = (255, 255, 255, 170)         # ~67% alpha white
SUB_LETTERSPACE = 4                            # px between subtitle characters
SUB_TOP_PAD     = 8                            # gap below title baseline


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


# ---- Render -------------------------------------------------------------

def main() -> int:
    title_font_path = find_font(TITLE_FONT_CANDIDATES)
    sub_font_path   = find_font(SUB_FONT_CANDIDATES)
    print(f"  title font: {title_font_path}")
    print(f"  sub   font: {sub_font_path}")

    title_font = ImageFont.truetype(title_font_path, TITLE_FONT_SIZE)
    sub_font   = ImageFont.truetype(sub_font_path,   SUB_FONT_SIZE)

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    draw   = ImageDraw.Draw(canvas)

    # Rounded-square dark backdrop with subtle outline.
    p = CARD_PADDING
    draw.rounded_rectangle(
        [p, p, CANVAS_SIZE - p, CANVAS_SIZE - p],
        radius=CORNER_RADIUS,
        fill=CARD_BG,
        outline=CARD_BORDER,
        width=CARD_BORDER_W,
    )

    # Title "QTAU" - centered, nudged up.
    tbox = draw.textbbox((0, 0), TITLE_TEXT, font=title_font)
    tw, th = tbox[2] - tbox[0], tbox[3] - tbox[1]
    tx = (CANVAS_SIZE - tw) / 2 - tbox[0]
    ty = (CANVAS_SIZE - th) / 2 - tbox[1] + TITLE_NUDGE_Y
    draw.text((tx, ty), TITLE_TEXT, font=title_font, fill=TITLE_COLOR)

    # Subtitle "SQK CLOUD" - letter-spaced, centered below title.
    sub_total_w = 0
    char_widths = []
    for ch in SUBTITLE_TEXT:
        cbox = draw.textbbox((0, 0), ch, font=sub_font)
        cw = cbox[2] - cbox[0]
        char_widths.append(cw)
        sub_total_w += cw
    sub_total_w += SUB_LETTERSPACE * (len(SUBTITLE_TEXT) - 1)

    sub_y = ty + th + SUB_TOP_PAD
    sub_x = (CANVAS_SIZE - sub_total_w) / 2
    cursor = sub_x
    for ch, cw in zip(SUBTITLE_TEXT, char_widths):
        draw.text((cursor, sub_y), ch, font=sub_font, fill=SUB_COLOR)
        cursor += cw + SUB_LETTERSPACE

    # Output
    out_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "resources",
        "toolbox-icon.png",
    )
    canvas.save(out_path, "PNG", optimize=True)

    # Sanity check
    chk = Image.open(out_path)
    assert chk.mode == "RGBA",      f"Expected RGBA, got {chk.mode}"
    assert chk.size == (256, 256),  f"Expected 256x256, got {chk.size}"
    nz = sum(1 for x in range(chk.width)
                for y in range(chk.height)
                if chk.getpixel((x, y))[3] > 0)
    trans = chk.width * chk.height - nz
    print(f"  written: {out_path}")
    print(f"  size:    {chk.size}, mode={chk.mode}")
    print(f"  pixels:  {nz} opaque, {trans} transparent")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
