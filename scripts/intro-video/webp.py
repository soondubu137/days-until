#!/usr/bin/env python3
"""Packs the intro video's frames into the animated WebP the README shows.

The frames are read one at a time, so they never sit in memory together, and frames that don't
change merge into one longer frame. Called by scripts/make-intro-video.sh.

Usage: webp.py <folder of numbered PNGs> <output.webp>
"""

import pathlib
import sys

from PIL import Image

FPS = 30        # as the video's
QUALITY = 80


class Frames(Image.Image):
    """The PNGs as one image with many frames, each loaded as the encoder seeks to it."""

    def __init__(self, paths):
        super().__init__()
        self.paths = paths
        self.n_frames = len(paths)
        self.seek(0)

    def seek(self, index):
        with Image.open(self.paths[index]) as frame:
            frame = frame.convert("RGB")
        self.im, self._mode, self._size = frame.im, frame.mode, frame.size
        self.index = index

    def tell(self):
        return self.index


def main():
    folder, output = sys.argv[1:]
    paths = sorted(pathlib.Path(folder).glob("*.png"))
    # Whole milliseconds that add up to the video's length.
    durations = [round((i + 1) * 1000 / FPS) - round(i * 1000 / FPS) for i in range(len(paths))]
    Frames(paths).save(output, save_all=True, duration=durations, loop=0, quality=QUALITY, method=4)


if __name__ == "__main__":
    main()
