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

# Define variables
DOMAIN="example.com"
BLUE="app_blue"
GREEN="app_green"
PORT_BLUE=3000
PORT_GREEN=3001

# Determine rollback target
ROLLBACK_TARGET="$1"
if [[ -z "$ROLLBACK_TARGET" ]]; then
  ROLLBACK_TARGET="blue"
fi

if [[ "$ROLLBACK_TARGET" == "blue" ]]; then
  TARGET="$BLUE"
  TARGET_PORT="$PORT_BLUE"
  CURRENT="$GREEN"
elif [[ "$ROLLBACK_TARGET" == "green" ]]; then
  TARGET="$GREEN"
  TARGET_PORT="$PORT_GREEN"
  CURRENT="$BLUE"
else
  echo -e "${RED}❌ Invalid rollback target: '$ROLLBACK_TARGET'. Use 'blue' or 'green'.${RESET}"
  exit 1
fi

echo -e "${YELLOW}🔄 Rolling back to '$TARGET' on port '$TARGET_PORT'...${RESET}"

# Start the rollback container (if stopped)
if ! docker ps --format "{{.Names}}" | grep -q "$TARGET"; then
  echo -e "${YELLOW}🚀 Starting '$TARGET'...${RESET}"
  docker start "$TARGET"
fi

# Update Caddy reverse proxy config
echo -e "${YELLOW}🔧 Updating Caddy reverse proxy...${RESET}"

cat >"$CADDY_SITE_CONFIG_PATH/$DOMAIN.caddy" <<EOF
$DOMAIN {
    reverse_proxy http://127.0.0.1:$TARGET_PORT
}
EOF

# Validate & reload Caddy
if caddy validate; then
  docker exec caddy-server caddy reload
  echo -e "${GREEN}✅ Caddy updated successfully!${RESET}"
else
  echo -e "${RED}❌ Caddy validation failed! Rolling back config...${RESET}"
  exit 1
fi

# Stop current container
echo -e "${YELLOW}🛑 Stopping '$CURRENT'...${RESET}"
docker stop "$CURRENT"

echo -e "${GREEN}🎉 Rollback completed! Now running on '$TARGET' (port $TARGET_PORT).${RESET}"
