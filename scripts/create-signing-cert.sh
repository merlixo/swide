#!/bin/bash
# Creates a self-signed code signing certificate in the login keychain, once.
# Signing every build with it keeps macOS permissions (Accessibility, Screen
# Recording) across rebuilds; ad hoc signatures change with every build.
set -euo pipefail

NAME="Swide Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "'$NAME' already exists."
    exit 0
fi

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT

cat > "$DIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/cert.cnf" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
    -out "$DIR/cert.p12" -passout pass:swide 2>/dev/null \
  || openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
    -out "$DIR/cert.p12" -passout pass:swide
security import "$DIR/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P swide -T /usr/bin/codesign

echo "Created '$NAME'. Rebuild with scripts/build.sh install."
