#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

node_up() {
  local sites_path="$CONFIG_DIR/sites"
  local node_base_dir="/home/infra-caddy-sites"

  # Domain: $1 or ask
  local domain="${1:-$(prompt_with_default "Enter domain name for Node.js app" "")}"
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  local compose_dir="$node_base_dir/$domain"
  local domain_file="$sites_path/$domain.caddy"
  [ -f "$domain_file" ] && {
    message ERROR "Domain $domain already exists in $sites_path"
    return 1
  }

  # Node port: $2 or ask
  local node_port="${2:-$(prompt_with_default "Enter port for Node.js app" "3000")}"

  # Node version: $3 or ask
  local node_version="${3:-$(prompt_with_fzf "Select Node.js version" "16 18 20 22")}"

  # Source directory: $4 or ask
  local source_dir="${4:-$(prompt_with_default "Enter source directory for Node.js app" "/home/$domain/node-app")}"
  [ ! -d "$source_dir" ] && { mkdir -p "$source_dir" || {
    message ERROR "Cannot create $source_dir"
    return 1
  }; }

  # Check and install NestJS if directory is empty
  local install_nestjs
  if [ -z "$(ls -A "$source_dir")" ]; then
    install_nestjs="${5:-$(prompt_with_fzf "Directory ${source_dir} is empty. Install NestJS?" "Yes No")}"
  fi

  # Ask for database (no args, always interactive for now)
  local use_db db_type db_separate db_container="db_${domain}" db_port
  use_db=$(prompt_with_fzf "Use a database?" "Yes No")
  if [ "$use_db" = "Yes" ]; then
    db_type=$(prompt_with_fzf "Select database type" "mariadb mysql percona mongodb postgresql")
    db_separate=$(prompt_with_fzf "Run database in a separate container?" "Yes No")
    if [ "$db_separate" = "Yes" ]; then
      db_container="db_${domain}_${db_type}"
      # Ask for DB port based on default
      case "$db_type" in
      "mariadb" | "mysql" | "percona") db_port=$(prompt_with_default "Enter port for $db_type" "3306") ;;
      "mongodb") db_port=$(prompt_with_default "Enter port for $db_type" "27017") ;;
      "postgresql") db_port=$(prompt_with_default "Enter port for $db_type" "5432") ;;
      esac
    else
      db_container="${PREFIX_NAME}_${db_type}"
    fi
  fi

  # Ask for cache (no args, always interactive for now)
  local use_cache cache_type cache_separate cache_container="cache_${domain}" cache_port
  use_cache=$(prompt_with_fzf "Use cache (Redis/Memcached)?" "Yes No")
  if [ "$use_cache" = "Yes" ]; then
    cache_type=$(prompt_with_fzf "Select cache type" "redis memcached")
    cache_separate=$(prompt_with_fzf "Run cache in a separate container?" "Yes No")
    if [ "$cache_separate" = "Yes" ]; then
      cache_container="cache_${domain}_${cache_type}"
      # Ask for cache port based on default
      case "$cache_type" in
      "redis") cache_port=$(prompt_with_default "Enter port for $cache_type" "6379") ;;
      "memcached") cache_port=$(prompt_with_default "Enter port for $cache_type" "11211") ;;
      esac
    else
      cache_container="${PREFIX_NAME}_${cache_type}"
    fi
  fi

  # Prepare directories and files
  mkdir -p "$compose_dir"
  local compose_file="$compose_dir/docker-compose.yml"
  local env_file="$compose_dir/.env"
  local dockerfile="$compose_dir/Dockerfile"
  local ecosystem_file="$source_dir/ecosystem.config.js"

  # Generate credentials for .env
  if [ "$use_db" = "Yes" ] || [ "$use_cache" = "Yes" ]; then
    cat >"$env_file" <<EOF
