#!/usr/bin/env bash
# Main setup script for Nginx + Stunnel4 Restreaming
error_exit() {
    echo "Error: $1" >&2
    exit 1
}
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root. Please use sudo."
fi
SCRIPT_DIR_SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ENV_DIR_SETUP="$(cd "$SCRIPT_DIR_SETUP/../real.env" && pwd)"
if [ ! -f "$REAL_ENV_DIR_SETUP/master.env" ]; then
    error_exit "master.env not found in $REAL_ENV_DIR_SETUP. Please ensure it exists."
fi
. "$REAL_ENV_DIR_SETUP/master.env" || error_exit "Failed to source master.env"
if [ -z "$envDr" ] || [ -z "$scriptsDr" ] || [ -z "$NGINX_CONF_FILENAME" ] || [ -z "$STUNNEL_CONF_FILENAME" ] || [ -z "$NGINX_USER" ] || [ -z "$HLS_BASE_DIR" ]; then
    error_exit "Essential variables (envDr, scriptsDr, NGINX_CONF_FILENAME, STUNNEL_CONF_FILENAME, NGINX_USER, HLS_BASE_DIR) are not set in master.env."
fi
if [ "$envDr" != "$REAL_ENV_DIR_SETUP" ]; then
    echo "Warning: envDr in master.env ($envDr) does not match expected location ($REAL_ENV_DIR_SETUP)."
fi
echo "Starting Restreaming Server Setup..."
echo "Using configuration from: $envDr"
echo "Scripts directory: $scriptsDr"
echo "Updating package lists and installing prerequisites (nginx, stunnel4, libnginx-mod-rtmp, ffmpeg, gphoto2)..."
apt-get update -y || error_exit "Failed to update package lists."
apt-get install -y nginx stunnel4 libnginx-mod-rtmp ffmpeg gphoto2 || error_exit "Failed to install prerequisites."
echo "Creating directories..."
mkdir -p /run/nginx || error_exit "Failed to create /run/nginx"
chown "$NGINX_USER":"$NGINX_GROUP" /run/nginx || error_exit "Failed to set ownership for /run/nginx"
mkdir -p /var/run/stunnel || error_exit "Failed to create /var/run/stunnel"
chown stunnel4:stunnel4 /var/run/stunnel || error_exit "Failed to set ownership for /var/run/stunnel"
mkdir -p /var/sock || error_exit "Failed to create /var/sock"
chown "$NGINX_USER":"$NGINX_GROUP" /var/sock || error_exit "Failed to set ownership for /var/sock"
mkdir -p "$NGINX_WEB_ROOT" || error_exit "Failed to create Nginx web root $NGINX_WEB_ROOT"
if [ -n "$HLS_BASE_DIR" ]; then
    mkdir -p "$HLS_BASE_DIR/$APP_MAIN_STREAM" || error_exit "Failed to create HLS directory $HLS_BASE_DIR/$APP_MAIN_STREAM"
    mkdir -p "$HLS_BASE_DIR/$APP_SHORTS_COMBINED" || error_exit "Failed to create HLS directory $HLS_BASE_DIR/$APP_SHORTS_COMBINED"
    chown -R "$NGINX_USER":"$NGINX_GROUP" "$HLS_BASE_DIR" || error_exit "Failed to set ownership for $HLS_BASE_DIR"
    chmod -R 755 "$HLS_BASE_DIR" || error_exit "Failed to set permissions for $HLS_BASE_DIR"
fi
echo "Generating Stunnel SSL certificate..."
if [ ! -f "$scriptsDr/generate-stunnel-cert.sh" ]; then
    error_exit "generate-stunnel-cert.sh not found in $scriptsDr"
fi
bash "$scriptsDr/generate-stunnel-cert.sh" || error_exit "Failed to generate stunnel certificate."
echo "Configuring Stunnel..."
if [ ! -f "$envDr/$STUNNEL_CONF_FILENAME" ]; then
    error_exit "Stunnel configuration ($envDr/$STUNNEL_CONF_FILENAME) not found."
fi
cp -f "$envDr/$STUNNEL_CONF_FILENAME" "/etc/stunnel/stunnel.conf" || error_exit "Failed to copy stunnel.conf."
echo "Configuring Nginx..."
if [ ! -f "$envDr/$NGINX_CONF_FILENAME" ]; then
    error_exit "Nginx configuration ($envDr/$NGINX_CONF_FILENAME) not found."
fi
cp -f "$envDr/$NGINX_CONF_FILENAME" "/etc/nginx/nginx.conf" || error_exit "Failed to copy nginx.conf."
echo "Setting permissions for web and HLS directories..."
if [ -d "$NGINX_WEB_ROOT" ]; then
    chown -R "$NGINX_USER":"$NGINX_GROUP" "$NGINX_WEB_ROOT" || error_exit "Failed to set ownership for Nginx web root."
    chmod -R 755 "$NGINX_WEB_ROOT" || error_exit "Failed to set permissions for Nginx web root."
fi
echo "Enabling and starting Stunnel4 and Nginx services..."
if systemctl is-active --quiet stunnel4; then
    systemctl restart stunnel4 || error_exit "Failed to restart stunnel4."
else
    systemctl enable stunnel4 || error_exit "Failed to enable stunnel4."
    systemctl start stunnel4 || error_exit "Failed to start stunnel4."
fi
if systemctl is-active --quiet nginx; then
    systemctl restart nginx || error_exit "Failed to restart nginx."
else
    systemctl enable nginx || error_exit "Failed to enable nginx."
    systemctl start nginx || error_exit "Failed to start nginx."
fi
echo "Setup complete!"
echo "Nginx and Stunnel4 should now be running."
echo "Use manage-services.sh to check status, stop, or restart services."
exit 0
