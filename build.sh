#!/bin/bash
# Builds ClipTyper.
#
#   ./build.sh               build, install into /Applications and start the app
#   ./build.sh --zip         also write dist/ClipTyper-<version>.zip
#   ./build.sh --no-install  build only (use with --zip); nothing on this Mac is changed
#   ./build.sh --native      build for this Mac's processor only (faster, not for sharing)
#
# Needs the Xcode Command Line Tools:  xcode-select --install
#
# The version number comes from the VERSION file.
# Run ./setup-signing.sh once to keep the Accessibility permission across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

NAME="ClipTyper"
BUNDLE_ID="local.cliptyper"
MIN_MACOS="13.0"
DEST="/Applications/$NAME.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
# Certificate created by ./setup-signing.sh. Without it the app is ad-hoc signed.
SIGN_IDENTITY="${CLIPTYPER_SIGN_IDENTITY:-ClipTyper Local}"

MAKE_ZIP=0
INSTALL=1
UNIVERSAL=1
while [ $# -gt 0 ]; do
    case "$1" in
        --zip) MAKE_ZIP=1 ;;
        --no-install) INSTALL=0 ;;
        --native) UNIVERSAL=0 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
    esac
    shift
done

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found. Run: xcode-select --install" >&2
    exit 1
fi

# Build and sign in a temporary folder, not next to this script: iCloud-synced folders
# (Desktop, Documents) attach Finder metadata that codesign rejects.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() {   # compile <architecture> <output file>
    swiftc -O -swift-version 5 -module-name "$NAME" \
        -target "$1-apple-macos$MIN_MACOS" \
        -o "$2" \
        Sources/ClipTyper/*.swift
}

NATIVE_ARCH="$(uname -m)"
if [ "$NATIVE_ARCH" = "arm64" ]; then OTHER_ARCH="x86_64"; else OTHER_ARCH="arm64"; fi

echo "Compiling ClipTyper $VERSION ($NATIVE_ARCH)..."
compile "$NATIVE_ARCH" "$WORK/$NAME-$NATIVE_ARCH"
BINARY="$WORK/$NAME-$NATIVE_ARCH"
BUILT_FOR="$NATIVE_ARCH only"

if [ "$UNIVERSAL" = "1" ]; then
    # Second half of a universal app, so the same download runs on Intel and Apple silicon.
    echo "Compiling ClipTyper $VERSION ($OTHER_ARCH)..."
    if compile "$OTHER_ARCH" "$WORK/$NAME-$OTHER_ARCH" 2> "$WORK/other-arch.log"; then
        lipo -create -output "$WORK/$NAME-universal" \
            "$WORK/$NAME-$NATIVE_ARCH" "$WORK/$NAME-$OTHER_ARCH"
        BINARY="$WORK/$NAME-universal"
        BUILT_FOR="universal: Apple silicon and Intel"
    else
        echo "Note: the $OTHER_ARCH half did not build, so this app runs on $NATIVE_ARCH Macs only:"
        tail -n 5 "$WORK/other-arch.log" | sed 's/^/    /'
    fi
fi

cp "$BINARY" "$APP/Contents/MacOS/$NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

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
    <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# --- Sign ---------------------------------------------------------------------------------
# With the local certificate the app keeps the same identity on every build, so macOS keeps
# its Accessibility permission. Ad-hoc signing gives every build a new identity.
xattr -cr "$APP"
SIGNED_WITH="ad-hoc signature"
IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
if [[ "$IDENTITIES" == *"\"$SIGN_IDENTITY\""* ]]; then
    if codesign --force --sign "$SIGN_IDENTITY" "$APP"; then
        SIGNED_WITH="certificate \"$SIGN_IDENTITY\""
    else
        echo "Signing with \"$SIGN_IDENTITY\" failed; using an ad-hoc signature instead."
    fi
fi
if [ "$SIGNED_WITH" = "ad-hoc signature" ]; then
    codesign --force --sign - "$APP"
fi

echo
echo "Built $NAME $VERSION ($BUILT_FOR), signed with $SIGNED_WITH."

# --- Zip ----------------------------------------------------------------------------------
if [ "$MAKE_ZIP" = "1" ]; then
    mkdir -p dist
    ZIP="dist/$NAME-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Wrote $ZIP"
fi

if [ "$INSTALL" = "0" ]; then
    exit 0
fi

# --- Install ------------------------------------------------------------------------------
# macOS ties the Accessibility permission to the app's signing identity. Compare the identity
# of the installed copy with the new one to know whether the permission carries over.
signing_identity() {
    codesign -d -r- "$1" 2>/dev/null | grep 'designated' || true
}
OLD_IDENTITY=""
if [ -d "$DEST" ]; then
    OLD_IDENTITY="$(signing_identity "$DEST")"
fi
NEW_IDENTITY="$(signing_identity "$APP")"

pkill -x "$NAME" 2>/dev/null || true
rm -rf "$DEST"
mv "$APP" "$DEST"

if [ -n "$NEW_IDENTITY" ] && [ "$NEW_IDENTITY" = "$OLD_IDENTITY" ]; then
    open "$DEST"
    echo "Installed and started $DEST. The Accessibility permission carries over."
else
    # The old permission entry no longer matches this build. Remove it, so that macOS asks
    # again and one switch in System Settings is all it takes.
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    open "$DEST"
    echo "Installed and started $DEST."
    echo "Allow ClipTyper under System Settings > Privacy & Security > Accessibility."
    echo "(If it is already listed there but does not work, remove it with the minus button and add it again.)"
    if [ "$SIGNED_WITH" = "ad-hoc signature" ]; then
        echo "To stop macOS asking after every rebuild, run ./setup-signing.sh once."
    fi
fi