NODE_PORT=${node_port}
EOF
    # Database credentials
    if [ "$use_db" = "Yes" ]; then
      case "$db_type" in
      "mariadb" | "mysql")
        local db_root_password=$(generate_password)
        local db_user="node_${domain}"
        local db_password=$(generate_password)
        local db_database="node_db_${domain}"
        echo "DB_ROOT_PASSWORD=${db_root_password}" >>"$env_file"
        echo "DB_USER=${db_user}" >>"$env_file"
        echo "DB_PASSWORD=${db_password}" >>"$env_file"
        echo "DB_DATABASE=${db_database}" >>"$env_file"
        [ "$db_separate" = "Yes" ] && echo "DB_PORT=${db_port}" >>"$env_file"
        ;;
      "mongodb")
        local mongo_admin_user="admin_${domain}"
        local mongo_admin_password=$(generate_password)
        local mongo_db="node_db_${domain}"
        echo "MONGO_INITDB_ROOT_USERNAME=${mongo_admin_user}" >>"$env_file"
        echo "MONGO_INITDB_ROOT_PASSWORD=${mongo_admin_password}" >>"$env_file"
        echo "MONGO_INITDB_DATABASE=${mongo_db}" >>"$env_file"
        if [ "$db_separate" = "Yes" ]; then
          echo "MONGO_URL=mongodb://${mongo_admin_user}:${mongo_admin_password}@${db_container}:${db_port}/${mongo_db}?authSource=admin" >>"$env_file"
        else
          echo "# MONGO_URL will depend on shared container port" >>"$env_file"
        fi
        ;;
      "postgresql")
        local pg_user="node_${domain}"
        local pg_password=$(generate_password)
        local pg_database="node_db_${domain}"
        echo "POSTGRES_USER=${pg_user}" >>"$env_file"
        echo "POSTGRES_PASSWORD=${pg_password}" >>"$env_file"
        echo "POSTGRES_DB=${pg_database}" >>"$env_file"
        if [ "$db_separate" = "Yes" ]; then
          echo "PG_CONNECTION_STRING=postgres://${pg_user}:${pg_password}@${db_container}:${db_port}/${pg_database}" >>"$env_file"
        else
          echo "# PG_CONNECTION_STRING will depend on shared container port" >>"$env_file"
        fi
        ;;
      esac
    fi

    # Cache credentials
    if [ "$use_cache" = "Yes" ]; then
      case "$cache_type" in
      "redis")
        local redis_password=$(generate_password)
        echo "REDIS_PASSWORD=${redis_password}" >>"$env_file"
        if [ "$cache_separate" = "Yes" ]; then
          echo "REDIS_URL=redis://:${redis_password}@${cache_container}:${cache_port}" >>"$env_file"
        else
          echo "# REDIS_URL will depend on shared container port" >>"$env_file"
        fi
        ;;
      "memcached")
        echo "# Memcached does not support authentication by default" >>"$env_file"
        if [ "$cache_separate" = "Yes" ]; then
          echo "MEMCACHED_HOST=${cache_container}" >>"$env_file"
          echo "MEMCACHED_PORT=${cache_port}" >>"$env_file"
        else
          echo "# MEMCACHED_HOST and PORT will depend on shared container" >>"$env_file"
        fi
        ;;
      esac
    fi
  fi

  # Create Dockerfile (with conditional NestJS installation)
  cat >"$dockerfile" <<EOF
FROM node:${node_version}-alpine
WORKDIR /app
COPY . .
RUN npm install
RUN npm install -g pm2
EOF
  if [ "$install_nestjs" = "Yes" ]; then
    cat >>"$dockerfile" <<EOF
RUN npm install -g @nestjs/cli
RUN nest new . --skip-git --package-manager npm
EOF
  fi
  cat >>"$dockerfile" <<EOF
CMD ["pm2-runtime", "ecosystem.config.js"]
EOF

  if [ ! -f "$ecosystem_file" ]; then

    # Ask for Node.js endpoint (entry point script)
    local node_endpoint="${6:-$(prompt_with_default "Enter Node.js entry point script (e.g., app.js, main.js)" "main.js")}"
    [ -z "$node_endpoint" ] && {
      message ERROR "Node.js entry point cannot be empty"
      return 1
    }

    # Create ecosystem.config.js
    cat >"$ecosystem_file" <<EOF
