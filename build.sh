#!/bin/bash
set -e

APPNAME="Missting"
BUNDLE="$APPNAME.app"

echo "Building $APPNAME..."
swift build -c release

echo "Creating .app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp ".build/release/$APPNAME" "$BUNDLE/Contents/MacOS/$APPNAME"
cp "Info.plist" "$BUNDLE/Contents/Info.plist"
cp "Resources/alarm-clock.png" "$BUNDLE/Contents/Resources/alarm-clock.png"
cp "Resources/sunflower.png" "$BUNDLE/Contents/Resources/sunflower.png"
cp "Resources/Missting.icns" "$BUNDLE/Contents/Resources/Missting.icns"

echo "Done! Open $BUNDLE to launch the app."
echo ""
echo "To install: cp -r $BUNDLE /Applications/"
