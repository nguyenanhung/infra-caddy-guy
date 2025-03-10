#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

laravel_up_apache() {
  local sites_path="$CONFIG_DIR/sites"
  local laravel_base_dir="$CONTAINER_DIR/sites/laravel"

  # Ask for domain
  local domain="${1:-$(prompt_with_default "Enter domain name for Laravel site" "")}"
  [ -z "$domain" ] && {
    message ERROR "Domain name cannot be empty"
    return 1
  }
  local domain_file="$sites_path/$domain.caddy"
  [ -f "$domain_file" ] && {
    message ERROR "Domain $domain already exists in $sites_path"
    return 1
  }

  # Ask for PHP version
  local php_version="${2:-$(prompt_with_fzf "Select PHP version" "8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0")}"

  # Ask for source directory
  local source_dir="${3:-$(prompt_with_default "Enter Laravel source directory" "${CADDY_HOME_DIR}/${domain}/html")}"
  [ -z "$source_dir" ] && {
    message ERROR "Source directory cannot be empty"
    return 1
  }
  local install_laravel
  if [ ! -d "$source_dir" ]; then
    mkdir -p "$source_dir" || {
      message ERROR "Cannot create $source_dir"
      return 1
    }
    install_laravel="${4:-$(prompt_with_fzf "Source directory $source_dir is empty. Install new Laravel project?" "Yes No" "No")}"
  fi

  # Define network
  local sites_network_name="${PREFIX_NAME}_sites_${domain}_net"
  docker network create "$sites_network_name" --driver bridge 2>/dev/null || message INFO "Network $sites_network_name already exists"

  # Create directories and files
  local laravel_dir="$laravel_base_dir/$domain"
  mkdir -p "$laravel_dir"
  local compose_file="$laravel_dir/docker-compose.yml"
  local dockerfile="$laravel_dir/Dockerfile"

  # Create Dockerfile for PHP-Apache
  cat >"$dockerfile" <<EOF
FROM php:${php_version}-apache
RUN apt-get update && apt-get install -y \
    build-essential curl git unzip supervisor libpng-dev libjpeg-dev libwebp-dev zlib1g-dev \
    libzip-dev libxml2-dev libicu-dev libfreetype6-dev libpq-dev libmariadb-dev \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && docker-php-ext-configure gd --with-jpeg --with-webp --with-freetype \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql mysqli gd zip bcmath pcntl exif mbstring soap intl opcache \
    && pecl install redis && docker-php-ext-enable redis \
    && a2enmod rewrite # Enable mod_rewrite for Laravel
WORKDIR /var/www/html
COPY . /var/www/html
RUN chown -R www-data:www-data /var/www/html
EOF
  if [ "$install_laravel" = "Yes" ]; then
    cat >>"$dockerfile" <<EOF
RUN composer create-project laravel/laravel . --prefer-dist
RUN chmod -R 777 storage bootstrap/cache
EOF
  fi
  cat >>"$dockerfile" <<EOF
EXPOSE 80
CMD ["apache2-foreground"]
EOF

  # Create docker-compose.yml
  local include_docker_version
  include_docker_version=$(set_compose_version)
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
      - ${source_dir}:/var/www/html
    networks:
      - ${sites_network_name}
      - ${NETWORK_NAME}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost"]
      interval: 30s
      retries: 3
      start_period: 10s
EOF
  # Ask for Docker Internal Mapping
  print_message ""
  local ENABLE_HOST_DOCKER_INTERNAL="NO"
  message INFO "host.docker.internal:host-gateway is a way to access the host from within a Docker container without knowing the host's specific IP address.
      - It uses host-gateway , a special value that helps Docker map host.docker.internal to the host's IP address.
      - It helps containers that need to call APIs from the host machine (outside the Caddy Stack environment) or connect to services on the host such as database, web server, etc.
      - If you are unsure of the need or understanding of allowing Docker containers to call out to the host environment, you should not enable this configuration for safety and security reasons!"
  echo
  if confirm_action "Now that you have a good understanding of 'host.docker.internal', do you want to enable it?"; then
    ENABLE_HOST_DOCKER_INTERNAL="YES"
  fi
  if [[ "$ENABLE_HOST_DOCKER_INTERNAL" == "YES" ]]; then
    echo "    extra_hosts:" >>"${compose_file}"
    echo "      - \"host.docker.internal:host-gateway\"" >>"${compose_file}"
  fi
  # Start containers
  cd "$laravel_dir" || {
    message ERROR "Failed to change to directory $laravel_dir"
    return 1
  }
  docker compose up -d --build

  # Copy Laravel source if installed
  if [ "$install_laravel" = "Yes" ]; then
    message INFO "Copying Laravel source from container to $source_dir..."
    local container_name="${PREFIX_NAME}_sites_${domain}"
    if ! docker cp "$container_name:/var/www/html/." "$source_dir" 2>/dev/null; then
      message ERROR "Failed to copy Laravel source from $container_name to $source_dir"
      docker compose down
      return 1
    fi
    message INFO "Successfully copied Laravel source to $source_dir"
    docker compose restart
  fi

  # Wait for health
  wait_for_health "${PREFIX_NAME}_sites_${domain}" "Laravel Apache"

  # Configure Caddy
  local basic_auth_config=""
  if confirm_action "Enable ${GREEN}basic auth${NC} for this ${GREEN}Laravel Application${NC}?"; then
    local username password hashed_password
    username=$(prompt_with_default "Enter basic auth username" "auth-admin")
    password=$(prompt_with_default "Enter basic auth password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"
    hashed_password=$(docker exec "${CADDY_CONTAINER_NAME}" caddy hash-password --plaintext "$password" | tail -n 1)
    # Prepare basic auth config
    local auth_path=""
    if [ -n "$auth_path" ]; then
      basic_auth_config="@path_$auth_path {\n    path $auth_path\n}\nhandle @path_$auth_path {\n    basic_auth {\n        $username $hashed_password\n    }\n}"
    else
      basic_auth_config="@notAcme {\n    not path /.well-known/acme-challenge/*\n}\nbasic_auth @notAcme {\n    $username $hashed_password\n}"
    fi
  fi

  # Write caddy domain config
  local reverse_proxy_endpoint
  reverse_proxy_endpoint="${PREFIX_NAME}_sites_${domain}:80"

  cat >"$domain_file" <<EOF
${domain} {
${basic_auth_config}
    reverse_proxy ${reverse_proxy_endpoint}
    encode zstd gzip
    file_server {
        precompressed gzip
    }
    import file_static_caching
    import file_forbidden_restricted
    import header_security_php
}
EOF

  if caddy_validate && caddy_reload; then
    message INFO "Laravel site $domain (Apache) is up and running"
  else
    rm -f "$domain_file"
    docker compose down
    message ERROR "Failed to configure Caddy for $domain"
    return 1
  fi
}