module.exports = {
  apps: [{
    name: '${domain}',
    script: './${node_endpoint}',
    instances: 1,
    autorestart: true,
    watch: false,
    env: {
      NODE_ENV: 'production',
      PORT: ${node_port}
    }
  }]
};
EOF
  fi

  # Create docker-compose.yml
  local include_docker_version=$(set_compose_version)
  local sites_network_name="${PREFIX_NAME}_sites_${domain}_net"
  cat >"$compose_file" <<EOF
${include_docker_version}
networks:
  ${sites_network_name}:
    driver: bridge
  ${NETWORK_NAME}:
    external: true
services:
  ${PREFIX_NAME}_sites_${domain}:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: ${PREFIX_NAME}_sites_${domain}
    volumes:
      - ${source_dir}:/app
    networks:
      - ${sites_network_name}
      - ${NETWORK_NAME}
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "${node_port}"]
      interval: 30s
      retries: 3
      start_period: 10s
EOF
  if [ -f "$env_file" ]; then
    echo "    env_file:" >>"$compose_file"
    echo "      - .env" >>"$env_file"
  fi
  if [ "$use_db" = "Yes" ] || [ "$use_cache" = "Yes" ]; then
    echo "    depends_on:" >>"$compose_file"
    [ "$use_db" = "Yes" ] && echo "      - ${db_container}" >>"$compose_file"
    [ "$use_cache" = "Yes" ] && echo "      - ${cache_container}" >>"$compose_file"
  fi

  # Add database if separate
  if [ "$db_separate" = "Yes" ] && [ -n "$db_type" ]; then
    echo "  ${db_container}:" >>"$compose_file"
    echo "    image: ${SERVICE_IMAGES[$db_type]}" >>"$compose_file"
    echo "    container_name: ${db_container}" >>"$compose_file"
    echo "    volumes:" >>"$compose_file"
    echo "      - $CONFIG_DIR/${db_container}/data:${SERVICE_PORTS[$db_type]}" >>"$compose_file"
    echo "    ports:" >>"$compose_file"
    echo "      - \"${db_port}:${SERVICE_PORTS[$db_type]}\"" >>"$compose_file"
    echo "    networks:" >>"$compose_file"
    echo "      - ${sites_network_name}" >>"$compose_file"
    echo "    healthcheck:" >>"$compose_file"
    echo "      test: [\"CMD-SHELL\", \"${SERVICE_HEALTHCHECKS[$db_type]}\"]" >>"$compose_file"
    echo "      interval: 30s" >>"$compose_file"
    echo "      retries: 3" >>"$compose_file"
    echo "      start_period: 10s" >>"$compose_file"
    if [[ "$db_type" == "mariadb" || "$db_type" == "mysql" || "$db_type" == "mongodb" || "$db_type" == "postgresql" ]]; then
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
    fi
  fi

  # Add cache if separate
  if [ "$cache_separate" = "Yes" ] && [ -n "$cache_type" ]; then
    echo "  ${cache_container}:" >>"$compose_file"
    echo "    image: ${SERVICE_IMAGES[$cache_type]}" >>"$compose_file"
    echo "    container_name: ${cache_container}" >>"$compose_file"
    echo "    volumes:" >>"$compose_file"
    echo "      - $CONFIG_DIR/${cache_container}/data:${SERVICE_PORTS[$cache_type]}" >>"$compose_file"
    echo "    ports:" >>"$compose_file"
    echo "      - \"${cache_port}:${SERVICE_PORTS[$cache_type]}\"" >>"$compose_file"
    echo "    networks:" >>"$compose_file"
    echo "      - ${sites_network_name}" >>"$compose_file"
    echo "    healthcheck:" >>"$compose_file"
    echo "      test: [\"CMD-SHELL\", \"${SERVICE_HEALTHCHECKS[$cache_type]}\"]" >>"$compose_file"
    echo "      interval: 30s" >>"$compose_file"
    echo "      retries: 3" >>"$compose_file"
    echo "      start_period: 10s" >>"$compose_file"
    if [ "$cache_type" = "redis" ]; then
      echo "    env_file:" >>"$compose_file"
      echo "      - .env" >>"$compose_file"
    fi
  fi

  # Start containers and wait for health
  docker compose -f "$compose_file" up -d

  # If NestJS was installed, copy the generated source back to host
  if [ "$install_nestjs" = "Yes" ]; then
    message INFO "Copying NestJS source from container to $source_dir..."
    local container_name="${PREFIX_NAME}_sites_${domain}"
    if ! docker cp "$container_name:/app/." "$source_dir" 2>/dev/null; then
      message ERROR "Failed to copy NestJS source from $container_name to $source_dir"
      docker compose -f "$compose_file" down
      return 1
    fi
    message INFO "Successfully copied NestJS source to $source_dir"
    docker compose -f "$compose_file" restart
  fi

  if [ "$use_db" = "Yes" ]; then
    wait_for_health "$db_container" "$db_type"
  fi

  if [ "$use_cache" = "Yes" ]; then
    wait_for_health "$cache_container" "$cache_type"
  fi

  # Configure Caddy reverse proxy
  local backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  [ -f "$domain_file" ] && cp "$domain_file" "$backup_file"
  cat >"$domain_file" <<EOF
