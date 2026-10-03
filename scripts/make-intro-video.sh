#!/bin/bash
# Builds the intro video from the app's own popover: design/days-until-intro.webp for the README,
# and design/days-until-intro.mp4, which git ignores.
#
# The popover in the video is the app's CountdownView, drawn at each frame's moment by SwiftUI's
# ImageRenderer; scripts/intro-video/main.swift draws the desktop around it. ImageRenderer can't
# draw AppKit views, so the ••• button's menu anchor, an invisible NSView, is left out of the copy
# of the sources built here.
#
# The WebP's frames are drawn 1600 px wide, so it stays sharp at the README's width on a Retina
# display, rather than scaled down from the video.
#
# Needs macOS 26, Xcode's command line tools, and Python 3 with Pillow.
#
# Usage: scripts/make-intro-video.sh [--stills <seconds,…>]
# With --stills it only writes PNGs of those moments, beside the video.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir "$WORK/src"
find "$ROOT/DaysUntil" -name '*.swift' ! -name AppDelegate.swift -exec cp {} "$WORK/src/" \;
ANCHOR='.overlay(MenuAnchor(makeMenu: makeMenu))'
grep -qF "$ANCHOR" "$WORK/src/CountdownView.swift" || { echo "CountdownView.swift: menu anchor not found" >&2; exit 1; }
sed -i '' "s/\.overlay(MenuAnchor(makeMenu: makeMenu))//" "$WORK/src/CountdownView.swift"

swiftc -O -swift-version 5 -default-isolation MainActor -target arm64-apple-macos26.0 -suppress-warnings \
    "$WORK"/src/*.swift "$ROOT/scripts/intro-video/main.swift" -o "$WORK/intro"

# A fixed time zone and US English with 12-hour times, so every render reads the same.
intro() {
    TZ=America/Los_Angeles "$WORK/intro" "$ROOT" "$@" -AppleLocale en_US -AppleLanguages '(en)' -AppleICUForce24HourTime NO
}

OUT="$ROOT/design/days-until-intro"
if [[ "${1:-}" == --stills ]]; then
    intro "$OUT.mp4" "$@"
    exit
fi
intro "$OUT.mp4"
intro "$WORK/frames" --frames 1600
python3 "$ROOT/scripts/intro-video/webp.py" "$WORK/frames" "$OUT.webp"
