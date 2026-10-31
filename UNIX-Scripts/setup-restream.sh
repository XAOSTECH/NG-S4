#!/usr/bin/env bash
# NG-S4 setup: install and configure the nginx + stunnel restream server.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 XAOSTECH. Licensed under the GNU GPL v3 or later.
# A commercial or separate licence is available on request from the owner.
set -u

error_exit() { echo "Error: $1" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || error_exit "This script must be run as root. Please use sudo."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ENV_DIR="$(cd "$SCRIPT_DIR/../real.env" 2>/dev/null && pwd)" \
    || error_exit "real.env not found. Copy example.env/* into real.env/ first."
MASTER_ENV="$REAL_ENV_DIR/master.env"
[[ -f "$MASTER_ENV" ]] || error_exit "master.env not found in $REAL_ENV_DIR."
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../example.env/master.env
. "$MASTER_ENV" || error_exit "Failed to source master.env"

# Fall back to the subnet of the default route when LAN_CIDR is left blank. The
# loopback that stunnel accepts on is always 127.0.0.1, so it needs no detection.
if [[ -z "${LAN_CIDR:-}" ]]; then
    LAN_CIDR="$(ip -4 route show 2>/dev/null | awk '/ src / && $1 ~ /\// {print $1; exit}')"
    [[ -n "$LAN_CIDR" ]] && echo "LAN_CIDR not set; using detected subnet $LAN_CIDR."
fi

for v in envDr scriptsDr NGINX_CONF_FILENAME STUNNEL_CONF_FILENAME NGINX_USER \
         NGINX_GROUP NGINX_WEB_ROOT HLS_BASE_DIR NGINX_HTTP_PORT LAN_CIDR LOG_DIR; do
    [[ -n "${!v:-}" ]] || error_exit "Essential variable '$v' is not set in master.env."
done

echo "Installing prerequisites (nginx, stunnel4, libnginx-mod-rtmp, ffmpeg, gphoto2)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || error_exit "Failed to update package lists."
apt-get install -y nginx libnginx-mod-rtmp stunnel4 ffmpeg gphoto2 \
    || error_exit "Failed to install prerequisites."

echo "Creating runtime and log directories..."
install -d -o "$NGINX_USER" -g "$NGINX_GROUP" /run/nginx /var/sock "$NGINX_WEB_ROOT" \
    "$HLS_BASE_DIR" "$HLS_BASE_DIR/ingest" "$LOG_DIR" || error_exit "Failed to create directories."
install -d -o stunnel4 -g stunnel4 /var/run/stunnel || error_exit "Failed to create stunnel runtime dir."
chmod 0755 "$HLS_BASE_DIR"

echo "Generating stunnel certificate..."
bash "$scriptsDr/generate-stunnel-cert.sh" || error_exit "Failed to generate stunnel certificate."

echo "Installing stunnel configuration..."
[[ -f "$envDr/$STUNNEL_CONF_FILENAME" ]] || error_exit "stunnel config not found in $envDr."
install -m 0644 "$envDr/$STUNNEL_CONF_FILENAME" /etc/stunnel/stunnel.conf \
    || error_exit "Failed to install stunnel.conf."
# Some distributions gate the service behind ENABLED=1 in /etc/default/stunnel4.
[[ -f /etc/default/stunnel4 ]] && sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4

echo "Rendering nginx configuration for this host..."
[[ -f "$envDr/$NGINX_CONF_FILENAME" ]] || error_exit "nginx config not found in $envDr."
sed -e "s|@@HTTP_PORT@@|${NGINX_HTTP_PORT}|g" \
    -e "s|@@LAN_CIDR@@|${LAN_CIDR}|g" \
    -e "s|@@HLS_BASE_DIR@@|${HLS_BASE_DIR}|g" \
    "$envDr/$NGINX_CONF_FILENAME" > /etc/nginx/nginx.conf \
    || error_exit "Failed to render nginx.conf."

# Install the RTMP statistics stylesheet when the module ships one.
for xsl in /usr/share/doc/libnginx-mod-rtmp/examples/stat.xsl \
           /usr/share/nginx/modules-available/stat.xsl; do
    [[ -f "$xsl" ]] && install -m 0644 "$xsl" "$NGINX_WEB_ROOT/stat.xsl" && break
done

echo "Installing the transcode engine..."
install -m 0755 "$scriptsDr/ng-s4-transcode.sh" /usr/local/bin/ng-s4-transcode.sh \
    || error_exit "Failed to install transcode engine."
cat > /etc/default/ng-s4 <<EOF
# Written by setup-restream.sh. Location of the live NG-S4 configuration.
NG_S4_MASTER_ENV="$MASTER_ENV"
EOF
chmod 0644 /etc/default/ng-s4

echo "Detecting encode hardware..."
add_group_if_present() {
    if getent group "$1" >/dev/null 2>&1; then
        usermod -aG "$1" "$NGINX_USER" && echo "  granted $NGINX_USER access to group '$1'"
    fi
}
if [[ -e /dev/nvidia0 ]] || command -v nvidia-smi >/dev/null 2>&1; then
    echo "  NVIDIA GPU detected: NVENC will be used."
    add_group_if_present video
    add_group_if_present render
elif [[ -e /dev/video11 ]] || grep -qi raspberry /proc/device-tree/model 2>/dev/null; then
    echo "  Raspberry Pi detected: V4L2 M2M will be used."
    add_group_if_present video
else
    echo "  No encode hardware detected: software encoding will be used."
fi

chown -R "$NGINX_USER":"$NGINX_GROUP" "$NGINX_WEB_ROOT" 2>/dev/null || true

echo "Validating nginx configuration..."
nginx -t || error_exit "nginx configuration test failed (see output above)."

start_or_restart() {
    if systemctl is-active --quiet "$1"; then
        systemctl restart "$1" || error_exit "Failed to restart $1."
    else
        systemctl enable "$1" >/dev/null 2>&1 || true
        systemctl start "$1" || error_exit "Failed to start $1."
    fi
}

# Report the process holding 127.0.0.1:<port> (name, pid, listen socket).
port_holder() { ss -ltnpH "sport = :$1" 2>/dev/null; }

# Terminate whatever still listens on a TCP port so a restart can bind it.
free_tcp_port() {
    local port="$1" pid n
    command -v ss >/dev/null 2>&1 || return 0
    for n in 1 2 3 4 5; do
        ss -ltnH "sport = :$port" 2>/dev/null | grep -q . || return 0
        pid="$(port_holder "$port" | grep -oE 'pid=[0-9]+' | head -n1 | cut -d= -f2)"
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
        sleep 0.3
    done
    pid="$(port_holder "$port" | grep -oE 'pid=[0-9]+' | head -n1 | cut -d= -f2)"
    [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
}

echo "Enabling and starting services..."
# Ubuntu's stunnel4 ships both an LSB service and a native stunnel@.service; a
# leftover or duplicate instance can keep holding the accept port and make the
# next start fail with "address already in use". Stop every variant, then free
# the configured accept ports (with consent) before starting one clean instance.
systemctl stop stunnel4 2>/dev/null || true
systemctl stop 'stunnel@*' 2>/dev/null || true

held_ports=()
if command -v ss >/dev/null 2>&1; then
    while IFS= read -r _port; do
        [[ -n "$_port" ]] || continue
        ss -ltnH "sport = :$_port" 2>/dev/null | grep -q . && held_ports+=("$_port")
    done < <(grep -oE '^[[:space:]]*accept[[:space:]]*=[[:space:]]*[0-9.]+:[0-9]+' /etc/stunnel/stunnel.conf 2>/dev/null | grep -oE '[0-9]+$')
fi

if [[ ${#held_ports[@]} -gt 0 ]]; then
    echo "These stunnel accept ports are already in use by another process:"
    for _port in "${held_ports[@]}"; do
        echo "  - port $_port:"
        port_holder "$_port" | sed 's/^/      /'
    done
    _free=0
    if [[ "${NG_S4_FORCE_FREE:-0}" == "1" ]]; then
        _free=1; echo "NG_S4_FORCE_FREE=1 set: freeing without prompting."
    elif [[ -t 0 ]]; then
        read -r -p "Terminate the above processes and free the ports? [y/N] " _ans
        case "$_ans" in [Yy]*) _free=1;; esac
    else
        echo "Non-interactive shell; set NG_S4_FORCE_FREE=1 to free automatically."
    fi
    if [[ "$_free" == "1" ]]; then
        for _port in "${held_ports[@]}"; do free_tcp_port "$_port"; done
    else
        echo "Leaving the ports in place; stunnel may fail to bind."
    fi
fi

systemctl enable stunnel4 >/dev/null 2>&1 || true
systemctl start stunnel4 || error_exit "Failed to start stunnel4 (see: journalctl -xeu stunnel4)."
start_or_restart nginx

echo
echo "Setup complete."
echo "  Publish:  rtmp://<this-host>:1935/${INGEST_APP:-ingest}/live"
echo "  Preview:  http://<this-host>:${NGINX_HTTP_PORT}/hls/ingest/live/index.m3u8"
echo "  Stats:    http://<this-host>:${NGINX_HTTP_PORT}/stat"
echo "  Health:   http://<this-host>:${NGINX_HTTP_PORT}/healthz"
echo "Run 'UNIX-Scripts/ng-s4-doctor.sh' to verify encode capabilities."
exit 0
