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

  # Check if container exists
  if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
    message INFO "Container $container_name already exists, skipping creation"
    return 0
  fi

  # Validate service
  if [ -z "${SERVICE_IMAGES[$service_name]}" ]; then
    message ERROR "Service $service_name is not supported"
    return 1
  fi

  # Get defaults
  local default_image="${SERVICE_IMAGES[$service_name]}"
  local default_port="${SERVICE_PORTS[$service_name]}"
  local default_resources="${SERVICE_RESOURCES[$service_name]}"
  if [ -z "$default_resources" ]; then
    if [[ -v SERVICE_RESOURCES[default] ]]; then
      default_resources="${SERVICE_RESOURCES[default]}"
    else
      default_resources="--cpus=0.5 --memory=256m"
    fi
  fi
  local default_healthcheck="${SERVICE_HEALTHCHECKS[$service_name]:-pgrep $service_name}"
  local default_mount_path="${SERVICE_MOUNT_PATHS[$service_name]}"

  # Ask for image version
  local image_options="latest $(echo "$default_image" | cut -d':' -f1):alpine $(echo "$default_image" | cut -d':' -f1):slim"
  local image=$(prompt_with_fzf "Select image for $service_name" "$image_options" "$default_image")

  # Ask for external port
  local default_port_suggestions="127.0.0.1:${default_port} 127.0.0.1:$((default_port + 1)) 127.0.0.1:$((default_port + 2)) ${default_port} $((default_port + 1)) $((default_port + 2))"
  message INFO "Internal port for $service_name will be fixed at $default_port"
  local external_port=$(prompt_with_fzf "Select or enter an external port to map to $service_name's internal port $default_port. (Note: If you need to set up security (some applications like redis), it's best to choose the range 127.0.0.1:xxx)" "$default_port_suggestions" "$default_port")
  while ! validate_port_mapping "$external_port" || ! check_port "$(echo "$external_port" | grep -o '[0-9]\+$')"; do
    message ERROR "Port $external_port is invalid or already in use."
    external_port=$(prompt_with_fzf "Select or enter a different external port for $service_name" "$default_port_suggestions" "$default_port")
  done

  # Ask for resource limits
  local resource_options="--cpus=0.5 --memory=256m --cpus=1 --memory=512m --cpus=1 --memory=1g --cpus=2 --memory=2g custom"
  local resources=$(prompt_with_fzf "Select or enter resource limits for $service_name" "$resource_options" "$default_resources")
  if [ "$resources" = "custom" ]; then
    resources=$(prompt_with_default "Enter custom resource limits (e.g., --cpus=1 --memory=512m)" "$default_resources")
    while ! echo "$resources" | grep -qE "--cpus=[0-9.]+ --memory=[0-9]+[mg]"; do
      message ERROR "Invalid resource format. Use '--cpus=<number> --memory=<number>[m|g]'"
      resources=$(prompt_with_default "Enter custom resource limits again" "$default_resources")
    done
  fi
  local resource_cpus="${resources##*--cpus=}" resource_cpus="${resource_cpus%% *}"
  local resource_memory="${resources##*--memory=}" resource_memory="${resource_memory%% *}"

  # Ask for restart policy
  local restart_options="unless-stopped on-failure no always"
  local restart_policy=$(prompt_with_fzf "Select restart policy for $service_name" "$restart_options")

  # Define volume
  local data_volume=""
  [ -n "$default_mount_path" ] && {
    data_volume="$VOLUMES_DIR/data/$container_name/data:$default_mount_path"
    mkdir -p "$VOLUMES_DIR/data/$container_name/data"
  }

  # Generate files
  local env_file="$CONTAINER_DIR/services/$container_name/.env"
  local compose_file="$CONTAINER_DIR/services/$container_name/docker-compose.yml"
  mkdir -p "$CONTAINER_DIR/services/$container_name"

  # Credentials handling
  local username password root_password database_name service_url
  case "$service_name" in
  mongodb)
    username=$(prompt_with_default "Enter MongoDB username" "admin")
    password=$(prompt_with_default "Enter MongoDB password (leave blank for random)" "$(generate_password)")
    [ -z "$password" ] && password=$(generate_password)
    database_name=$(prompt_with_default "Enter MongoDB database" "${service_name}_db")
    echo "MONGO_INITDB_ROOT_USERNAME=${username}" >"$env_file"
    echo "MONGO_INITDB_ROOT_PASSWORD=${password}" >>"$env_file"
    echo "MONGO_INITDB_DATABASE=${database_name}" >>"$env_file"
    echo "MONGO_URL=mongodb://${username}:${password}@${container_name}:${default_port}/${database_name}?authSource=admin" >>"$env_file"
    ;;
  mariadb | mysql | percona)
    root_password=$(prompt_with_default "Enter ${service_name} root password (leave blank for random)" "$(generate_password)")
    [ -z "$root_password" ] && root_password=$(generate_password)
    username=$(prompt_with_default "Enter ${service_name} username" "admin")
    password=$(prompt_with_default "Enter ${service_name} password for ${username} (leave blank for random)" "$(generate_password)")
    [ -z "$password" ] && password=$(generate_password)
    database_name=$(prompt_with_default "Enter ${service_name} database" "${service_name}_db")
    echo "MYSQL_ROOT_PASSWORD=${root_password}" >"$env_file"
    echo "MYSQL_USER=${username}" >>"$env_file"
    echo "MYSQL_PASSWORD=${password}" >>"$env_file"
    echo "MYSQL_DATABASE=${database_name}" >>"$env_file"
    ;;
  postgresql)
    username=$(prompt_with_default "Enter PostgreSQL username" "postgres")
    password=$(prompt_with_default "Enter PostgreSQL password (leave blank for random)" "$(generate_password)")
    [ -z "$password" ] && password=$(generate_password)
    database_name=$(prompt_with_default "Enter PostgreSQL database" "${service_name}_db")
    echo "POSTGRES_USER=${username}" >"$env_file"
    echo "POSTGRES_PASSWORD=${password}" >>"$env_file"
    echo "POSTGRES_DB=${database_name}" >>"$env_file"
    echo "PG_CONNECTION_STRING=postgres://${username}:${password}@${container_name}:${default_port}/${database_name}" >>"$env_file"
    ;;
  rabbitmq)
    username=$(prompt_with_default "Enter RabbitMQ username" "guest")
    password=$(prompt_with_default "Enter RabbitMQ password (leave blank for random)" "$(generate_password)")
    [ -z "$password" ] && password=$(generate_password)
    echo "RABBITMQ_DEFAULT_USER=${username}" >"$env_file"
    echo "RABBITMQ_DEFAULT_PASS=${password}" >>"$env_file"
    ;;
  elasticsearch)
    username=$(prompt_with_default "Enter Elasticsearch username" "elastic")
    password=$(prompt_with_default "Enter Elasticsearch password (leave blank for random)" "$(generate_password)")
    [ -z "$password" ] && password=$(generate_password)
    service_url=$(prompt_with_default "Enter Elasticsearch URL" "http://${container_name}:${default_port}")
    echo "ELASTIC_USERNAME=${username}" >"$env_file"
    echo "ELASTIC_PASSWORD=${password}" >>"$env_file"
    echo "ELASTICSEARCH_URL=${service_url}" >>"$env_file"
    echo "discovery.type=single-node" >>"$env_file"
    ;;
  influxdb)
    username=$(prompt_with_default "Enter InfluxDB username" "admin")
    password=$(prompt_with_default "Enter InfluxDB password (leave blank for random)" "$(generate_password)")
    [ -z "$password" ] && password=$(generate_password)
    database_name=$(prompt_with_default "Enter InfluxDB database" "${service_name}_db")
    echo "INFLUXDB_ADMIN_USER=${username}" >"$env_file"
    echo "INFLUXDB_ADMIN_PASSWORD=${password}" >>"$env_file"
    echo "INFLUXDB_DB=${database_name}" >>"$env_file"
    echo "INFLUXDB_HTTP_AUTH_ENABLED=true" >>"$env_file"
    ;;
  redis)
    if confirm_action "Enable password for Redis?"; then
      password=$(prompt_with_default "Enter Redis password (leave blank for random)" "$(generate_password)")
      [ -z "$password" ] && password=$(generate_password)
      echo "REDIS_PASSWORD=${password}" >"$env_file"
      echo "REDIS_URL=redis://:${password}@${container_name}:${default_port}" >>"$env_file"
    else
      echo "# Redis running without password" >"$env_file"
    fi
    ;;
  beanstalkd)
    if confirm_action "Enable SASL auth for Beanstalkd?"; then
      username=$(prompt_with_default "Enter Beanstalkd SASL username" "admin")
      password=$(prompt_with_default "Enter Beanstalkd SASL password (leave blank for random)" "$(generate_password)")
      [ -z "$password" ] && password=$(generate_password)
      echo "BEANSTALKD_SASL_USERNAME=${username}" >"$env_file"
      echo "BEANSTALKD_SASL_PASSWORD=${password}" >>"$env_file"
    else
      echo "# Beanstalkd running without SASL auth" >"$env_file"
    fi
    ;;
  minio)
    username=$(prompt_with_default "Enter MinIO root username" "minioadmin")
    password=$(prompt_with_default "Enter MinIO root password (leave blank for random)" "$(generate_password)")
    [ -z "$password" ] && password=$(generate_password)
    echo "MINIO_ROOT_USER=${username}" >"$env_file"
    echo "MINIO_ROOT_PASSWORD=${password}" >>"$env_file"
    echo "MINIO_URL=http://${container_name}:${default_port}" >>"$env_file"
    default_healthcheck="curl -s -u ${username}:${password} http://${container_name}:${default_port}/minio/health/live"
    ;;
  n8n)
    if confirm_action "Enable basic auth for n8n?"; then
      username=$(prompt_with_default "Enter n8n username" "admin")
      password=$(prompt_with_default "Enter n8n password (leave blank for random)" "$(generate_password)")
      [ -z "$password" ] && password=$(generate_password)
      echo "N8N_BASIC_AUTH_ACTIVE=true" >"$env_file"
      echo "N8N_BASIC_AUTH_USER=${username}" >>"$env_file"
      echo "N8N_BASIC_AUTH_PASSWORD=${password}" >>"$env_file"
      default_healthcheck="curl -s -u ${username}:${password} http://${container_name}:${default_port}/healthz"
    else
      echo "# n8n running without basic auth" >"$env_file"
    fi
    ;;
  mailhog | phpmyadmin | adminer | uptime-kuma | gearmand | memcached)
    echo "# $service_name does not require authentication by default" >"$env_file"
    ;;
  esac
  [ -f "$env_file" ] && chmod 600 "$env_file"

  # Generate docker-compose.yml
  local include_docker_version=$(set_compose_version)
  cat >"$compose_file" <<EOF
