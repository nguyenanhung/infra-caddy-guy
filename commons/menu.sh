#!/bin/bash
# Base directory of the project (root of bear-caddy/)
# Use BASE_DIR from main.sh if set; otherwise calculate from config.sh
if [ -z "$BASE_DIR" ]; then
  if command -v realpath >/dev/null 2>&1; then
    BASE_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
  else
    # Fallback for systems without realpath
    BASE_DIR="$(cd "$(dirname "$(dirname "$0")")" && pwd)"
  fi
fi
CONFIG_DIR="$BASE_DIR/config"

# shellcheck source=./config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./validation.sh
source "$BASE_DIR/commons/validation.sh"

# Function to display welcome message for Bear Caddy
bear_welcome() {
  __display_header_information
  check_docker
  message INFO "  $(basename "$0") init                          - Setup Caddy Web Server"
  message INFO "  $(basename "$0") reload-caddy                  - Reload Caddy Web Server"
  message INFO "  $(basename "$0") list                          - List Website/Proxy..."
  message INFO "  $(basename "$0") install                       - Install a new site"
  message INFO "  $(basename "$0") stop [domain]                 - Stop running sites"
  message INFO "  $(basename "$0") start [domain]                - Start an installed sites"
  message INFO "  $(basename "$0") restart [domain]              - Restart an installed sites"
  message INFO "  $(basename "$0") delete [domain]               - Delete a site"
  message INFO "  $(basename "$0") logs                          - Check BEAR Caddy Docker Stack Logs"
  message INFO "  $(basename "$0") enable-<service>              - Enable new Service (e.g. mariadb, redis, ...). Example: $(basename "$0") enable-redis"
  message INFO "  $(basename "$0") stop-<service>                - Stop Service Container (e.g. mariadb, redis, ...). Example: $(basename "$0") stop-redis"
  message INFO "  $(basename "$0") start-<service>               - Start Service Container (e.g. mariadb, redis, ...). Example: $(basename "$0") start-redis"
  message INFO "  $(basename "$0") restart-<service>             - Restart Service Container (e.g. mariadb, redis, ...). Example: $(basename "$0") restart-redis"
  message INFO "  $(basename "$0") remove-<service>              - Removing Service Container (e.g. mariadb, redis, ...). Example: $(basename "$0") remove-redis"
  message INFO "  $(basename "$0") log-<service>                 - Check Service Container (e.g. mariadb, redis, ...). Example: $(basename "$0") log-redis"
  message INFO "  $(basename "$0") basic-auth                    - Enable basic authentication"
  message INFO "  $(basename "$0") delete-basic-auth             - Disable basic authentication"
  message INFO "  $(basename "$0") add-reverse-proxy             - Add Reverse Proxy"
  message INFO "  $(basename "$0") delete-reverse-proxy          - Delete Reverse Proxy"
  message INFO "  $(basename "$0") add-load-balancer             - Add Load Balancer"
  message INFO "  $(basename "$0") delete-load-balancer          - Delete Load Balancer"
  message INFO "  $(basename "$0") delete-load-balancer-backend  - Delete Load Balancer Backend"
  message INFO "  $(basename "$0") laravel-up                    - Build and configure Laravel Application"
  message INFO "  $(basename "$0") laravel-down                  - Down mode for Laravel Application"
  message INFO "  $(basename "$0") laravel-restore               - Restore from Down mode Laravel Application"
  message INFO "  $(basename "$0") laravel-remove                - Removing Laravel Application"
  echo
  message INFO "...and more great features will be added soon.."
  print_message
}
