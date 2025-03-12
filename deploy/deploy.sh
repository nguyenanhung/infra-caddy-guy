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

# Determine current running container
CURRENT=$(docker ps --filter "name=$BLUE" --format "{{.Names}}")

if [[ "$CURRENT" == "$BLUE" ]]; then
  NEXT="$GREEN"
  NEXT_PORT="$PORT_GREEN"
  OLD="$BLUE"
else
  NEXT="$BLUE"
  NEXT_PORT="$PORT_BLUE"
  OLD="$GREEN"
fi

echo -e "${YELLOW}🚀 Deploying new version to '$NEXT' on port '$NEXT_PORT'...${RESET}"

# Start new container
docker run -d --rm --name "$NEXT" -p "$NEXT_PORT:3000" my-app:latest

# Check if container is running
if ! docker ps --format "{{.Names}}" | grep -q "$NEXT"; then
  echo -e "${RED}❌ Deployment failed!${RESET}"
  exit 1
fi

# Update Caddy reverse proxy config
echo -e "${YELLOW}🔧 Updating Caddy reverse proxy...${RESET}"
cat >"$CADDY_SITE_PATH/$DOMAIN.caddy" <<EOF
$DOMAIN {
    reverse_proxy http://127.0.0.1:$NEXT_PORT
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

# Stop old container
echo -e "${YELLOW}🛑 Stopping old container '$OLD'...${RESET}"
docker stop "$OLD"

# Cleanup stopped containers
echo -e "${YELLOW}🧹 Cleaning up old containers...${RESET}"
docker container prune -f

echo -e "${GREEN}🎉 Deployment completed! Now running on '$NEXT' (port $NEXT_PORT).${RESET}"