$domain {
    reverse_proxy http://${PREFIX_NAME}_sites_${domain}:${node_port}
}
EOF

  if caddy_validate && caddy_reload; then
    message INFO "Node.js app for $domain is up and running"
    [ -f "$env_file" ] && {
      message INFO "Credentials generated in $env_file:"
      cat "$env_file" | while IFS='=' read -r key value; do message INFO "  $key: $value"; done
      message INFO "Update your Node.js app config with these values if needed."
    }
  else
    rm -f "$domain_file"
    [ -f "$backup_file" ] && mv "$backup_file" "$domain_file"
    message ERROR "Failed to configure Caddy for $domain"
    return 1
  fi
}

node_down() {
  local sites_path="$CONFIG_DIR/sites"
  local domain="${1:-$(prompt_with_fzf "Select domain to take down" "$(ls -1 "$sites_path"/*.caddy | sed 's|.*/||;s|\.caddy||')")}"
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi
  local domain_file="$sites_path/$domain.caddy"
  [ ! -f "$domain_file" ] && {
    message ERROR "Domain $domain does not exist"
    return 1
  }
  local backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  rm -f "$domain_file"
  caddy_reload && message INFO "Caddy config for $domain removed, backed up to $backup_file" || {
    mv "$backup_file" "$domain_file"
    message ERROR "Failed to remove Caddy config for $domain"
    return 1
  }
}

node_restore() {
  local sites_path="$CONFIG_DIR/sites"
  local domain="${1:-$(prompt_with_fzf "Select domain to restore" "$(ls -1 "$sites_path"/*.caddy | sed 's|.*/||;s|\.caddy||')")}"
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi
  local domain_file="$sites_path/$domain.caddy"
  local backup_file=$(ls -1t "$BACKUP_DIR/$domain.caddy."* 2>/dev/null | head -n 1)
  [ -z "$backup_file" ] && {
    message ERROR "No backup found for $domain"
    return 1
  }
  [ -f "$domain_file" ] && {
    message ERROR "Domain $domain already exists in $sites_path"
    return 1
  }
  cp "$backup_file" "$domain_file"
  caddy_reload && message INFO "Caddy config for $domain restored from $backup_file" || {
    rm -f "$domain_file"
    message ERROR "Failed to restore Caddy config for $domain"
    return 1
  }
}

node_remove() {
  local sites_path="$CONFIG_DIR/sites"
  local node_base_dir="/home/infra-caddy-sites"
  local domain="${1:-$(prompt_with_fzf "Select domain to remove" "$(ls -1 "$sites_path"/*.caddy | sed 's|.*/||;s|\.caddy||')")}"
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi
  local domain_file="$sites_path/$domain.caddy"
  local compose_dir="$node_base_dir/$domain"
  local compose_file="$compose_dir/docker-compose.yml"
  [ ! -f "$domain_file" ] && {
    message ERROR "Domain $domain does not exist"
    return 1
  }
  local backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  rm -f "$domain_file"
  [ -f "$compose_file" ] && docker compose -f "$compose_file" down
  caddy_reload && message INFO "Node.js app for $domain removed, Caddy config backed up to $backup_file" || {
    mv "$backup_file" "$domain_file"
    message ERROR "Failed to remove Node.js app for $domain"
    return 1
  }
}
