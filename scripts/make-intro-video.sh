#!/bin/bash
# Builds the intro video, design/days-until-intro.mp4, from the app's own popover.
#
# The popover in the video is the app's CountdownView, drawn at each frame's moment by SwiftUI's
# ImageRenderer; scripts/intro-video/main.swift draws the desktop around it. ImageRenderer can't
# draw AppKit views, so the ••• button's menu anchor, an invisible NSView, is left out of the copy
# of the sources built here.
#
# Needs macOS 26 and Xcode's command line tools.
#
# Usage: scripts/make-intro-video.sh [--stills <seconds,…>]
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
TZ=America/Los_Angeles "$WORK/intro" "$ROOT" "$ROOT/design/days-until-intro.mp4" "$@" \
    -AppleLocale en_US -AppleLanguages '(en)' -AppleICUForce24HourTime NO
