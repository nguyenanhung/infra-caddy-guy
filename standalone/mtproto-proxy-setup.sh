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

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

# Script to generate docker-compose.yml for MTProto proxy with custom port, secret, and tag
if docker ps -a --format '{{.Names}}' | grep -q "^mtproto-proxy$"; then
  echo "⚠️  Container 'mtproto-proxy' already exists. Skipping docker-compose up."
  exit
fi

# Function to generate 16-byte hex string from /dev/urandom
generate_secret() {
  head -c 16 /dev/urandom | xxd -p
}

# 1. Ask user for port to run
read -rp "Enter the port you want MTProto proxy to listen on (e.g. 6688): " PORT

# Validate port is a number between 1 and 65535
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "Invalid port number. Please enter a number between 1 and 65535."
  exit 1
fi

# 2. Generate SECRET and TAG (same value)
SECRET=$(generate_secret)
TAG=$SECRET

# 3. Ask for location to save docker-compose.yml
SAVE_PATH="${BASE_DIR}/standalone/mtproto-proxy"
if [ ! -d "$SAVE_PATH" ]; then
  mkdir -p "$SAVE_DIR"
fi

# Full file path
FILE_PATH="${SAVE_PATH}/docker-compose.yml"

# 4. Create docker-compose.yml with the required content
cat >"$FILE_PATH" <<EOF
version: '3.8'

services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    ports:
      - "${PORT}:443"
    environment:
      - SECRET=${SECRET}
      - TAG=${TAG}
    restart: always
EOF

if [ $? -eq 0 ]; then
  echo "✅ docker-compose.yml has been created at: $FILE_PATH"
else
  echo "❌ Failed to create docker-compose.yml"
  exit 1
fi

# 5. Check if container 'mtproto-proxy' already exists
if docker ps -a --format '{{.Names}}' | grep -q "^mtproto-proxy$"; then
  echo "⚠️  Container 'mtproto-proxy' already exists. Skipping docker-compose up."
else
  echo "🚀 Starting MTProto proxy with Docker Compose..."
  cd "$SAVE_PATH" || exit
  docker compose up -d
  if [ $? -eq 0 ]; then
    echo "✅ MTProto proxy container started successfully."
    echo "------------------------------------------------"
    echo "🌐 You can now connect via:"
    echo "   https://t.me/proxy?server=$(curl -s ifconfig.me)&port=${PORT}&secret=${SECRET}"
    echo "or"
    echo "   tg://proxy?server=$(curl -s ifconfig.me)&port=${PORT}&secret=${SECRET}"
    echo "------------------------------------------------"
  else
    echo "❌ Failed to start MTProto proxy."
  fi
fi
