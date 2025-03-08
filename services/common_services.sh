#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

# Function to enable a service
enable_service() {
  local service_name="$1"
  local container_name="${PREFIX_NAME}_${service_name}"

  # Check if container already exists
  if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
    message INFO "Container $container_name already exists, skipping creation"
    return 0
  fi

  # Validate service name
  if [ -z "${SERVICE_IMAGES[$service_name]}" ]; then
    message ERROR "Service $service_name is not supported"
    return 1
  fi

  # Get default values
  local default_image="${SERVICE_IMAGES[$service_name]}"
  local default_port="${SERVICE_PORTS[$service_name]}"
  local default_resources="${SERVICE_RESOURCES[$service_name]}"
  local default_healthcheck="${SERVICE_HEALTHCHECKS[$service_name]}"
  [ -z "$default_image" ] && {
    message ERROR "No default image defined for $service_name"
    return 1
  }
  [ -z "$default_port" ] && {
    message ERROR "No default port defined for $service_name"
    return 1
  }
  if [ -z "$default_resources" ]; then
    if [[ -v SERVICE_RESOURCES[default] ]]; then
      default_resources="${SERVICE_RESOURCES[default]}"
    else
      default_resources="cpu=1,memory=512M"
    fi
  fi
  [ -z "$default_healthcheck" ] && default_healthcheck="pgrep $service_name"

  # Ask for image version with fzf
  local image_options image
  image_options="latest $(echo "$default_image" | cut -d':' -f1):alpine $(echo "$default_image" | cut -d':' -f1):slim"
  local image
  image=$(prompt_with_fzf "Select image for $service_name" "$image_options" "$default_image")

  # Ask for credentials (if applicable)
  local service_url=""
  local database_name=""
  local username=""
  local root_password=""
  local password=""
  case "$service_name" in
  mongodb)
    username=$(prompt_with_default "Enter MongoDB username" "admin")
    password=$(prompt_with_default "Enter MongoDB password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"
    ;;
  mariadb | mysql | percona)
    username=$(prompt_with_default "Enter MariaDB/MySQL username" "admin")
    password=$(prompt_with_default "Enter MariaDB/MySQL ${username} password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password for ${username}: $password"
    root_password=$(prompt_with_default "Enter MariaDB/MySQL root password (leave blank for random)" "")
    [ -z "$root_password" ] && root_password=$(generate_password) && message INFO "Generated password for root: $root_password"
    ;;
  postgresql)
    username=$(prompt_with_default "Enter PostgreSQL username" "postgres")
    password=$(prompt_with_default "Enter PostgreSQL password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"
    ;;
  rabbitmq)
    username=$(prompt_with_default "Enter RabbitMQ username" "guest")
    password=$(prompt_with_default "Enter RabbitMQ password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"
    ;;
  elasticsearch)
    service_url=$(prompt_with_default "Enter Elasticsearch URL" "http://localhost:9200")
    username=$(prompt_with_default "Enter Elasticsearch username" "elastic")
    password=$(prompt_with_default "Enter Elasticsearch password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"
    ;;
  influxdb)
    database_name=$(prompt_with_default "Enter InfluxDB Database" "${PREFIX_NAME}_influxdb_database")
    username=$(prompt_with_default "Enter InfluxDB username" "elastic")
    password=$(prompt_with_default "Enter InfluxDB password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"
    ;;
  *)
    # No credentials needed for redis, memcached, etc.
    ;;
  esac

  # Ask for external port with fzf
  local default_port_suggestions="$default_port $((default_port + 1)) $((default_port + 2)) 127.0.0.1:$default_port 0.0.0.0:$default_port"
  local external_port
  message INFO "Internal port for $service_name will be fixed at $default_port"
  external_port=$(prompt_with_fzf "Select or enter an external port to map to $service_name's internal port $default_port (e.g., 1234, 127.0.0.1:1234)" "$default_port_suggestions" "")
  while ! validate_port_mapping "$external_port" || ! check_port "$(echo "$external_port" | grep -o '[0-9]\+$')"; do
    message ERROR "Port $external_port is invalid or already in use. Please choose another port."
    external_port=$(prompt_with_fzf "Select or enter a different external port for $service_name" "$default_port_suggestions" "")
  done
  validate_port_mapping "$external_port" || return 1
  local port_to_check
  port_to_check=$(echo "$external_port" | grep -o '[0-9]\+$')
  check_port "$port_to_check" || return 1

  # Ask for resource limits with fzf
  local resource_options="--cpus=0.5 --memory=256m --cpus=1 --memory=512m --cpus=1 --memory=1g --cpus=2 --memory=2g custom"
  local resources
  resources=$(prompt_with_fzf "Select or enter resource limits for $service_name (e.g., --cpus=1 --memory=512m)" "$resource_options" "$default_resources")
  if [ "$resources" = "custom" ]; then
    resources=$(prompt_with_default "Enter custom resource limits (e.g., --cpus=1 --memory=512m)" "$default_resources")
    while ! echo "$resources" | grep -qE "--cpus=[0-9.]+ --memory=[0-9]+[mg]"; do
      message ERROR "Invalid resource format. Use '--cpus=<number> --memory=<number>[m|g]' (e.g., --cpus=1 --memory=512m)"
      resources=$(prompt_with_default "Enter custom resource limits again" "$default_resources")
    done
  fi
  local resource_cpus resource_memory
  resource_cpus="${resources##*--cpus=}"
  resource_cpus="${resource_cpus%% *}"
  resource_memory="${resources##*--memory=}"
  resource_memory="${resource_memory%% *}"

  # Ask for restart policy with fzf
  local restart_options="unless-stopped on-failure no always"
  local restart_policy
  restart_policy=$(prompt_with_fzf "Select restart policy for $service_name" "$restart_options")

  # Define volume paths
  local data_volume=""
  case "$service_name" in
  mongodb)
    data_volume="$VOLUMES_DIR/data/$container_name/data:/data/db"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
    ;;
  mariadb | mysql | percona)
    data_volume="$VOLUMES_DIR/data/$container_name/data:/var/lib/mysql"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
    ;;
  postgresql)
    data_volume="$VOLUMES_DIR/data/$container_name/data:/var/lib/postgresql/data"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
    ;;
  rabbitmq)
    data_volume="$VOLUMES_DIR/data/$container_name/data:/var/lib/rabbitmq"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
    ;;
  redis)
    data_volume="$VOLUMES_DIR/data/$container_name/data:/data"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
    ;;
  elasticsearch)
    data_volume="$VOLUMES_DIR/data/$container_name/data:/usr/share/elasticsearch/data"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
    ;;
  influxdb)
    data_volume="$VOLUMES_DIR/data/$container_name/data:/var/lib/influxdb2"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
    ;;
  *)
    # Other services may not need persistent data by default
    ;;
  esac

  # Generate.env file
  local env_file="$CONTAINER_DIR/services/$container_name/.env"
  local compose_file="$CONTAINER_DIR/services/$container_name/docker-compose.yml"

  # Get the compose version dynamically
  local include_docker_version
  include_docker_version=$(set_compose_version)

  # Show overview and confirm
  print_message "Overview of new service ${service_name}"
  message INFO "Network name: ${NETWORK_NAME}"
  message INFO "Services name: ${PREFIX_NAME}_${service_name}"
  message INFO "Container name: ${container_name}"
  message INFO "Image: ${image}"
  [ -n "$username" ] && message INFO "Username: $username"
  [ -n "$password" ] && message INFO "Password: $password"
  [ -n "$root_password" ] && message INFO "Root Password: $root_password"
  message INFO "Port mapping: ${external_port}:${default_port}"
  message INFO "Resources CPU: $resource_cpus"
  message INFO "Resources Memory: $resource_memory"
  message INFO "Restart Policy: $restart_policy"
  message INFO "Mount Volumes: $data_volume"
  message INFO "Environment File: $env_file"
  message INFO "Docker Compose File: $compose_file"
  message INFO "Docker Compose Version Syntax: $include_docker_version"
  print_message
  confirm_action "Do you want to proceed with enabling ${GREEN}${service_name}${NC}?" || {
    message INFO "Action canceled"
    return 0
  }

  # Generate docker-compose.yml
  mkdir -p "$CONTAINER_DIR/services/$container_name"
  cat >"$compose_file" <<EOF
