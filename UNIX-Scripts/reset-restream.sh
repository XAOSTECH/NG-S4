#!/usr/bin/env bash
# Reset Nginx and Stunnel4 installation
error_exit() {
    echo "Error: $1" >&2
    exit 1
}
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root. Please use sudo."
fi
SCRIPT_DIR_RESET="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ENV_DIR_RESET="$(cd "$SCRIPT_DIR_RESET/../real.env" && pwd)"
MASTER_ENV_PATH_RESET="$REAL_ENV_DIR_RESET/master.env"
LOG_DIR_DEFAULT="$SCRIPT_DIR_RESET/logs"
if [ ! -f "$MASTER_ENV_PATH_RESET" ]; then
    echo "Warning: master.env not found in $REAL_ENV_DIR_RESET. Using default log directory: $LOG_DIR_DEFAULT"
    LOG_DIR_ACTUAL="$LOG_DIR_DEFAULT"
else
    . "$MASTER_ENV_PATH_RESET" || echo "Warning: Failed to source $MASTER_ENV_PATH_RESET. Some variables may not be set."
    LOG_DIR_ACTUAL="${LOG_DIR:-$LOG_DIR_DEFAULT}"
fi
LOG_FILE="$LOG_DIR_ACTUAL/reset-restream_$(date '+%Y-%m-%d_%H-%M-%S').log"
mkdir -p "$LOG_DIR_ACTUAL" || error_exit "Failed to create log directory: $LOG_DIR_ACTUAL"
exec > >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)
echo "Starting Nginx and Stunnel4 reset process..."
echo "Stopping Nginx and Stunnel4 services..."
systemctl stop nginx >/dev/null 2>&1 || echo "Nginx not running or failed to stop."
killall nginx >/dev/null 2>&1 || true
systemctl stop stunnel4 >/dev/null 2>&1 || echo "Stunnel4 not running or failed to stop."
killall stunnel4 >/dev/null 2>&1 || true
echo "Removing Nginx and Stunnel4 packages (purge)..."
apt-get remove -y --purge nginx nginx-full nginx-common libnginx-mod-rtmp stunnel4 || echo "Warning: Failed to remove some packages. They might not have been installed."
apt-get autoremove -y || echo "Warning: Failed during autoremove."
apt-get autoclean -y || echo "Warning: Failed during autoclean."
echo "Removing configuration files and directories..."
rm -rf /etc/nginx || echo "Warning: Failed to remove /etc/nginx."
rm -rf /etc/stunnel || echo "Warning: Failed to remove /etc/stunnel."
rm -rf /var/log/nginx || echo "Warning: Failed to remove /var/log/nginx."
rm -rf /var/log/stunnel4 || echo "Warning: Failed to remove /var/log/stunnel4."
rm -rf /run/nginx || echo "Warning: Failed to remove /run/nginx."
rm -rf /run/stunnel4 || echo "Warning: Failed to remove /run/stunnel4."
rm -rf /var/run/stunnel || echo "Warning: Failed to remove /var/run/stunnel."
NGINX_WEB_ROOT_ACTUAL=${NGINX_WEB_ROOT:-/var/www/html}
HLS_BASE_DIR_ACTUAL=${HLS_BASE_DIR:-/mnt/hls}
if [ -d "$NGINX_WEB_ROOT_ACTUAL/NGINX" ]; then
    echo "Removing Nginx web content directory: $NGINX_WEB_ROOT_ACTUAL/NGINX"
    rm -rf "$NGINX_WEB_ROOT_ACTUAL/NGINX"
fi
if [ -n "$HLS_BASE_DIR_ACTUAL" ] && [ -d "$HLS_BASE_DIR_ACTUAL" ] && [ "$HLS_BASE_DIR_ACTUAL" != "/mnt" ] && [ "$HLS_BASE_DIR_ACTUAL" != "/" ]; then
    echo "Removing HLS base directory: $HLS_BASE_DIR_ACTUAL"
    rm -rf "$HLS_BASE_DIR_ACTUAL"
fi
echo "Reset process completed."
echo "If you wish to reinstall, you can now run the setup-restream.sh script."
echo "Log file for this session: $LOG_FILE"
exit 0
