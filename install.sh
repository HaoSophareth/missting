#!/bin/bash
# Missting installer — the single source of truth for how the app is installed.
# Every surface (README, landing page, release notes) points here via:
#   curl -fsSL https://raw.githubusercontent.com/HaoSophareth/missting/main/install.sh | bash
set -e

echo "Downloading the latest Missting..."
curl -fsSL https://github.com/HaoSophareth/missting/releases/latest/download/Missting.zip -o /tmp/Missting.zip

killall Missting 2>/dev/null || true
rm -rf /Applications/Missting.app
ditto -xk /tmp/Missting.zip /Applications
xattr -cr /Applications/Missting.app
rm -f /tmp/Missting.zip

open /Applications/Missting.app
echo "🌻 Missting installed! Look for the sunflower in your menu bar."
