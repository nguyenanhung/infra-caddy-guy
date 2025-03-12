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
# Defined Caddy domain file
CADDY_DOMAIN_FILE="${CADDY_SITE_CONFIG_PATH}/${TARGET_DOMAIN}.caddy"

# First or last deployment
[ ! -e "$CADDY_DOMAIN_FILE" ] && {
  message ERROR "Domain ${TARGET_DOMAIN} is not exists in ${CADDY_SITE_CONFIG_PATH}. Please manually check and try again!"
  message INFO "This script only support rolling-update aka Blue-Green deployment, and not support first deployment!"
  exit 1
}

# Define variables
TARGET_DOMAIN="${2:-""}"
if [ -z "$TARGET_DOMAIN" ]; then
  message ERROR "Domain must be provided."
  exit 1
fi
CONTAINER_APP_BLUE="${3:-"${PREFIX_NAME}_sites_${TARGET_DOMAIN}"}" # Blue container or Origin container
CONTAINER_APP_GREEN="${4:-"${PREFIX_NAME}_sites_${TARGET_DOMAIN}_green"}"
CONTAINER_PORT_BLUE="$5"
CONTAINER_PORT_GREEN="$6"
if [[ -z "$CONTAINER_PORT_BLUE" || -z "$CONTAINER_PORT_GREEN" ]]; then
  message ERROR "Port Green and Blue must be provided"
  exit 1
fi

# Determine current running container
CURRENT=$(docker ps --filter "name=$CONTAINER_APP_BLUE" --format "{{.Names}}")

if [[ "$CURRENT" == "$CONTAINER_APP_BLUE" ]]; then
  NEXT="$CONTAINER_APP_GREEN"
  NEXT_PORT="$CONTAINER_PORT_GREEN"
  OLD="$CONTAINER_APP_BLUE"
  OLD_PORT="$CONTAINER_PORT_BLUE"
else
  NEXT="$CONTAINER_APP_BLUE"
  NEXT_PORT="$CONTAINER_PORT_BLUE"
  OLD="$CONTAINER_APP_GREEN"
  OLD_PORT="$CONTAINER_PORT_GREEN"
fi

message INFO "🚀 Deploying new version to '$NEXT' on port '$NEXT_PORT'..."

# Start new container
docker run -d --rm --name "$NEXT" -p "$NEXT_PORT:3000" my-app:latest

# Check if container is running
if ! docker ps --format "{{.Names}}" | grep -q "$NEXT"; then
  message ERROR "❌ Deployment failed!"
  exit 1
fi

# Update Caddy
message INFO "🔧 Updating Caddy Web Server Configuration..."

# Check latest caddy configuration
caddy_sites_previous_config="${CADDY_SITE_CONFIG_PATH}/${TARGET_DOMAIN}.caddy.last_previous_deploy_config"
caddy_sites_previous_config_tmp="${CADDY_SITE_CONFIG_PATH}/${TARGET_DOMAIN}.caddy.last_previous_deploy_config.tmp"

MAY_BE_ERROR_SYNTAX="NO"
if [ -e "$caddy_sites_previous_config" ]; then
  # Trong trường hợp tồn tại cấu hình cũ, lấy cấu hình cũ

  if [ -e "$caddy_sites_previous_config_tmp" ]; then
    rm -f "$caddy_sites_previous_config_tmp"
  fi
  backup_original_path "$CADDY_DOMAIN_FILE" || {
    message ERROR "Failed to backup ${CADDY_DOMAIN_FILE}"
    exit 1
  }
  backup_original_path "$caddy_sites_previous_config" || {
    message ERROR "Failed to backup ${caddy_sites_previous_config}"
    exit 1
  }
  # Moving current $domain.caddy to $caddy_sites_previous_config_tmp
  mv "${CADDY_DOMAIN_FILE}" "${caddy_sites_previous_config_tmp}"
  if [ ! -e "$caddy_sites_previous_config_tmp" ] || [ -e "${CADDY_DOMAIN_FILE}" ]; then
    message ERROR "Failed moving ${CADDY_DOMAIN_FILE} to tmp file"
    exit 1
  fi
  # Moving last blue/green version
  mv "${caddy_sites_previous_config}" "${CADDY_DOMAIN_FILE}"
  if [ -e "$caddy_sites_previous_config" ] || [ ! -e "${CADDY_DOMAIN_FILE}" ]; then
    message ERROR "Failed moving ${CADDY_DOMAIN_FILE} to tmp file"
    exit 1
  fi
  message INFO "Setup Caddy Configure for ${TARGET_DOMAIN} on the ${NEXT} successfully"

  # Setup rollback file
  mv "${caddy_sites_previous_config_tmp}" "${caddy_sites_previous_config}"
  if [ -e "$caddy_sites_previous_config_tmp" ] || [ ! -e "${caddy_sites_previous_config}" ]; then
    message ERROR "Failed moving ${caddy_sites_previous_config_tmp} to ${caddy_sites_previous_config}"
    exit 1
  fi
  message INFO "Setup Rollback Caddy Web Server Config for ${TARGET_DOMAIN} in ${OLD}"
else
  if [ -e "$caddy_sites_previous_config_tmp" ]; then
    rm -f "$caddy_sites_previous_config_tmp"
  fi
  backup_original_path "$CADDY_DOMAIN_FILE" || {
    message ERROR "Failed to backup ${CADDY_DOMAIN_FILE}"
    exit 1
  }
  cp -f "$CADDY_DOMAIN_FILE" "$caddy_sites_previous_config"
  if [ -e "$caddy_sites_previous_config" ]; then
    message ERROR "Failed to create Rollback for ${TARGET_DOMAIN} in ${OLD}"
    exit 1
  fi
  if ! str_replace "${OLD}:${OLD_PORT}" "${NEXT}:${NEXT_PORT}" "$CADDY_DOMAIN_FILE"; then
    message ERROR "Failed to update Caddy Web Server Configuration for ${TARGET_DOMAIN}. Please manually check and try again..."
    exit 1
  fi
  MAY_BE_ERROR_SYNTAX="YES"
fi

# Validate & reload Caddy
if caddy_validate; then
  if caddy_reload; then
    message SUCCESS "✅ Caddy Reload successfully!"
    message INFO "Deployment ${TARGET_DOMAIN} to latest version successfully!"
  else
    message ERROR "❌ Failed to configuration Caddy Web Server on Rolling-Update case. Please manually check config and try again!"
    exit 1
  fi
else
  if [[ "$MAY_BE_ERROR_SYNTAX" == "YES" ]]; then
    message INFO "Error Syntax Caddy. Rollback configuration"
    cp -f "$caddy_sites_previous_config" "$CADDY_DOMAIN_FILE"
  else
    message ERROR "❌ Caddy validation failed! Please manually check and try again..."
  fi
  exit 1
fi

# Stop old container
message INFO "🛑 Stopping old container '$OLD'..."
docker stop "$OLD"

message SUCCESS "🎉 Deployment completed! Now running on '$NEXT' (port $NEXT_PORT)."