${include_docker_version}

networks:
  ${NETWORK_NAME}:
    external: true

services:
  ${PREFIX_NAME}_${service_name}:
    image: ${image}
    container_name: ${container_name}
    networks:
      - ${NETWORK_NAME}
    ports:
      - "${external_port}:${default_port}"
    deploy:
      resources:
        limits:
          cpus: "${resource_cpus}"
          memory: "${resource_memory}"
    logging:
      driver: "local"
      options:
        max-size: "10m"
        max-file: "3"
    restart: ${restart_policy}
EOF

  # Add environment variables for services requiring credentials
  if [ -n "$username" ] && [ -n "$password" ]; then
    case "$service_name" in
    mongodb)
      if [ ! -f "$env_file" ]; then
        cat >"$env_file" <<EOF
MONGO_INITDB_ROOT_USERNAME=${username}
MONGO_INITDB_ROOT_PASSWORD=${password}
EOF
      fi
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
      ;;
    mariadb | mysql | percona)
      if [ ! -f "$env_file" ]; then
        cat >"$env_file" <<EOF
MYSQL_ROOT_PASSWORD=${root_password}
MYSQL_USER=${username}
MYSQL_PASSWORD=${password}
EOF
      fi
      if [ ! -f "$env_file" ]; then
        message ERROR "Failed to create environment file"
        return 1
      fi
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
      ;;
    postgresql)
      if [ ! -f "$env_file" ]; then
        cat >"$env_file" <<EOF
