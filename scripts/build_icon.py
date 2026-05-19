#!/usr/bin/env python3
"""
build_icon.py - Generate resources/toolbox-icon.png for the QTAU
                Connector Workbench .mltbx packaging step.

Why a script and not a static PNG checked in?
  * Reproducibility: anyone with Python + PIL can regenerate.
  * Tunability: design parameters (colors, sizes, fonts) live in
    code so a brand refresh is a 5-line diff.

Design rationale (v2 — quantum-themed)
  * The icon needs to read as "quantum computing" at a glance. The
    visual language convergence across IBM Quantum, Qiskit, Azure
    Quantum, etc. is a Q-monogram with an orbital ring through it
    (the electron-orbit / Saturn-ring metaphor). This icon adopts
    that pattern, customised for QTAU:
      - A bold serif "Q" sits as the brand monogram (nucleus).
      - A tilted elliptical orbit encircles the Q (the electron path).
      - A glowing cyan dot rides the orbit — the qubit state.
        Cyan (#5EEAFF) matches the IBM Quantum / Quantinuum colour
        family, signalling "quantum tech" at first glance.
  * Below the symbol sits the typographic lockup: a thin divider
    rule, the "QTAU" wordmark, and the "SQK CLOUD" tagline with
    spec-sheet tracking — a classic logo-lockup pattern.
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

# ── Symbol: Q monogram + orbital ring + glowing qubit ────────────────────

SYMBOL_CX       = CANVAS_SIZE // 2             # always horizontally centred
SYMBOL_CY       = 92                           # vertical centre of Q + orbit

# "Q" letterform — the brand monogram, primary visual anchor (the "nucleus").
Q_TEXT          = "Q"
Q_COLOR         = (255, 255, 255, 255)
Q_FIT_RATIO     = 0.40                         # Q width spans this fraction of inner card
Q_MAX_SIZE      = 180
Q_MIN_SIZE      = 80

# Orbital ring — encircles the Q, Saturn-ring style.
ORBIT_A         = 96                           # semi-major axis (unrotated)
ORBIT_B         = 34                           # semi-minor axis (unrotated)
ORBIT_TILT_DEG  = 20                           # CCW rotation in degrees
ORBIT_STROKE_W  = 2
ORBIT_COLOR     = (255, 255, 255, 140)         # ~55% alpha white — recedes behind the Q

# Glowing cyan qubit on the orbit.
DOT_ACCENT_RGB  = (94, 234, 255)               # cyan #5EEAFF (IBM Quantum family)
DOT_CORE_R      = 6                            # bright core radius
DOT_HALO_R      = 16                           # halo input radius (gets blurred)
DOT_HALO_ALPHA  = 165                          # ~65% alpha cyan glow before blur
DOT_BLUR_RADIUS = 5                            # Gaussian blur strength for halo
DOT_RING_R      = 9                            # mid-radius "shell" between core and halo
DOT_RING_ALPHA  = 200
# Parametric angle on the UNROTATED ellipse (PIL convention: 0° = east).
# After the orbit's CCW tilt is applied, the dot lands in the upper-right
# quadrant of the icon — a striking "particle at the top of its trajectory".
DOT_ANGLE_DEG   = 10

# ── Lockup: divider + wordmark + tagline (bottom strip) ──────────────────

DIVIDER_COLOR   = (255, 255, 255, 70)          # ~27% alpha white
DIVIDER_WIDTH   = 1
DIVIDER_RATIO   = 0.36                         # fraction of inner card width
DIVIDER_Y       = 170                          # absolute y in canvas

TITLE_TEXT      = "QTAU"
TITLE_COLOR     = (255, 255, 255, 240)
TITLE_FIT_RATIO = 0.30                         # wordmark is SECONDARY to the Q symbol
TITLE_MAX_SIZE  = 36
TITLE_MIN_SIZE  = 14
DIV_TO_TITLE    = 8                            # gap between divider and title top

SUBTITLE_TEXT   = "SQK CLOUD"
SUB_COLOR       = (255, 255, 255, 175)         # quieter than wordmark — supporting role
SUB_FIT_RATIO   = 0.42
SUB_MAX_SIZE    = 16
SUB_MIN_SIZE    = 9
SUB_LETTERSPACE = 5
TITLE_TO_SUB    = 6                            # gap between title bottom and subtitle top


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


def _point_on_tilted_ellipse(angle_deg: float, a: float, b: float,
                             tilt_deg: float, cx: float, cy: float) -> tuple[float, float]:
    """Return image-coord (x, y) of a point on an axis-aligned ellipse of
    semi-axes (a, b) at parametric angle `angle_deg`, then rotated CCW
    by `tilt_deg` around (cx, cy).

    Matches PIL's `Image.rotate(positive_angle)` which appears CCW
    on screen even though image-coord y increases downward.
    """
    t = math.radians(angle_deg)
    px = a * math.cos(t)
    py = b * math.sin(t)
    phi = math.radians(tilt_deg)
    rx =  px * math.cos(phi) + py * math.sin(phi)
    ry = -px * math.sin(phi) + py * math.cos(phi)
    return (cx + rx, cy + ry)


def _make_orbit_layer(draw_fn) -> Image.Image:
    """Render a transparent canvas-sized layer using `draw_fn(draw)`,
    then rotate it CCW by ORBIT_TILT_DEG around the symbol centre.
    Used to draw the back arc, front arc, or any orbit fragment with
    a single tilt applied at the end (cheap and crisp).
    """
    layer = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    return layer.rotate(
        ORBIT_TILT_DEG,
        resample=Image.BICUBIC,
        center=(SYMBOL_CX, SYMBOL_CY),
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

    # ── 5. Symbol: orbital BACK arc → Q glyph → orbital FRONT arc → glow ──
    #
    # The Saturn-ring effect needs three passes so the Q sits "inside" the
    # orbit visually:
    #   (a) Draw the back half of the orbit (upper arc of the unrotated
    #       ellipse, PIL angles 180→360). After rotation, this is the portion
    #       "behind" the Q.
    #   (b) Draw the Q letterform. The Q occludes the back arc where they
    #       overlap.
    #   (c) Draw the front half of the orbit (lower arc, PIL angles 0→180).
    #       This restores visibility of the orbit in front of the Q,
    #       completing the through-Q ring effect.

    orbit_bbox = [
        SYMBOL_CX - ORBIT_A, SYMBOL_CY - ORBIT_B,
        SYMBOL_CX + ORBIT_A, SYMBOL_CY + ORBIT_B,
    ]

    # (a) Back arc — drawn on a rotated layer, composited first.
    back_layer = _make_orbit_layer(
        lambda d: d.arc(orbit_bbox, start=180, end=360,
                        fill=ORBIT_COLOR, width=ORBIT_STROKE_W)
    )
    canvas.alpha_composite(back_layer)

    # (b) Q glyph — auto-fitted serif Q centred on the symbol point.
    q_target = int(inner_w * Q_FIT_RATIO)
    def _q_w(f: ImageFont.FreeTypeFont) -> int:
        bb = _measure_text(draw, Q_TEXT, f)
        return bb[2] - bb[0]
    q_font = _autofit_font(draw, title_font_path, q_target,
                           Q_MIN_SIZE, Q_MAX_SIZE, _q_w)
    qbox = _measure_text(draw, Q_TEXT, q_font)
    q_w = qbox[2] - qbox[0]
    q_h = qbox[3] - qbox[1]
    qx = SYMBOL_CX - q_w / 2 - qbox[0]
    qy = SYMBOL_CY - q_h / 2 - qbox[1]
    draw.text((qx, qy), Q_TEXT, font=q_font, fill=Q_COLOR)
    print(f"  Q     size: {q_font.size}pt -> {q_w}x{q_h}px")

    # (c) Front arc — drawn on a rotated layer, composited on top of the Q.
    front_layer = _make_orbit_layer(
        lambda d: d.arc(orbit_bbox, start=0, end=180,
                        fill=ORBIT_COLOR, width=ORBIT_STROKE_W)
    )
    canvas.alpha_composite(front_layer)

    # ── 6. Glowing cyan qubit on the orbit ────────────────────────────────
    dot_x, dot_y = _point_on_tilted_ellipse(
        DOT_ANGLE_DEG, ORBIT_A, ORBIT_B, ORBIT_TILT_DEG, SYMBOL_CX, SYMBOL_CY
    )
    print(f"  dot   pos:  ({dot_x:.1f}, {dot_y:.1f})  (angle={DOT_ANGLE_DEG}°)")

    # Soft halo — blurred large cyan circle, drawn under the core.
    halo_layer = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(halo_layer).ellipse(
        [dot_x - DOT_HALO_R, dot_y - DOT_HALO_R,
         dot_x + DOT_HALO_R, dot_y + DOT_HALO_R],
        fill=(*DOT_ACCENT_RGB, DOT_HALO_ALPHA),
    )
    halo_layer = halo_layer.filter(ImageFilter.GaussianBlur(radius=DOT_BLUR_RADIUS))
    canvas.alpha_composite(halo_layer)

    # Mid-radius "shell" — gives the qubit a tiny gradient feel.
    draw.ellipse(
        [dot_x - DOT_RING_R, dot_y - DOT_RING_R,
         dot_x + DOT_RING_R, dot_y + DOT_RING_R],
        fill=(*DOT_ACCENT_RGB, DOT_RING_ALPHA),
    )

    # Bright core — solid cyan disc on top.
    draw.ellipse(
        [dot_x - DOT_CORE_R, dot_y - DOT_CORE_R,
         dot_x + DOT_CORE_R, dot_y + DOT_CORE_R],
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
