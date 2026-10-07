#!/usr/bin/env python3
"""Builds the disk image people download Days Until in: DaysUntil-<version>.dmg.

Opening it shows a Finder window with the app on the left, the Applications folder on the right
and an arrow between them, so installing is one drag. The window's layout is written straight into
the image's .DS_Store by dmgbuild, so nothing opens in Finder while it builds. The background is
drawn here, at 1x and 2x, and dmgbuild joins them into one Retina TIFF.

Finder always shows a window with a background picture in light mode, with black labels, so the
background is white like a light Finder window and works when the Mac is in Dark Mode too. The
window's size includes its title bar (32 pt on macOS 26, 28 pt before), so the bottom of the
picture is never seen; it's white there, and the icons sit in the middle of what is.

The image is HFS+, which Finder's background pictures were made for, compressed with LZFSE. It's
signed with the app's identity; notarize and staple it afterwards, as with the zip. Sparkle keeps
updating from the zip, so the image is only for people installing by hand.

Needs dmgbuild and Pillow: pip3 install --break-system-packages dmgbuild pillow

Usage: scripts/make-dmg.py path/to/DaysUntil.app DaysUntil-0.3.4.dmg ["Developer ID Application"]
"""

import pathlib
import subprocess
import sys
import tempfile

import dmgbuild
from PIL import Image, ImageDraw

VOLUME_NAME = "Days Until"
WIDTH, HEIGHT = 600, 360         # the window, title bar included, in points
ICON_SIZE = 128
APP_AT = (170, 150)              # icon centres, from the content's top left, below the title bar
APPLICATIONS_AT = (430, 150)
ARROW_LENGTH = 72
ARROW_COLOUR = (174, 174, 178)   # systemGray2


def draw_background(path, scale):
    """White, with an arrow from the app to Applications. Drawn 4x larger, then scaled down."""
    big = 4 * scale
    image = Image.new("RGB", (WIDTH * big, HEIGHT * big), "white")
    draw = ImageDraw.Draw(image)

    def p(x, y):
        return (round(x * big), round(y * big))

    def stroke(points, width=5):
        draw.line([p(*point) for point in points], fill=ARROW_COLOUR, width=round(width * big), joint="curve")
        for x, y in (points[0], points[-1]):
            r = width / 2
            draw.ellipse([p(x - r, y - r), p(x + r, y + r)], fill=ARROW_COLOUR)

    cx = (APP_AT[0] + APPLICATIONS_AT[0]) / 2
    y = APP_AT[1]
    left, right = cx - ARROW_LENGTH / 2, cx + ARROW_LENGTH / 2
    head = 16
    stroke([(left, y), (right, y)])
    stroke([(right - head, y - head), (right, y), (right - head, y + head)])

    image.resize((WIDTH * scale, HEIGHT * scale), Image.LANCZOS).save(path, dpi=(72 * scale, 72 * scale))


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__.strip().splitlines()[-1])
    app = pathlib.Path(sys.argv[1]).resolve()
    dmg = pathlib.Path(sys.argv[2]).resolve()
    identity = sys.argv[3] if len(sys.argv) == 4 else "Developer ID Application"

    with tempfile.TemporaryDirectory() as scratch:
        background = pathlib.Path(scratch) / "background.png"
        draw_background(background, 1)
        draw_background(background.with_name("background@2x.png"), 2)

        dmg.unlink(missing_ok=True)
        dmgbuild.build_dmg(str(dmg), VOLUME_NAME, settings={
            "format": "ULFO",
            "files": [str(app)],
            "symlinks": {"Applications": "/Applications"},
            "background": str(background),
            "window_rect": ((200, 200), (WIDTH, HEIGHT)),
            "icon_size": ICON_SIZE,
            "text_size": 13,
            "icon_locations": {app.name: APP_AT, "Applications": APPLICATIONS_AT},
        })

    subprocess.run(["codesign", "--sign", identity, "--timestamp", str(dmg)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(dmg)], check=True)
    print(f"Built and signed {dmg}")


if __name__ == "__main__":
    main()
