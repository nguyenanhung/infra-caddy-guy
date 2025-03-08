#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

laravel_up() {
  local sites_path="$CONFIG_DIR/sites"
  local laravel_base_dir="$CONTAINER_DIR/sites/laravel"

  # Ask for domain
  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(prompt_with_default "Enter domain name for Laravel site" "")
    [ -z "$domain" ] && {
      message ERROR "Domain name cannot be empty"
      return 1
    }
  fi

  # Check if domain already exists
  local domain_file="$sites_path/$domain.caddy"
  if [ -f "$domain_file" ]; then
    message ERROR "Domain $domain already exists in $sites_path"
    return 1
  fi

  # Ask for database usage
  local use_db
  use_db=$(prompt_with_fzf "Use a database for Application?" "Yes No")
  local db_type=""
  local db_separate=""
  local db_container=""
  if [ "$use_db" = "Yes" ]; then
    db_type=$(prompt_with_fzf "Select database type" "mariadb mongodb postgresql")
    db_separate=$(prompt_with_fzf "Create separate database container?" "Yes No")
    if [ "$db_separate" = "Yes" ]; then
      db_container="db_${domain}_${db_type}"
    else
      db_container="${PREFIX_NAME}_${db_type}"
    fi
  fi

  # Ask for cache usage
  local use_cache
  use_cache=$(prompt_with_fzf "Use cache (Redis/Memcached)?" "Yes No")
  local cache_type=""
  local cache_separate=""
  local cache_container=""
  if [ "$use_cache" = "Yes" ]; then
    cache_type=$(prompt_with_fzf "Select cache type" "redis memcached")
    cache_separate=$(prompt_with_fzf "Create separate cache container?" "Yes No")
    if [ "$cache_separate" = "Yes" ]; then
      cache_container="cache_${domain}_${cache_type}"
    else
      cache_container="${PREFIX_NAME}_${cache_type}"
    fi
  fi

  # Ask for worker/scheduler
  local use_worker
  use_worker=$(prompt_with_fzf "Run worker/scheduler? Do not turn on if not really necessary!" "Yes No")
  local worker_separate=""
  local worker_container=""
  if [ "$use_worker" = "Yes" ]; then
    worker_separate=$(prompt_with_fzf "Create separate worker/scheduler container?" "Yes No")
    if [ "$worker_separate" = "Yes" ]; then
      worker_container="${PREFIX_NAME}_sites_cli_${domain}"
    fi
  fi

  # Ask for PHP version
  local php_version
  php_version=$(prompt_with_fzf "Select PHP version" "8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0")

  # Ask for source directory
  local source_dir
  source_dir=$(prompt_with_default "Enter Laravel source directory" "/home/infra-caddy-sites/${domain}/html")
  [ -z "$source_dir" ] && {
    message ERROR "Source directory cannot be empty"
    return 1
  }
  if [ ! -d "$source_dir" ]; then
    if confirm_action "Laravel source directory does not exist yet. Do you want to start new Laravel project in the directory?"; then
      if ! has_command composer; then
        message ERROR "Composer is not installed. Please install Composer first."
        return 1
      fi
      sudo mkdir -p "$source_dir"
      if [ ! -d "$source_dir" ]; then
        message ERROR "Failed to create directory $source_dir"
        return 1
      fi
      sudo env COMPOSER_ALLOW_SUPERUSER=1 composer create-project laravel/laravel "${source_dir}"
      sudo chown -R "${USER}:${USER}" "${source_dir}"
      sudo chmod -R 777 "${source_dir}/storage"
      sudo chmod -R 777 "${source_dir}/bootstrap/cache"
    fi
  else
    sudo mkdir -p "$source_dir"
  fi

  # Define network
  local sites_network_name="${PREFIX_NAME}_sites_${domain}_net"
  docker network create "$sites_network_name" --driver bridge 2>/dev/null || message INFO "Network $sites_network_name already exists"

  # Create Dockerfile for Laravel PHP-FPM
  local laravel_dir="$laravel_base_dir/$domain"
  mkdir -p "$laravel_dir"
  cat >"$laravel_dir/Dockerfile" <<EOF
FROM php:${php_version}-fpm-alpine
RUN apk add --no-cache build-base  bash netcat-openbsd curl git unzip supervisor \\
    libpng-dev libjpeg-turbo-dev libwebp-dev zlib-dev libzip-dev libxml2-dev icu-dev freetype-dev libpq \\
    postgresql-dev mariadb-connector-c-dev autoconf pkgconfig g++ make oniguruma-dev openssl-dev inotify-tools \\
    zip jpegoptim optipng pngquant gifsicle unzip \\
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \\
    && docker-php-ext-configure gd --with-jpeg --with-webp \\
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql mysqli gd zip bcmath pcntl exif mbstring soap intl opcache gd \\
    && pecl install redis && docker-php-ext-enable redis
WORKDIR /var/www/${domain}/html
EXPOSE 9000
CMD ["php-fpm"]
EOF

  # Create Dockerfile for worker/scheduler if separate
  if [ "$worker_separate" = "Yes" ]; then
    cat >"$laravel_dir/Dockerfile.cli" <<EOF
FROM php:${php_version}-cli-alpine
RUN apk add --no-cache build-base  bash netcat-openbsd curl git unzip supervisor \\
    libpng-dev libjpeg-turbo-dev libwebp-dev zlib-dev libzip-dev libxml2-dev icu-dev freetype-dev libpq \\
    postgresql-dev mariadb-connector-c-dev autoconf pkgconfig g++ make oniguruma-dev openssl-dev inotify-tools \\
    zip jpegoptim optipng pngquant gifsicle unzip \\
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \\
    && docker-php-ext-configure gd --with-jpeg --with-webp \\
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql mysqli gd zip bcmath pcntl exif mbstring soap intl opcache gd \\
    && pecl install redis && docker-php-ext-enable redis
WORKDIR /var/www/${domain}/html
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
EOF
    # Create supervisord.conf for worker/scheduler
    cat >"$laravel_dir/supervisord.conf" <<EOF
[supervisord]
nodaemon=true

[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php artisan queue:work --sleep=3 --tries=3
directory=/var/www/${domain}/html
autostart=true
autorestart=true
user=root
numprocs=2
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:laravel-scheduler]
process_name=%(program_name)s_%(process_num)02d
command=php artisan schedule:work --verbose --no-interaction
directory=/var/www/${domain}/html
autostart=true
autorestart=true
user=root
numprocs=1
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
  fi

  # Create docker-compose.yml
  local compose_file="$laravel_dir/docker-compose.yml"

  # Get the compose version dynamically
  local include_docker_version
  include_docker_version=$(set_compose_version)

  # Write compose file with dynamic version
  cat >"$compose_file" <<EOF
${include_docker_version}
networks:
  ${sites_network_name}:
    driver: bridge
  ${PREFIX_NAME}_caddy_net:
    external: true
services:
  ${PREFIX_NAME}_sites_${domain}:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: ${PREFIX_NAME}_sites_${domain}
    volumes:
      - ${source_dir}:/var/www/${domain}/html
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - ${sites_network_name}
      - ${NETWORK_NAME}
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "9000"]
      interval: 30s
      retries: 3
      start_period: 10s
