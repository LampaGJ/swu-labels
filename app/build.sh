#!/usr/bin/env bash
#
# build.sh — compile with SwiftPM, assemble the macOS .app bundle, codesign.
#
# Usage:  ./build.sh [debug|release]
#
# Produces a DUAL-BINARY bundle:
#
#   SWULabels.app/Contents/MacOS/SWULabels     the GUI
#   SWULabels.app/Contents/MacOS/swu-labels    the CLI
#   SWULabels.app/Contents/Resources/assets    rarity icons
#   SWULabels.app/Contents/Resources/data      pinned snapshots
#
# The CLI ships inside the bundle on purpose: signing the bundle covers both
# binaries, so one signature and one notarization ticket serve the app and the
# command. A separately shipped CLI would need its own of each.
#
# NO Xcode IDE, NO xcodebuild — `swift build` compiles, this script bundles and
# signs. Xcode is only a toolchain provider (swift / codesign).
#
# Environment:
#   SIGN_IDENTITY      codesign identity. Defaults to ad-hoc ("-").
#   PROVISION_PROFILE  optional .provisionprofile to embed.
#   VERSION            CFBundleShortVersionString to stamp (default 0.0.0).
set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="SWULabels"
GUI_TARGET="SWULabelsApp"
CLI_TARGET="swu-labels"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
PROVISION_PROFILE="${PROVISION_PROFILE:-}"
VERSION="${VERSION:-0.0.0}"
ENTITLEMENTS="$APP_NAME/$APP_NAME.entitlements"
INFO_PLIST_SRC="Resources/Info.plist"

# Content lives one level up, in the repository the TypeScript generator also
# reads. It is copied in rather than symlinked so the bundle is self-contained
# once moved off this machine.
CONTENT_ROOT=".."

BUILD_NUMBER="$(date +%Y%m%d%H%M 2>/dev/null || echo 1)"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
GUI_BIN="$BIN_PATH/$GUI_TARGET"
CLI_BIN="$BIN_PATH/$CLI_TARGET"

for binary in "$GUI_BIN" "$CLI_BIN"; do
	if [ ! -x "$binary" ]; then
		echo "✗ executable not found at $binary" >&2
		exit 1
	fi
done

# ---------------------------------------------------------------------------
# Assemble the bundle
# ---------------------------------------------------------------------------
echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The GUI is installed under the bundle name, which must match
# CFBundleExecutable; the SwiftPM target is named differently so the two
# executables can coexist in one package.
cp "$GUI_BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$CLI_BIN" "$APP/Contents/MacOS/$CLI_TARGET"

sed -e "s/__SHORT_VERSION__/$VERSION/g" \
    -e "s/__BUILD_VERSION__/$BUILD_NUMBER/g" \
    "$INFO_PLIST_SRC" > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Card data and icons. Both the GUI and the bundled CLI resolve content by
# looking here first, so a bundle copied to another machine still works.
echo "→ bundling content"
for content in assets data; do
	if [ ! -d "$CONTENT_ROOT/$content" ]; then
		echo "✗ missing $CONTENT_ROOT/$content — run from the app/ directory" >&2
		exit 1
	fi
	rm -rf "${APP:?}/Contents/Resources/$content"
	cp -R "$CONTENT_ROOT/$content" "$APP/Contents/Resources/$content"
done
# Snapshots carry a progress directory the generator writes at run time; it is
# not content and should not ship.
rm -rf "$APP/Contents/Resources/data/.progress"

for bundle in "$BIN_PATH"/*.bundle; do
	if [ -e "$bundle" ]; then
		cp -R "$bundle" "$APP/Contents/Resources/"
		echo "  bundled $(basename "$bundle")"
	fi
done

if [ -f "$BUILD_DIR/AppIcon.icns" ]; then
	cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
	echo "  (no $BUILD_DIR/AppIcon.icns — run 'make icon'; bundling without one)"
fi

if [ -n "$PROVISION_PROFILE" ] && [ -f "$PROVISION_PROFILE" ]; then
	cp "$PROVISION_PROFILE" "$APP/Contents/embedded.provisionprofile"
	echo "  embedded provisioning profile"
fi

# ---------------------------------------------------------------------------
# Codesign
# ---------------------------------------------------------------------------
# The nested CLI is signed first, then the bundle. Signing the bundle alone
# would leave the inner executable unsigned and the whole bundle invalid on a
# machine that checks.
sign_args=(--force --sign "$SIGN_IDENTITY")
if [ -f "$ENTITLEMENTS" ]; then
	sign_args+=(--entitlements "$ENTITLEMENTS")
fi

echo "→ codesign ($SIGN_IDENTITY)"
if ! codesign "${sign_args[@]}" "$APP/Contents/MacOS/$CLI_TARGET" 2>/dev/null; then
	echo "  identity '$SIGN_IDENTITY' unavailable — falling back to ad-hoc (-)"
	SIGN_IDENTITY="-"
	sign_args=(--force --sign "-")
	if [ -f "$ENTITLEMENTS" ]; then
		sign_args+=(--entitlements "$ENTITLEMENTS")
	fi
	codesign "${sign_args[@]}" "$APP/Contents/MacOS/$CLI_TARGET"
fi
codesign "${sign_args[@]}" "$APP"

codesign --verify --verbose=1 "$APP"
echo "✓ built $APP"
echo "  GUI: $APP/Contents/MacOS/$APP_NAME"
echo "  CLI: $APP/Contents/MacOS/$CLI_TARGET"
