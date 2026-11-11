#!/bin/bash
# One-time setup: creates a personal code-signing certificate for ClipTyper builds.
#
#   ./setup-signing.sh
#
# Why: macOS ties the Accessibility permission to the app's signing identity. Without a
# certificate every build counts as a new app and the permission has to be granted again.
# With this certificate, ./build.sh signs every build the same way and the permission stays.
#
# The certificate is self-signed, stored in your login keychain, and only good for signing
# apps on this Mac. Nothing is sent anywhere. To remove it later, delete "ClipTyper Local"
# in the Keychain Access app.
set -euo pipefail

NAME="${CLIPTYPER_SIGN_IDENTITY:-ClipTyper Local}"
# The two settings below exist for automated checks; normally leave them alone.
KEYCHAIN="${CLIPTYPER_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
KEYCHAIN_PASSWORD="${CLIPTYPER_KEYCHAIN_PASSWORD:-}"

has_identity() {
    local found
    found="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null || true)"
    [[ "$found" == *"\"$NAME\""* ]]
}

if has_identity; then
    echo "The certificate \"$NAME\" already exists. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/certificate.conf" <<EOF
[ req ]
distinguished_name = subject
x509_extensions = extensions
prompt = no

[ subject ]
CN = $NAME

[ extensions ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# /usr/bin/openssl is the copy that ships with macOS; its files import cleanly into the keychain.
echo "Creating the certificate \"$NAME\"..."
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/certificate.conf" \
    -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null

# The password only protects the temporary file on its way into the keychain.
TRANSFER_PASSWORD="cliptyper"
/usr/bin/openssl pkcs12 -export \
    -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$TRANSFER_PASSWORD"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TRANSFER_PASSWORD" \
    -T /usr/bin/codesign >/dev/null

if [ -n "$KEYCHAIN_PASSWORD" ]; then
    # Lets codesign use the key without a prompt (needed where nobody can click "Allow").
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
fi

if ! has_identity; then
    echo "The certificate was created but macOS does not list it for code signing." >&2
    echo "Create it by hand instead: see \"Keeping the permission across rebuilds\" in README.md." >&2
    exit 1
fi

echo
echo "Done. Now run ./build.sh"
echo
echo "During that build macOS asks whether \"codesign\" may use the key \"$NAME\"."
echo "Enter your Mac login password and click \"Always Allow\"."
echo "Then allow ClipTyper under Accessibility one last time; later builds keep the permission."
