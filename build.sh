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
cp "Resources/alarm-clock.png" "$BUNDLE/Contents/Resources/alarm-clock.png"
cp "Resources/sunflower.png" "$BUNDLE/Contents/Resources/sunflower.png"
cp "Resources/sunflower-gray.png" "$BUNDLE/Contents/Resources/sunflower-gray.png"
cp "Resources/Missting.icns" "$BUNDLE/Contents/Resources/Missting.icns"

# Embed Sparkle.framework (the executable links it via @rpath ../Frameworks)
echo "Embedding Sparkle.framework..."
FRAMEWORK_SRC="$BINDIR/Sparkle.framework"
if [ ! -d "$FRAMEWORK_SRC" ]; then
  FRAMEWORK_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
mkdir -p "$BUNDLE/Contents/Frameworks"
cp -R "$FRAMEWORK_SRC" "$BUNDLE/Contents/Frameworks/"

# Ad-hoc sign so the bundle is coherent for Sparkle's installer
codesign --force --deep -s - "$BUNDLE" 2>/dev/null

echo "Done! Open $BUNDLE to launch the app."
echo ""
echo "To install: cp -r $BUNDLE /Applications/"
