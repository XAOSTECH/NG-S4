#!/usr/bin/env bash
# Manage Nginx and Stunnel4 services
error_exit() {
    echo "Error: $1" >&2
}
if [ -z "$1" ]; then
    echo "Usage: sudo $0 {start|stop|restart|status|enable|disable} [nginx|stunnel4|all]"
    echo "Example: sudo $0 start all"
    echo "Example: sudo $0 status nginx"
    exit 1
fi
ACTION=$1
SERVICE=${2:-all}
perform_action() {
    local service_name=$1
    local action_cmd=$2
    echo "Performing '$action_cmd' on '$service_name'..."
    case $action_cmd in
        start|stop|restart|status|enable|disable)
            if systemctl is-active --quiet "$service_name" && [ "$action_cmd" == "start" ]; then
                echo "$service_name is already running."
                return
            elif ! systemctl is-active --quiet "$service_name" && [ "$action_cmd" == "stop" ]; then
                echo "$service_name is not running."
                return
            fi
            if ! systemctl "$action_cmd" "$service_name"; then
                error_exit "Failed to $action_cmd $service_name."
            fi
            if [ "$action_cmd" == "status" ]; then
                systemctl status "$service_name" --no-pager -l
            fi
            ;;
        *)
            error_exit "Invalid action: $action_cmd for $service_name"
            ;;
    esac
}
case $SERVICE in
    nginx)
        perform_action "nginx" "$ACTION"
        ;;
    stunnel4)
        perform_action "stunnel4" "$ACTION"
        ;;
    all)
        if [ "$ACTION" == "start" ] || [ "$ACTION" == "restart" ] || [ "$ACTION" == "enable" ]; then
            perform_action "stunnel4" "$ACTION"
            perform_action "nginx" "$ACTION"
        elif [ "$ACTION" == "stop" ] || [ "$ACTION" == "disable" ]; then
            perform_action "nginx" "$ACTION"
            perform_action "stunnel4" "$ACTION"
        elif [ "$ACTION" == "status" ]; then
            perform_action "stunnel4" "$ACTION"
            echo "----"
            perform_action "nginx" "$ACTION"
        else
             error_exit "Invalid action '$ACTION' for 'all' services."
        fi
        ;;
    *)
        error_exit "Invalid service specified: $SERVICE. Use 'nginx', 'stunnel4', or 'all'."
        exit 1
        ;;
esac
echo "Service management task '$ACTION' for '$SERVICE' completed."
exit 0
