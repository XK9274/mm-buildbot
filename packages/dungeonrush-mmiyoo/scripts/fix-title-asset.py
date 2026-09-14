#!/usr/bin/env python3
"""Downscale DungeonRush's title.png sprite strip so no single texture
exceeds the MMIYOO SDL2 renderer's 4096px max texture width, rewriting its
frame descriptor to match. Runs against the staged res/drawable directory
after CMake copies res/ into the build tree -- never touches the pinned
upstream source checkout (package.yml stays modified_source: no).
"""
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("fix-title-asset.py: Pillow is required (pip install Pillow)")

MAX_TEXTURE_WIDTH = 4096
TARGET_WIDTH = 4000  # safety margin under the hard cap

def main():
    if len(sys.argv) != 2:
        sys.exit("usage: fix-title-asset.py <staged res/drawable dir>")

    drawable_dir = Path(sys.argv[1])
    descriptor_path = drawable_dir / "title"
    image_path = drawable_dir / "title.png"

    line = descriptor_path.read_text().strip()
    fields = line.split()
    if len(fields) != 6:
        sys.exit(f"fix-title-asset.py: unexpected descriptor format: {line!r}")
    name, x, y, w, h, frames = fields
    x, y, w, h, frames = int(x), int(y), int(w), int(h), int(frames)

    total_width = w * frames
    if total_width <= MAX_TEXTURE_WIDTH:
        print(f"fix-title-asset: {total_width}px already within the "
              f"{MAX_TEXTURE_WIDTH}px limit, leaving title.png untouched")
        return

    scale = TARGET_WIDTH / total_width
    new_w = max(1, round(w * scale))
    new_h = max(1, round(h * scale))
    new_total_width = new_w * frames

    img = Image.open(image_path)
    if img.size != (total_width, h):
        sys.exit(f"fix-title-asset.py: title.png is {img.size}, expected "
                  f"{(total_width, h)} from the descriptor")
    # LANCZOS on a palette image resamples indices, not colors -- PIL
    # effectively falls back to nearest-neighbor. Convert to RGBA first.
    img = img.convert("RGBA")

    # Resize each frame separately and recomposite: downscaling the whole
    # strip in one pass lets LANCZOS's filter kernel sample across frame
    # boundaries, bleeding adjacent frames into each other's edges.
    resized = Image.new(img.mode, (new_total_width, new_h))
    for i in range(frames):
        frame = img.crop((x + i * w, y, x + i * w + w, y + h))
        resized.paste(frame.resize((new_w, new_h), Image.LANCZOS), (i * new_w, 0))
    resized.save(image_path)

    descriptor_path.write_text(f"{name} 0 0 {new_w} {new_h} {frames}\n")
    print(f"fix-title-asset: {w}x{h}x{frames} (total {total_width}px) -> "
          f"{new_w}x{new_h}x{frames} (total {new_total_width}px)")

if __name__ == "__main__":
    main()
