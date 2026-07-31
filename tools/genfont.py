#!/usr/bin/env python3
"""Generate a Playdate bitmap font (.fnt + companion PNG table) with Cyrillic.

The Playdate app renders every string with the built-in system font, which has
no Cyrillic glyphs, so Cyrillic todos show as blank boxes. This script rasterizes
Noto Sans (SIL Open Font License) into the Playdate bitmap-font format so the app
can embed and use a Cyrillic-capable font.

Output:
  Source/fonts/NotoCyrillic.fnt
  Source/fonts/NotoCyrillic-table-<W>-<H>.png

Format reference (verified against the SDK's Roobert-11-Medium):
  - The .fnt lists one glyph per line as "<char>\\t<advance>" (the space char is
    written as the literal word "space"), preceded by a "tracking=N" line.
  - The companion PNG holds glyphs in a fixed W x H cell grid, filled row-major in
    the exact order the glyphs are listed in the .fnt. Columns = imageWidth / W.

Run:  python3 tools/genfont.py
"""

import math
import os
import urllib.request

from PIL import Image, ImageDraw, ImageFont

# --- paths --------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
TTF_PATH = os.path.join(HERE, "NotoSans-Regular.ttf")
TTF_URL = (
    "https://github.com/googlefonts/noto-fonts/raw/main/"
    "hinted/ttf/NotoSans/NotoSans-Regular.ttf"
)
OUT_DIR = os.path.join(REPO, "Source", "fonts")
FONT_NAME = "NotoCyrillic"

# --- tunables -----------------------------------------------------------------
FONT_PX = 16      # rasterization size; yields a ~19-20px line height
COLUMNS = 16      # glyph grid width
TRACKING = 1      # extra px added between glyphs by the renderer
THRESHOLD = 110   # >= this luminance becomes ink (1-bit conversion)


def build_charset():
    """Ordered list of characters to include. Order defines the grid order."""
    chars = []
    # ASCII printable
    chars += [chr(c) for c in range(0x20, 0x7F)]
    # Russian Cyrillic: А-я plus Ё/ё
    chars += [chr(c) for c in range(0x410, 0x450)]
    chars += ["Ё", "ё"]  # Ё ё
    # Ukrainian extras
    chars += ["Ґ", "ґ", "Є", "є",
              "І", "і", "Ї", "ї"]  # Ґ ґ Є є І і Ї ї
    # Common punctuation seen in task titles
    chars += ["–", "—", "«", "»"]  # – — « »
    # De-duplicate, preserving order
    seen = set()
    out = []
    for ch in chars:
        if ch not in seen:
            seen.add(ch)
            out.append(ch)
    return out


def ensure_ttf():
    if os.path.exists(TTF_PATH):
        return
    print(f"Downloading Noto Sans -> {TTF_PATH}")
    urllib.request.urlretrieve(TTF_URL, TTF_PATH)


def glyph_name(ch):
    """How the glyph is labeled in the .fnt."""
    if ch == " ":
        return "space"
    return ch


def main():
    ensure_ttf()
    os.makedirs(OUT_DIR, exist_ok=True)

    font = ImageFont.truetype(TTF_PATH, FONT_PX)
    ascent, descent = font.getmetrics()
    cell_h = ascent + descent
    baseline = ascent

    chars = build_charset()

    # Measure: advance width per glyph and the max ink extent to size the cell.
    advances = {}
    max_w = 1
    for ch in chars:
        advance = math.ceil(font.getlength(ch))
        # bbox of ink relative to the pen origin at (0, baseline)
        bbox = font.getbbox(ch)  # (left, top, right, bottom), origin at top
        ink_right = bbox[2] if bbox else 0
        advances[ch] = max(advance, 0)
        max_w = max(max_w, advance, ink_right)

    cell_w = max_w + 1  # +1 px of right breathing room
    rows = math.ceil(len(chars) / COLUMNS)
    img_w = cell_w * COLUMNS
    img_h = cell_h * rows

    # Render each glyph in grayscale, then convert to black-ink-on-transparent.
    gray = Image.new("L", (img_w, img_h), 0)
    draw = ImageDraw.Draw(gray)
    for i, ch in enumerate(chars):
        col = i % COLUMNS
        row = i // COLUMNS
        x = col * cell_w
        y = row * cell_h + baseline
        if ch != " ":
            draw.text((x, y), ch, font=font, fill=255, anchor="ls")

    rgba = Image.new("RGBA", (img_w, img_h), (0, 0, 0, 0))
    px_gray = gray.load()
    px_out = rgba.load()
    for yy in range(img_h):
        for xx in range(img_w):
            if px_gray[xx, yy] >= THRESHOLD:
                px_out[xx, yy] = (0, 0, 0, 255)

    png_path = os.path.join(OUT_DIR, f"{FONT_NAME}-table-{cell_w}-{cell_h}.png")
    rgba.save(png_path)

    fnt_path = os.path.join(OUT_DIR, f"{FONT_NAME}.fnt")
    with open(fnt_path, "w", encoding="utf-8") as f:
        f.write(f"tracking={TRACKING}\n\n")
        for ch in chars:
            f.write(f"{glyph_name(ch)}\t{advances[ch]}\n")

    print(f"Wrote {fnt_path}")
    print(f"Wrote {png_path}")
    print(f"glyphs={len(chars)} grid={COLUMNS}x{rows} cell={cell_w}x{cell_h}")


if __name__ == "__main__":
    main()