${include_docker_version}
networks:
  ${NETWORK_NAME}:
    external: true
services:
  ${container_name}:
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
  [ -s "$env_file" ] && {
    echo "    env_file:" >>"$compose_file"
    echo "      - .env" >>"$compose_file"
  }
  [ -n "$data_volume" ] && {
    echo "    volumes:" >>"$compose_file"
    echo "      - $data_volume" >>"$compose_file"
  }
  echo "    healthcheck:" >>"$compose_file"
  echo "      test: [\"CMD-SHELL\", \"${default_healthcheck}\"]" >>"$compose_file"
  echo "      interval: 30s" >>"$compose_file"
  echo "      retries: 3" >>"$compose_file"
  echo "      start_period: 10s" >>"$compose_file"

  # Show overview and confirm
  print_message "Overview of new service ${service_name}"
  message INFO "Container name: ${container_name}"
  message INFO "Image: ${image}"
  message INFO "Port mapping: ${external_port}:${default_port}"
  message INFO "Resources: CPU=${resource_cpus}, Memory=${resource_memory}"
  message INFO "Restart Policy: $restart_policy"
  [ -n "$data_volume" ] && message INFO "Mount Volumes: $data_volume"
  message INFO "Environment File: $env_file (check for credentials)"
  confirm_action "Do you want to proceed with enabling ${GREEN}${service_name}${NC}?" || {
    message INFO "Action canceled"
    return 0
  }

  # Start the service
  cd "$CONTAINER_DIR/services/$container_name" || return 1
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    message INFO "Pulling image ${image}"
    docker pull "${image}"
  fi
  message INFO "Starting service $service_name"
  if docker compose up -d; then
    message SUCCESS "Service $service_name enabled successfully"
    wait_for_health "${container_name}" "${service_name}" && docker ps -a --filter "name=${container_name}"
  else
    message ERROR "Failed to enable service $service_name"
    return 1
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
