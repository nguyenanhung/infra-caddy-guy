#!/bin/bash
# Base directory of the project (root of bear-caddy/)
if [ -z "$BASE_DIR" ]; then
  if command -v realpath >/dev/null 2>&1; then
    BASE_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
  else
    # Fallback for systems without realpath
    BASE_DIR="$(cd "$(dirname "$(dirname "$0")")" && pwd)"
  fi
fi

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

# Define paths
CADDY_SITE_CONFIG_PATH="${CONFIG_DIR}/sites"

# Determine rollback target
ROLLBACK_TARGET="$1"
if [[ -z "$ROLLBACK_TARGET" ]]; then
  ROLLBACK_TARGET="blue"
fi

# Define variables
TARGET_DOMAIN="${2:-""}"
if [ -z "$TARGET_DOMAIN" ]; then
  message ERROR "Domain must be provided."
  exit 1
fi
CADDY_DOMAIN_FILE="${CADDY_SITE_CONFIG_PATH}/${TARGET_DOMAIN}.caddy"
[ ! -e "$CADDY_DOMAIN_FILE" ] && {
  message ERROR "Domain ${TARGET_DOMAIN} is not exists in ${CADDY_SITE_CONFIG_PATH}. Please manually check and try again!"
  exit 1
}

CONTAINER_APP_BLUE="${3:-"${PREFIX_NAME}_sites_${TARGET_DOMAIN}"}" # Blue container or Origin container
CONTAINER_APP_GREEN="${4:-"${PREFIX_NAME}_sites_${TARGET_DOMAIN}_green"}"
CONTAINER_PORT_BLUE="$5"
CONTAINER_PORT_GREEN="$6"
if [[ -z "$CONTAINER_PORT_BLUE" || -z "$CONTAINER_PORT_GREEN" ]]; then
  message ERROR "Port Green and Blue must be provided"
  exit 1
fi

if [[ "$ROLLBACK_TARGET" == "blue" ]]; then
  TARGET="$CONTAINER_APP_BLUE"
  TARGET_PORT="$CONTAINER_PORT_BLUE"
  CURRENT="$CONTAINER_APP_GREEN"
elif [[ "$ROLLBACK_TARGET" == "green" ]]; then
  TARGET="$CONTAINER_APP_GREEN"
  TARGET_PORT="$CONTAINER_PORT_GREEN"
  CURRENT="$CONTAINER_APP_BLUE"
else
  message ERROR "❌ Invalid rollback target: '$ROLLBACK_TARGET'. Use 'blue' or 'green'."
  exit 1
fi

if ! docker ps -aq -f name="^${TARGET}$" | grep -q .; then
  message ERROR "Container '${TARGET}' does not exist!"
  message INFO "Please manually check, make sure container ${TARGET} it exists"
  exit 1
fi

# Check latest caddy configuration
caddy_sites_previous_config="${CADDY_SITE_CONFIG_PATH}/${TARGET_DOMAIN}.caddy.last_previous_deploy" # Tên file cấu hình cũ
if [ ! -e "$caddy_sites_previous_config" ]; then
  message ERROR "Previous config Caddy of ${TARGET_DOMAIN} does not exists in ${caddy_sites_previous_config}. Please manually check and try again!"
  exit 1
fi

message INFO "🔄 Rolling back to '$TARGET' on port '$TARGET_PORT'..."

# Start the rollback container (if stopped)
if ! docker ps --format "{{.Names}}" | grep -q "$TARGET"; then
  message INFO "$🚀 Starting container '$TARGET'..."
  docker start "$TARGET"
fi

# Update Caddy reverse proxy config
message INFO "🔧 Rollback Caddy Web Server Configuration of ${TARGET_DOMAIN}..."

############################
caddy_sites_error_rollback_config="${CADDY_SITE_CONFIG_PATH}/${TARGET_DOMAIN}.caddy.last_error_rollback" # Tên file cấu hình bị lỗi
if [ -e "$caddy_sites_error_rollback_config" ]; then
  backup_original_path "$caddy_sites_error_rollback_config"
  sudo rm -f "$caddy_sites_error_rollback_config"
fi
mv "$CADDY_DOMAIN_FILE" "$caddy_sites_error_rollback_config"
message INFO "Backed up $TARGET_DOMAIN.caddy to $caddy_sites_error_rollback_config"

############################
mv "$caddy_sites_previous_config" "$CADDY_DOMAIN_FILE"
message INFO "Restored up $TARGET_DOMAIN.caddy from $caddy_sites_error_rollback_config"

# Validate & reload Caddy
if caddy_validate; then
  if caddy_reload; then
    message SUCCESS "✅ Caddy Reload successfully!"
    message INFO "Rollback ${TARGET_DOMAIN} to last previous version successfully!"
  else
    message ERROR "❌ Failed to configuration Caddy Web Server on Rollback case. Please manually check config and try again!"
    exit 1
  fi
else
  message ERROR "❌ Caddy validation failed! Rolling back config..."
  exit 1
fi

# Stop current container
message INFO "🛑 Stopping '${CURRENT}'..."
docker stop "${CURRENT}"

message SUCCESS "🎉 Rollback completed! Now running on '${TARGET}' (port ${TARGET_PORT})."
