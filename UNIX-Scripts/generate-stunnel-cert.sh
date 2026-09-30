#!/usr/bin/env bash
# Generate the self signed certificate used by stunnel for the RTMPS tunnels.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
set -eu

error_exit() { echo "Error: $1" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || error_exit "This script must be run as root. Please use sudo."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ENV_DIR="$(cd "$SCRIPT_DIR/../real.env" 2>/dev/null && pwd)" \
    || error_exit "real.env not found. Copy example.env/* into real.env/ first."
MASTER_ENV="$REAL_ENV_DIR/master.env"
[[ -f "$MASTER_ENV" ]] || error_exit "master.env not found at $MASTER_ENV"
# shellcheck source=/dev/null
. "$MASTER_ENV" || error_exit "Failed to source $MASTER_ENV"

[[ -n "${STUNNEL_SSL_SUBJECT:-}" ]] \
    || error_exit "STUNNEL_SSL_SUBJECT is not set in master.env (e.g. /C=GB/ST=England/L=London/O=NG-S4/CN=ng-s4.local)."

CERT_FINAL="/etc/stunnel/stunnel.pem"
KEY_TMP="$(mktemp)"; CRT_TMP="$(mktemp)"
trap 'rm -f "$KEY_TMP" "$CRT_TMP"' EXIT

mkdir -p /etc/stunnel
if [[ -f "$CERT_FINAL" ]]; then
    cp "$CERT_FINAL" "$CERT_FINAL.bak" || error_exit "Failed to back up existing certificate."
    echo "Backed up existing certificate to $CERT_FINAL.bak"
fi

echo "Generating key and certificate for: $STUNNEL_SSL_SUBJECT"
openssl genpkey -algorithm RSA -out "$KEY_TMP" -pkeyopt rsa_keygen_bits:2048 >/dev/null 2>&1 \
    || error_exit "Error generating private key."
openssl req -new -x509 -key "$KEY_TMP" -out "$CRT_TMP" -days 825 -subj "$STUNNEL_SSL_SUBJECT" >/dev/null 2>&1 \
    || error_exit "Error generating certificate."
cat "$KEY_TMP" "$CRT_TMP" > "$CERT_FINAL" || error_exit "Error writing $CERT_FINAL."
chmod 600 "$CERT_FINAL"

mkdir -p /var/run/stunnel
id stunnel4 >/dev/null 2>&1 && chown -R stunnel4:stunnel4 /var/run/stunnel
echo "Stunnel certificate written to $CERT_FINAL"
