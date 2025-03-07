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
  message INFO "  $0 init                          - Setup Caddy Web Server"
  message INFO "  $0 list                          - List Website/Proxy..."
  message INFO "  $0 install                       - Install a new site"
  message INFO "  $0 stop [domain]                 - Stop running sites"
  message INFO "  $0 start [domain]                - Start an installed sites"
  message INFO "  $0 restart [domain]              - Restart an installed sites"
  message INFO "  $0 delete [domain]               - Delete a site"
  message INFO "  $0 logs                          - Check BEAR Caddy Docker Stack Logs"
  message INFO "  $0 enable-<service>              - Enable new Service (e.g. mariadb, redis, ...). Example: $0 enable-redis"
  message INFO "  $0 stop-<service>                - Stop Service Container (e.g. mariadb, redis, ...). Example: $0 stop-redis"
  message INFO "  $0 start-<service>               - Start Service Container (e.g. mariadb, redis, ...). Example: $0 start-redis"
  message INFO "  $0 restart-<service>             - Restart Service Container (e.g. mariadb, redis, ...). Example: $0 restart-redis"
  message INFO "  $0 remove-<service>              - Removing Service Container (e.g. mariadb, redis, ...). Example: $0 remove-redis"
  message INFO "  $0 log-<service>                 - Check Service Container (e.g. mariadb, redis, ...). Example: $0 log-redis"
  print_message
}
