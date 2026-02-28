#!/usr/bin/env bash
# Generates SSL certificate for stunnel
set -e
error_exit() {
    echo "Error: $1" >&2
    exit 1
}
SCRIPT_DIR_CERT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ENV_DIR_CERT="$(cd "$SCRIPT_DIR_CERT/../real.env" && pwd)"
MASTER_ENV_PATH="$REAL_ENV_DIR_CERT/master.env"
if [ ! -f "$MASTER_ENV_PATH" ]; then
    error_exit "master.env not found at $MASTER_ENV_PATH"
fi
. "$MASTER_ENV_PATH" || error_exit "Failed to source $MASTER_ENV_PATH"
if [ -z "$STUNNEL_SSL_SUBJECT" ]; then
    error_exit "STUNNEL_SSL_SUBJECT is not set in master.env. Please define it (e.g., /C=US/ST=CA/L=City/O=Org/CN=yourdomain.com)."
fi
echo "Generating stunnel SSL certificate..."
sudo mkdir -p /etc/stunnel
KEY_FILE_TMP="/etc/stunnel/stunnel.key.tmp"
CERT_CRT_FILE_TMP="/etc/stunnel/stunnel.crt.tmp"
CERT_FILE_FINAL="/etc/stunnel/stunnel.pem"
if [ -f "$CERT_FILE_FINAL" ]; then
    echo "Backing up existing $CERT_FILE_FINAL to $CERT_FILE_FINAL.bak"
    sudo cp "$CERT_FILE_FINAL" "$CERT_FILE_FINAL.bak" || error_exit "Failed to backup existing certificate."
fi
echo "Generating private key and certificate for subject: $STUNNEL_SSL_SUBJECT"
sudo openssl genpkey -algorithm RSA -out "$KEY_FILE_TMP" -pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1 || error_exit "Error generating private key"
sudo openssl req -new -x509 -key "$KEY_FILE_TMP" -out "$CERT_CRT_FILE_TMP" -days 365 -subj "$STUNNEL_SSL_SUBJECT" >/dev/null 2>&1 || error_exit "Error generating certificate"
sudo cat "$KEY_FILE_TMP" "$CERT_CRT_FILE_TMP" > "$CERT_FILE_FINAL" || error_exit "Error combining key and certificate"
sudo rm -f "$KEY_FILE_TMP" "$CERT_CRT_FILE_TMP"
sudo chmod 600 "$CERT_FILE_FINAL"
sudo mkdir -p /var/run/stunnel
if id "stunnel4" &>/dev/null; then
    sudo chown -R stunnel4:stunnel4 /var/run/stunnel
fi
echo "Stunnel SSL certificate generated successfully at $CERT_FILE_FINAL"