POSTGRES_USER=${username}
POSTGRES_PASSWORD=${password}
EOF
      fi
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
      ;;
    rabbitmq)
      if [ ! -f "$env_file" ]; then
        cat >"$env_file" <<EOF
RABBITMQ_DEFAULT_USER=${username}
RABBITMQ_DEFAULT_PASS=${password}
EOF
      fi
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
      ;;
    elasticsearch)
      if [ ! -f "$env_file" ]; then
        cat >"$env_file" <<EOF
ELASTIC_USERNAME=${username}
ELASTIC_PASSWORD=${password}
ELASTICSEARCH_URL=${service_url}
discovery.type=single-node
EOF
      fi
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
      ;;
    influxdb)
      if [ ! -f "$env_file" ]; then
        cat >"$env_file" <<EOF
INFLUXDB_ADMIN_USER=${username}
INFLUXDB_ADMIN_PASSWORD=${password}
INFLUXDB_DB=${database_name}
INFLUXDB_HTTP_AUTH_ENABLED=true
EOF
      fi
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
      ;;
    esac
  fi

  # Add volumes if applicable
  if [ -n "$data_volume" ]; then
    echo "    volumes:" >>"$compose_file"
    echo "      - $data_volume" >>"$compose_file"
  fi

  # Define the health check service
  cat >>"$compose_file" <<EOF
    healthcheck:
      test: ["CMD-SHELL", "${default_healthcheck}"]
      interval: 30s
      retries: 3
      start_period: 10s
EOF

  # Start the service
  cd "$CONTAINER_DIR/services/$container_name" || return 1

  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    message INFO "Pulling and Build image ${image}"
    docker pull "${image}"
    docker compose build
  fi

  message INFO "Starting service $service_name"
  if docker compose up -d; then
    message SUCCESS "Build Service $service_name and enabled successfully"
    message INFO "Please wait a moment while ${service_name} starts up..."
    if wait_for_health "${container_name}" "${service_name}"; then
      echo
      docker ps -a --filter "name=${container_name}"
    else
      message INFO "Failed to start service ${service_name}"
      exit 1
    fi
  else
    message ERROR "Failed to enable service $service_name" >&2
    exit 1
  fi
}

# Function to stop a service
stop_service() {
  local service_name="$1"
  local container_name="${PREFIX_NAME}_${service_name}"
  docker stop "$container_name" && message INFO "Service $service_name stopped"
}

# Function to start a service
start_service() {
  local service_name="$1"
  local container_name="${PREFIX_NAME}_${service_name}"
  docker start "$container_name" && message INFO "Service $service_name started"
}

# Function to restart a service
restart_service() {
  local service_name="$1"
  local container_name="${PREFIX_NAME}_${service_name}"
  docker restart "$container_name" && message INFO "Service $service_name restarted"
}

# Function to remove a service
remove_service() {
  local service_name="$1"
  local container_name="${PREFIX_NAME}_${service_name}"
  local compose_dir="$CONTAINER_DIR/services/$container_name"
  print_message "Removing service $service_name"
  docker rm -f "$container_name" && message INFO "Service $service_name removed"

  if [ -f "$compose_dir/docker-compose.yml" ]; then
    local backup_file
    backup_file="$BACKUP_DIR/$service_name.docker-compose.yml.$(date +%Y%m%d_%H%M%S)"
    backup_original_path "$compose_dir/docker-compose.yml" "$backup_file" || return 1
    message INFO "Backed up docker-compose.yml to $backup_file"
  fi

  if [ -f "$compose_dir/.env" ]; then
    local backup_file
    backup_file="$BACKUP_DIR/$service_name.env.$(date +%Y%m%d_%H%M%S)"
    backup_original_path "$compose_dir/.env" "$backup_file" || return 1
    message INFO "Backed up .env to $backup_file"
  fi

  if [ -d "$compose_dir" ]; then
    rm -rf "$compose_dir"
    message INFO "Service directory $compose_dir removed"
  fi
}

# Function to view logs of a service
log_service() {
  local service_name="$1"
  local container_name="${PREFIX_NAME}_${service_name}"
  docker logs -f "$container_name"
}
