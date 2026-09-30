#!/usr/bin/env bash
# NG-S4 reset: stop services, purge packages and remove installed files.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
set -u

error_exit() { echo "Error: $1" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || error_exit "This script must be run as root. Please use sudo."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ENV_DIR="$(cd "$SCRIPT_DIR/../real.env" 2>/dev/null && pwd || true)"
MASTER_ENV="${REAL_ENV_DIR:+$REAL_ENV_DIR/master.env}"
if [[ -n "$MASTER_ENV" && -f "$MASTER_ENV" ]]; then
    # shellcheck source=/dev/null
    . "$MASTER_ENV" || echo "Warning: failed to source master.env; using defaults."
fi
LOG_DIR_ACTUAL="${LOG_DIR:-/var/log/ng-s4}"
HLS_BASE_DIR_ACTUAL="${HLS_BASE_DIR:-/mnt/hls}"
NGINX_WEB_ROOT_ACTUAL="${NGINX_WEB_ROOT:-/var/www/html}"

mkdir -p "$LOG_DIR_ACTUAL" 2>/dev/null || LOG_DIR_ACTUAL="/tmp"
LOG_FILE="$LOG_DIR_ACTUAL/reset-restream_$(date '+%Y-%m-%d_%H-%M-%S').log"
exec > >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "Stopping services and any running transcode jobs..."
pkill -f /usr/local/bin/ng-s4-transcode.sh 2>/dev/null || true
systemctl stop nginx 2>/dev/null || echo "nginx not running."
systemctl stop stunnel4 2>/dev/null || echo "stunnel4 not running."

echo "Removing installed NG-S4 files..."
rm -f /usr/local/bin/ng-s4-transcode.sh /etc/default/ng-s4

echo "Purging nginx and stunnel4 packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get remove -y --purge nginx nginx-full nginx-common libnginx-mod-rtmp stunnel4 \
    || echo "Warning: some packages were not installed."
apt-get autoremove -y || true
apt-get autoclean -y || true

echo "Removing configuration and runtime directories..."
for d in /etc/nginx /etc/stunnel /var/log/nginx /var/log/stunnel4 \
         /run/nginx /run/stunnel4 /var/run/stunnel; do
    rm -rf "$d" 2>/dev/null || true
done
rm -f "$NGINX_WEB_ROOT_ACTUAL/stat.xsl" 2>/dev/null || true

if [[ -n "$HLS_BASE_DIR_ACTUAL" && -d "$HLS_BASE_DIR_ACTUAL" \
      && "$HLS_BASE_DIR_ACTUAL" != "/" && "$HLS_BASE_DIR_ACTUAL" != "/mnt" ]]; then
    echo "Removing HLS directory: $HLS_BASE_DIR_ACTUAL"
    rm -rf "$HLS_BASE_DIR_ACTUAL"
fi

echo "Reset complete. Re-run setup-restream.sh for a fresh installation."
echo "Transcode and reset logs are kept in: $LOG_DIR_ACTUAL"
echo "Log file for this session: $LOG_FILE"
exit 0
