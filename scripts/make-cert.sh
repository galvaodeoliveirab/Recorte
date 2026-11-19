#!/bin/bash
# Cria um certificado local "Recorte Dev" para assinar o app.
# Assim a permissão de Gravação de Tela continua valendo entre builds.
set -euo pipefail
NAME="Recorte Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "Certificado já existe"; exit 0; fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cfg" <<CFG
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
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/cfg" -keyout "$T/key.pem" -out "$T/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -out "$T/c.p12" -passout pass:recorte -name "$NAME"
security import "$T/c.p12" -k ~/Library/Keychains/login.keychain-db -P recorte -T /usr/bin/codesign
echo "Certificado criado"
