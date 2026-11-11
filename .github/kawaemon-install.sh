#!/usr/bin/env bash
# Build kghostty (Release) and install it as /Applications/KGhostty.app.
#
# Usage: .github/kawaemon-install.sh [--no-build] [--force]
#
#   --no-build  install the existing macos/build/Release/Ghostty.app
#   --force     if KGhostty does not quit (e.g. a quit confirmation is
#               shown because shells are running), terminate it
#
# Steps: build GhosttyKit + the app, quit a running KGhostty, replace the
# installed app, sign it, and launch it.
#
# Signing uses $KGHOSTTY_SIGN_IDENTITY if set, otherwise the first
# "Apple Development" identity in the keychain, otherwise ad-hoc. A real
# identity keeps the signature's designated requirement stable across
# reinstalls, so the Accessibility permission needed by global keybinds
# (e.g. toggle_quick_terminal) keeps working. If the designated requirement
# changes (e.g. switching identities), the stale Accessibility entry is
# reset so macOS prompts again on launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="/Applications/KGhostty.app"
BUNDLE_ID="com.kawaemon.kghostty"
BUILT="$ROOT/macos/build/Release/Ghostty.app"
LOG="${TMPDIR:-/tmp}/kghostty-xcodebuild.log"

build=1
force=0
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --force) force=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }

# --- Build -------------------------------------------------------------------
if [ "$build" = 1 ]; then
  step "Building GhosttyKit (ReleaseFast)"
  (cd "$ROOT" && zig build -Doptimize=ReleaseFast -Demit-macos-app=false)

  step "Building KGhostty.app (Release) — log: $LOG"
  # xcodebuild must not run with a Nix/dev-shell environment.
  if ! (cd "$ROOT/macos" && env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        xcodebuild -project Ghostty.xcodeproj -scheme Ghostty \
        -configuration Release SYMROOT="$ROOT/macos/build" build >"$LOG" 2>&1); then
    grep -E "error:" "$LOG" | tail -20 >&2 || true
    echo "xcodebuild failed; see $LOG" >&2
    exit 1
  fi
fi
[ -d "$BUILT" ] || { echo "missing build: $BUILT" >&2; exit 1; }

# --- Pick a signing identity -------------------------------------------------
identity="${KGHOSTTY_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
identity="${identity:--}"
step "Signing identity: $([ "$identity" = - ] && echo "ad-hoc (Accessibility must be re-granted after every install)" || echo "$identity")"

# Make sure the identity actually works *before* quitting the running app.
# From a non-GUI ("Background") security session, e.g. inside a tmux server
# started outside the GUI, codesign cannot ask for keychain access and fails
# with errSecInternalComponent.
if [ "$identity" != - ]; then
  probe="$(mktemp -d)/probe"
  cp /usr/bin/true "$probe"
  if ! codesign --force --sign "$identity" "$probe" >/dev/null 2>&1; then
    rm -rf "$(dirname "$probe")"
    cat >&2 <<MSG
Cannot sign with "$identity" from this session ($(launchctl managername) session).
Nothing was changed. Either:
  * run this script in a terminal tab outside tmux and click "Always Allow"
    when the keychain asks, or
  * allow codesign to use the key without a prompt (once):
      security set-key-partition-list -S apple-tool:,apple:,codesign: -s \\
        -k "<login password>" ~/Library/Keychains/login.keychain-db
  * or sign ad-hoc: KGHOSTTY_SIGN_IDENTITY=- $0 $*
MSG
    exit 1
  fi
  rm -rf "$(dirname "$probe")"
fi

old_req=""
if [ -d "$DEST" ]; then
  old_req="$(codesign -d -r- "$DEST" 2>/dev/null | sed -n 's/^designated => //p' || true)"
fi

# --- Quit the running app ----------------------------------------------------
if pgrep -f "$DEST/Contents/MacOS/" >/dev/null; then
  step "Quitting running KGhostty"
  osascript -e "tell application \"$DEST\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    pgrep -f "$DEST/Contents/MacOS/" >/dev/null || break
    sleep 0.5
  done
  if pgrep -f "$DEST/Contents/MacOS/" >/dev/null && [ "$force" = 1 ]; then
    echo "Still running; terminating (--force)."
    pkill -TERM -f "$DEST/Contents/MacOS/" || true
    for _ in $(seq 1 20); do
      pgrep -f "$DEST/Contents/MacOS/" >/dev/null || break
      sleep 0.5
    done
    pkill -KILL -f "$DEST/Contents/MacOS/" 2>/dev/null || true
    sleep 1
  fi
  if pgrep -f "$DEST/Contents/MacOS/" >/dev/null; then
    echo "KGhostty is still running (a quit confirmation may be open)." >&2
    echo "Quit it, or re-run with --force (add --no-build to skip rebuilding)." >&2
    exit 1
  fi
fi

# --- Install & sign ----------------------------------------------------------
step "Installing to $DEST"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

step "Signing"
"$ROOT/.github/kawaemon-sign.sh" "$DEST" "$identity" >/dev/null

new_req="$(codesign -d -r- "$DEST" 2>/dev/null | sed -n 's/^designated => //p')"
if [ "$identity" = - ] || [ "$old_req" != "$new_req" ]; then
  step "Signature changed; resetting the stale Accessibility permission"
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "macOS will ask for Accessibility permission when KGhostty starts; allow it."
fi

# --- Launch ------------------------------------------------------------------
step "Launching"
open "$DEST"
echo "Done."