EOF

  # Combine depends_on into a single block for the main Laravel service
  if [ "$use_db" = "Yes" ] || [ "$use_cache" = "Yes" ]; then
    echo "    depends_on:" >>"$compose_file"
    if [ "$use_db" = "Yes" ]; then
      echo "      - ${db_container}" >>"$compose_file"
    fi
    if [ "$use_cache" = "Yes" ]; then
      echo "      - ${cache_container}" >>"$compose_file"
    fi
  fi

  # Add database if separate
  if [ "$db_separate" = "Yes" ] && [ -n "$db_type" ]; then
    echo "  ${db_container}:" >>"$compose_file"
    echo "    image: ${SERVICE_IMAGES[$db_type]}" >>"$compose_file"
    echo "    container_name: ${db_container}" >>"$compose_file"
    echo "    volumes:" >>"$compose_file"
    echo "      - $CONFIG_DIR/${db_container}/data:${SERVICE_PORTS[$db_type]}" >>"$compose_file"
    echo "    networks:" >>"$compose_file"
    echo "      - ${sites_network_name}" >>"$compose_file"
    echo "    healthcheck:" >>"$compose_file"
    echo "      test: [\"CMD-SHELL\", \"${SERVICE_HEALTHCHECKS[$db_type]}\"]" >>"$compose_file"
    echo "      interval: 30s" >>"$compose_file"
    echo "      retries: 3" >>"$compose_file"
    echo "      start_period: 10s" >>"$compose_file"
    if [[ "$db_type" == "mariadb" || "$db_type" == "mysql" || "$db_type" == "percona" ]]; then
      echo "    environment:" >>"$compose_file"
      echo "      - MYSQL_ROOT_PASSWORD=$(generate_password)" >>"$compose_file"
      echo "      - MYSQL_DATABASE=laravel_db_${domain}" >>"$compose_file"
      echo "      - MYSQL_USER=laravel_admin_${domain}" >>"$compose_file"
      echo "      - MYSQL_PASSWORD=$(generate_password)" >>"$compose_file"
    fi
  fi

  # Add cache if separate
  if [ "$cache_separate" = "Yes" ] && [ -n "$cache_type" ]; then
    echo "  ${cache_container}:" >>"$compose_file"
    echo "    image: ${SERVICE_IMAGES[$cache_type]}" >>"$compose_file"
    echo "    container_name: ${cache_container}" >>"$compose_file"
    echo "    volumes:" >>"$compose_file"
    echo "      - $CONFIG_DIR/${cache_container}/data:${SERVICE_PORTS[$cache_type]}" >>"$compose_file"
    echo "    networks:" >>"$compose_file"
    echo "      - ${sites_network_name}" >>"$compose_file"
    echo "    healthcheck:" >>"$compose_file"
    echo "      test: [\"CMD-SHELL\", \"${SERVICE_HEALTHCHECKS[$cache_type]}\"]" >>"$compose_file"
    echo "      interval: 30s" >>"$compose_file"
    echo "      retries: 3" >>"$compose_file"
    echo "      start_period: 10s" >>"$compose_file"
  fi

  # Add worker/scheduler if separate
  if [ "$worker_separate" = "Yes" ]; then
    echo "  ${worker_container}:" >>"$compose_file"
    echo "    build:" >>"$compose_file"
    echo "      context: ." >>"$compose_file"
    echo "      dockerfile: Dockerfile.cli" >>"$compose_file"
    echo "    container_name: ${worker_container}" >>"$compose_file"
    echo "    volumes:" >>"$compose_file"
    echo "      - ${source_dir}:/var/www/${domain}/html" >>"$compose_file"
    # echo "      - ${source_dir}/.env.production:/var/www/${domain}/html/.env" >>"$compose_file"
    echo "    extra_hosts:" >>"$compose_file"
    echo "      - \"host.docker.internal:host-gateway\"" >>"$compose_file"
    echo "    networks:" >>"$compose_file"
    echo "      - ${sites_network_name}" >>"$compose_file"
    echo "    healthcheck:" >>"$compose_file"
    echo "      test: [\"CMD\", \"supervisorctl\", \"status\"]" >>"$compose_file"
    echo "      interval: 30s" >>"$compose_file"
    echo "      retries: 3" >>"$compose_file"
    echo "      start_period: 10s" >>"$compose_file"
    # Combine depends_on into a single block
    if [ "$use_db" = "Yes" ] || [ "$use_cache" = "Yes" ]; then
      echo "    depends_on:" >>"$compose_file"
      if [ "$use_db" = "Yes" ]; then
        echo "      - ${db_container}" >>"$compose_file"
      fi
      if [ "$use_cache" = "Yes" ]; then
        echo "      - ${cache_container}" >>"$compose_file"
      fi
    fi
  fi

  # Start containers and wait for health
  cd "$laravel_dir" || {
    message ERROR "Failed to change to directory $laravel_dir"
    return 1
  }
  if ! docker-compose up -d; then
    message ERROR "Failed to start containers with docker-compose"
    return 1
  fi

  # Wait for health of separate database container if applicable
  if [ "$db_separate" = "Yes" ] && [ -n "$db_type" ]; then
    wait_for_health "$db_container" "$db_type"
  fi

  # Wait for health of separate cache container if applicable
  if [ "$cache_separate" = "Yes" ] && [ -n "$cache_type" ]; then
    wait_for_health "$cache_container" "$cache_type"
  fi

  # Wait for health of Laravel PHP-FPM container
  wait_for_health "${PREFIX_NAME}_sites_${domain}" "Laravel PHP-FPM"
  docker exec -it "${PREFIX_NAME}_sites_${domain}" chmod -R 777 "/var/www/${domain}/html/storage"
  docker exec -it "${PREFIX_NAME}_sites_${domain}" chmod -R 777 "/var/www/${domain}/html/bootstrap/cache"

  # Wait for health of worker/scheduler container if separate
  if [ "$worker_separate" = "Yes" ]; then
    wait_for_health "${PREFIX_NAME}_sites_cli_${domain}" "Laravel Worker/Scheduler"
    docker exec -it "${PREFIX_NAME}_sites_cli_${domain}" chmod -R 777 "/var/www/${domain}/html/storage"
    docker exec -it "${PREFIX_NAME}_sites_cli_${domain}" chmod -R 777 "/var/www/${domain}/html/bootstrap/cache"
  fi

  # Ask if user wants basic auth
  local basic_auth_config=""
  if confirm_action "Enable ${GREEN}basic auth${NC} for this ${GREEN}Laravel Application${NC}?"; then
    # Ask for username and password
    local username
    username=$(prompt_with_default "Enter basic auth username" "auth-admin")
    local password
    password=$(prompt_with_default "Enter basic auth password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"

    # Generate hashed password
    local hashed_password
    hashed_password=$(docker exec "${PREFIX_NAME}_caddy" caddy hash-password --plaintext "$password" | tail -n 1)

    # Prepare basic auth config
    basic_auth_config="    basic_auth {\n        $username $hashed_password\n    }"
  fi

  # Create Caddy config
  cat >"$domain_file" <<EOF
${domain} {
${basic_auth_config}
    #tls internal
    root * /var/www/${domain}/html/public
    encode zstd gzip

    php_fastcgi ${PREFIX_NAME}_sites_${domain}:9000

    @notStatic {
        file {
            try_files {path} /index.php
        }
    }
    rewrite @notStatic /index.php?{query}

    file_server {
        precompressed gzip
    }

    header / {
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE"
        Access-Control-Allow-Headers "Content-Type, X-CSRF-TOKEN"
    }

    import file_static_caching
    import file_forbidden_restricted
    import wordpress
}
EOF

  # Test and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Laravel site $domain set up and Caddy reloaded"
  else
    rm -f "$domain_file"
    docker-compose down
    message ERROR "Invalid Caddy configuration, Laravel setup aborted"
    return 1
  fi
}

