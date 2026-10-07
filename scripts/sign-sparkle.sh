#!/bin/zsh
# Signs Sparkle's helpers inside a built Days Until with the app's own identity, then the app again.
#
# Xcode signs the embedded Sparkle.framework but leaves the programs inside it (its Installer and
# Downloader XPC services, Autoupdate and Updater.app) with Sparkle's ad hoc signatures, which
# notarization rejects. Inner code first, never with --deep, as Sparkle's documentation asks. The
# Downloader keeps its entitlements, and the app keeps its own and the widget's signature.
#
# Usage: scripts/sign-sparkle.sh "path/to/Days Until.app" ["Developer ID Application"]

set -euo pipefail

app=${1:?usage: scripts/sign-sparkle.sh "path/to/Days Until.app" [identity]}
identity=${2:-Developer ID Application}
sparkle="$app/Contents/Frameworks/Sparkle.framework"
helpers="$sparkle/Versions/B"

sign() { codesign --force --sign "$identity" --options runtime --timestamp "$@" }

sign "$helpers/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$helpers/XPCServices/Downloader.xpc"
sign "$helpers/Autoupdate"
sign "$helpers/Updater.app"
sign "$sparkle"
sign --preserve-metadata=entitlements,requirements,flags "$app"

codesign --verify --deep --strict "$app"
for code in "$helpers/XPCServices/Installer.xpc" "$helpers/XPCServices/Downloader.xpc" "$helpers/Autoupdate" "$helpers/Updater.app" "$sparkle" "$app"; do
    if codesign -dv "$code" 2>&1 | grep -q "Signature=adhoc"; then
        echo "Still ad hoc: $code" >&2
        exit 1
    fi
done
echo "Signed Sparkle's helpers and $app"
