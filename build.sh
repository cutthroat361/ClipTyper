#!/bin/bash
# Builds ClipTyper and installs it into /Applications.
#
#   ./build.sh          build, install into /Applications, start the app
#   ./build.sh --zip    also write dist/ClipTyper-<version>.zip (for a GitHub release)
#
# Needs Xcode Command Line Tools:  xcode-select --install
#
# The app is built and signed in a temporary folder, not next to this script, because
# iCloud-synced folders (Desktop, Documents) attach Finder metadata that codesign rejects.
set -euo pipefail
cd "$(dirname "$0")"

NAME="ClipTyper"
VERSION="1.0.0"
BUNDLE_ID="local.cliptyper"
DEST="/Applications/$NAME.app"

# Optional: a code-signing certificate with this name keeps the Accessibility permission
# across rebuilds (see README, "Keeping the permission across rebuilds").
# Without it the app is ad-hoc signed and the permission must be re-added after each build.
SIGN_IDENTITY="${CLIPTYPER_SIGN_IDENTITY:-ClipTyper Local}"

MAKE_ZIP=0
if [ "${1:-}" = "--zip" ]; then
    MAKE_ZIP=1
fi

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found. Run: xcode-select --install" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling..."
swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos13.0" \
    -o "$APP/Contents/MacOS/$NAME" \
    ClipTyper.swift

cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

xattr -cr "$APP"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    echo "Signing with certificate \"$SIGN_IDENTITY\""
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
    SIGNED_WITH_CERT=1
else
    codesign --force --sign - "$APP"
    SIGNED_WITH_CERT=0
fi

if [ "$MAKE_ZIP" = "1" ]; then
    mkdir -p dist
    ZIP="dist/$NAME-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Wrote $ZIP"
fi

# Quit a running copy, replace the installed app, start the new one.
pkill -x "$NAME" 2>/dev/null || true
rm -rf "$DEST"
mv "$APP" "$DEST"
open "$DEST"

echo
echo "Installed and started $DEST (version $VERSION)"
echo "First install: allow ClipTyper under"
echo "  System Settings > Privacy & Security > Accessibility."
if [ "$SIGNED_WITH_CERT" = "0" ]; then
    echo "After a rebuild: remove the old ClipTyper entry there (minus button) and add it again."
fi