laravel_down() {
  local sites_path="$CONFIG_DIR/sites"

  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message INFO "No Laravel sites available to delete"
    return 0
  fi

  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(echo "$site_files" | fzf --prompt="Select Laravel site to delete Caddy config (use up/down keys): ")
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  local site_file="$sites_path/$domain.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Site $domain not found"
    return 1
  }

  # Backup before deletion
  local backup_file
  backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$site_file" "$backup_file"
  message INFO "Backed up $domain.caddy to $backup_file"

  # Confirm deletion
  confirm_action "Do you want to delete Caddy config for $domain?" || {
    message INFO "Deletion canceled"
    return 0
  }

  rm -f "$site_file"
  message INFO "Caddy config for $domain deleted"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
  else
    message ERROR "Caddy configuration invalid after deletion"
    return 1
  fi
}

laravel_restore() {
  local sites_path="$CONFIG_DIR/sites"

  local backup_files
  backup_files=$(find "$BACKUP_DIR" -type f -name "*.caddy.*" -exec basename {} \; | sed 's/\.caddy\..*//g' | sort -u)
  if [ -z "$backup_files" ]; then
    message INFO "No backup files available to restore"
    return 0
  fi

  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(echo "$backup_files" | fzf --prompt="Select Laravel site to restore (use up/down keys): ")
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  local latest_backup
  latest_backup=$(find "$BACKUP_DIR" -type f -name "$domain.caddy.*" | sort -r | head -n 1)
  if [ -z "$latest_backup" ]; then
    message ERROR "No backup found for $domain"
    return 1
  fi

  local site_file="$sites_path/$domain.caddy"
  if [ -f "$site_file" ]; then
    message ERROR "Site $domain already exists, cannot restore"
    return 1
  fi

  cp "$latest_backup" "$site_file"
  message INFO "Restored $domain from $latest_backup"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
  else
    rm -f "$site_file"
    message ERROR "Invalid Caddy configuration after restore, restoration aborted"
    return 1
  fi
}

laravel_remove() {
  local sites_path="$CONFIG_DIR/sites"
  local laravel_base_dir="$CONTAINER_DIR/sites/laravel"

  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message INFO "No Laravel sites available to remove"
    return 0
  fi

  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(echo "$site_files" | fzf --prompt="Select Laravel site to remove (use up/down keys): ")
  fi

  if [ -z "$domain" ] || ! validate_domain "$domain"; then
  message INFO "No site selected"
  return 0
fi

  local site_file="$sites_path/$domain.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Site $domain not found"
    return 1
  }

  # Backup before deletion
  local backup_file
  backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$site_file" "$backup_file"
  message INFO "Backed up $domain.caddy to $backup_file"

  # Confirm removal
  confirm_action "Do you want to remove Laravel site $domain (including containers)?" || {
    message INFO "Removal canceled"
    return 0
  }

  # Stop and remove containers
  local laravel_dir="$laravel_base_dir/$domain"
  cd "$laravel_dir" || return 1
  docker-compose down
  message INFO "Stopped and removed containers for $domain"

  # Remove Caddy config
  rm -f "$site_file"
  message INFO "Caddy config for $domain deleted"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
  else
    message ERROR "Caddy configuration invalid after removal"
    return 1
  fi
}
