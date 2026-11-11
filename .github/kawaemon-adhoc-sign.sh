#!/usr/bin/env bash
# Ad-hoc sign a built Ghostty/KGhostty.app so it launches without an Apple
# Developer ID.
#
# Xcode's Release build enables the hardened runtime, whose library
# validation refuses to load ad-hoc signed frameworks (Sparkle) into an
# ad-hoc signed process. We therefore re-sign every nested component and
# the app itself ad-hoc *without* the hardened runtime, innermost first.
#
# Usage: .github/kawaemon-adhoc-sign.sh path/to/App.app
set -euo pipefail

APP="${1:?usage: $0 path/to/App.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() { codesign --force --sign - "$@"; }

sign "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/PlugIns/DockTilePlugin.plugin"
sign --entitlements "$ROOT/macos/Ghostty.entitlements" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
