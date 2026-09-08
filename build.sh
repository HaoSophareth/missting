#!/bin/bash
set -e

APPNAME="Missting"
BUNDLE="$APPNAME.app"

echo "Building $APPNAME..."
if [ "${UNIVERSAL:-0}" = "1" ]; then
  # Universal binary for releases (Intel + Apple Silicon)
  swift build -c release --arch arm64 --arch x86_64
  BINDIR=".build/apple/Products/Release"
else
  swift build -c release
  BINDIR=".build/release"
fi

echo "Creating .app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINDIR/$APPNAME" "$BUNDLE/Contents/MacOS/$APPNAME"
cp "Info.plist" "$BUNDLE/Contents/Info.plist"

if [ "${UNIVERSAL:-0}" != "1" ]; then
  # Local dev builds never bump their own version number the way a tagged
  # release does (only the CI release workflow stamps that, from the git
  # tag), so a fresh local build always reports itself as older than
  # whatever's actually published. With SUAutomaticallyUpdate on, Sparkle
  # will silently replace a local test build with the real public release
  # mid-session otherwise. Disable checks on this local copy only — the
  # committed Info.plist, and every CI release (which stamps its own
  # version before this script even runs), are untouched.
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$BUNDLE/Contents/Info.plist"
fi
cp "Resources/alarm-clock.png" "$BUNDLE/Contents/Resources/alarm-clock.png"
cp "Resources/sunflower.png" "$BUNDLE/Contents/Resources/sunflower.png"
cp "Resources/sunflower-gray.png" "$BUNDLE/Contents/Resources/sunflower-gray.png"
cp "Resources/Missting.icns" "$BUNDLE/Contents/Resources/Missting.icns"
cp "Resources/menu-bar-drag.mp4" "$BUNDLE/Contents/Resources/menu-bar-drag.mp4"

# Embed Sparkle.framework (the executable links it via @rpath ../Frameworks)
echo "Embedding Sparkle.framework..."
FRAMEWORK_SRC="$BINDIR/Sparkle.framework"
if [ ! -d "$FRAMEWORK_SRC" ]; then
  FRAMEWORK_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
mkdir -p "$BUNDLE/Contents/Frameworks"
cp -R "$FRAMEWORK_SRC" "$BUNDLE/Contents/Frameworks/"

# Sign with a stable local identity when available so the Keychain doesn't
# treat every rebuild as a new app (ad-hoc signatures change per-build and
# retrigger the "wants to use your confidential information" prompt).
# Falls back to ad-hoc, matching prior behavior, when no such identity exists (e.g. in CI).
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development:[^"]*"' | tr -d '"')
if [ -n "$IDENTITY" ]; then
  codesign --force --deep -s "$IDENTITY" "$BUNDLE"
else
  codesign --force --deep -s - "$BUNDLE" 2>/dev/null
fi

echo "Done! Open $BUNDLE to launch the app."
echo ""
echo "To install: cp -r $BUNDLE /Applications/"
