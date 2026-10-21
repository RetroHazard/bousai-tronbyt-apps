#!/usr/bin/env python3
"""Tile the distinct frames of a rendered GIF into one PNG for review.

Usage: uv run --with pillow tools/contact_sheet.py in.gif out.png [max_frames]
"""

import sys

from PIL import Image, ImageSequence


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    max_frames = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    frames, last = [], None
    for frame in ImageSequence.Iterator(Image.open(src)):
        rgb = frame.convert("RGB")
        data = rgb.tobytes()
        if data != last:
            frames.append(rgb.copy())
            last = data
    step = max(1, len(frames) // max_frames)
    chosen = frames[::step][:max_frames]
    w, h = chosen[0].size
    cols = 2 if w > 300 else 4
    rows = (len(chosen) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (w + 4), rows * (h + 4)), (40, 40, 40))
    for i, frame in enumerate(chosen):
        sheet.paste(frame, ((i % cols) * (w + 4), (i // cols) * (h + 4)))
    sheet.save(out)
    print(f"{len(frames)} distinct frames, showing {len(chosen)}")


if __name__ == "__main__":
    main()
