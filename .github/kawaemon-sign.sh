#!/usr/bin/env bash
# Sign a built Ghostty/KGhostty.app so that it launches.
#
# Usage: .github/kawaemon-sign.sh path/to/App.app [identity]
#
# identity defaults to "-" (ad-hoc). Pass a codesigning identity (e.g. an
# "Apple Development: ..." certificate) to get a stable signature, which
# lets macOS privacy permissions such as Accessibility survive reinstalls.
#
# Every nested component is re-signed innermost first with the same
# identity, without the hardened runtime: with ad-hoc signing, the hardened
# runtime's library validation refuses to load the bundled Sparkle.framework.
set -euo pipefail

APP="${1:?usage: $0 path/to/App.app [identity]}"
IDENTITY="${2:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() { codesign --force --sign "$IDENTITY" "$@"; }

sign "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/PlugIns/DockTilePlugin.plugin"
sign --entitlements "$ROOT/macos/Ghostty.entitlements" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
