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
bear_welcome_introduce() {
  __display_header_information
  check_docker
  message INFO "  $(basename "$0") self-update                   - Infra Caddy Guy's self-update"
  message INFO "  $(basename "$0") help/intro                    - Infra Caddy Guy's Help / Introspection"
  message INFO "  $(basename "$0") clean-build-cache             - Clean Docker Build Cache"
  message INFO "  $(basename "$0") buildx-multi-platform         - Enable Docker Buildx Multi-Platform"
  message INFO "  $(basename "$0") init                          - Setup Caddy Web Server"
  message INFO "  $(basename "$0") reload-caddy                  - Reload Caddy Web Server"
  message INFO "  $(basename "$0") join-caddy                    - Join Caddy Network"
  message INFO "  $(basename "$0") disconnect-caddy              - Disconnect Caddy Network"
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

  message INFO "  $(basename "$0") add-static-site               - Add Static Site"
  message INFO "  $(basename "$0") delete-static-site            - Delete Static Site"

  message INFO "  $(basename "$0") add-load-balancer             - Add Load Balancer"
  message INFO "  $(basename "$0") delete-load-balancer          - Delete Load Balancer"
  message INFO "  $(basename "$0") delete-load-balancer-backend  - Delete Load Balancer Backend"

  message INFO "  $(basename "$0") add-php-app                   - Add PHP Application"
  message INFO "  $(basename "$0") delete-php-app                - Delete PHP Application"
  message INFO "  $(basename "$0") laravel-up                    - Build and configure Laravel Application Container"
  message INFO "  $(basename "$0") laravel-down                  - Down mode for Laravel Application Container"
  message INFO "  $(basename "$0") laravel-restore               - Restore from Down mode Laravel Application Container"
  message INFO "  $(basename "$0") laravel-remove                - Removing Laravel Application Container"
  message INFO "  $(basename "$0") laravel-apache-up             - Build and configure Laravel Application Apache Container"

  message INFO "  $(basename "$0") add-node-app                  - Add Node.js Application"
  message INFO "  $(basename "$0") delete-node-app               - Delete Node.js Application"
  message INFO "  $(basename "$0") node-up                       - Build and configure Node.js Application Container"
  message INFO "  $(basename "$0") node-down                     - Down mode for Node.js Application Container"
  message INFO "  $(basename "$0") node-restore                  - Restore from Down mode Node.js Application Container"
  message INFO "  $(basename "$0") node-remove                   - Removing Node.js Application Container"
  echo
  message INFO "...and more great features will be added soon.."
  print_message
}
bear_menu_interactive() {
  __display_header_information
  check_docker
  options=(
    "Introduction"
    "Setup Caddy Server" "Reload Caddy Server" "Join Container to Caddy Network" "Disconnect Caddy Network"
    "Check Container Logs"
    "List all Sites" "Install new Site" "Stop Sites" "Start Sites" "Restart Sites" "Delete Sites"
    "Enable Basic Auth" "Disable Basic Auth"
    "Add Static Site" "Delete Static Site"
    "Add Reverse Proxy" "Delete Reverse Proxy"
    "Add Load Balancer Cluster" "Delete Load Balancer Cluster" "Delete Load Balancer Backend"
    "Add new Node.js App (Container exists)"
    "Delete Node.js App"
    "Build & Add new Node.js App"
    "Add new PHP App (Container exists)"
    "Build & Add new Laravel App (PHP-FPM)"
    "Delete PHP App"
  )
  prompt="Enter your selected menu you want [0 = Exit]: "
  PS3=$'\n'"${prompt} "
  select opt in "${options[@]}" "Exit"; do
    case "$REPLY" in

    1) bash "${BASE_DIR}/bear-caddy" introduce ;;
    2) bash "${BASE_DIR}/bear-caddy" init ;;
    3) bash "${BASE_DIR}/bear-caddy" reload-caddy ;;
    4) bash "${BASE_DIR}/bear-caddy" join-caddy ;;
    5) bash "${BASE_DIR}/bear-caddy" disconnect-caddy ;;
    6) bash "${BASE_DIR}/bear-caddy" logs ;;
    7) bash "${BASE_DIR}/bear-caddy" list ;;
    8) bash "${BASE_DIR}/bear-caddy" install ;;
    9) bash "${BASE_DIR}/bear-caddy" stop ;;
    10) bash "${BASE_DIR}/bear-caddy" start ;;
    11) bash "${BASE_DIR}/bear-caddy" restart ;;
    12) bash "${BASE_DIR}/bear-caddy" delete ;;
    13) bash "${BASE_DIR}/bear-caddy" basic-auth ;;
    14) bash "${BASE_DIR}/bear-caddy" delete-basic-auth ;;
    15) bash "${BASE_DIR}/bear-caddy" add-static-site ;;
    16) bash "${BASE_DIR}/bear-caddy" delete-static-site ;;
    17) bash "${BASE_DIR}/bear-caddy" add-reverse-proxy ;;
    18) bash "${BASE_DIR}/bear-caddy" delete-reverse-proxy ;;
    19) bash "${BASE_DIR}/bear-caddy" add-load-balancer ;;
    20) bash "${BASE_DIR}/bear-caddy" delete-load-balancer ;;
    21) bash "${BASE_DIR}/bear-caddy" delete-load-balancer-backend ;;
    22) bash "${BASE_DIR}/bear-caddy" laravel-up ;;
    23) bash "${BASE_DIR}/bear-caddy" add-php-app ;;
    24) bash "${BASE_DIR}/bear-caddy" delete-php-app ;;
    25) bash "${BASE_DIR}/bear-caddy" node-up ;;
    26) bash "${BASE_DIR}/bear-caddy" add-node-app ;;
    27) bash "${BASE_DIR}/bear-caddy" delete-node-app ;;

    $((${#options[@]} + 1)) | 0 | exit)
      printf "\nGoodbye!\nSee you again at https://bash.nguyenanhung.com/\n\n"
      break
      ;;
    q | quit | ":quit" | ":q")
      printf "\nGoodbye!\nSee you again at https://bash.nguyenanhung.com/\n\n"
      exit
      ;;
    *)
      echo -e "\nYou entered the wrong number, please enter the number in order on the list [${GREEN}1-$((${#options[@]} + 1))${NC}]"
      continue
      ;;
    esac
  done

}
