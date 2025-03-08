#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

add_laravel() {
  message INFO "This feature is suitable for the situation where you already have another Laravel Application container with fully built source code, and want to configure Caddy Web Server to update the domain name. In case you need to build a Laravel application from scratch, use the command: infra-caddy laravel-up"

  if ! confirm_action "Are you sure you ${GREEN}understand the important note${NC} above and want to ${GREEN}continue${NC}?"; then
    message INFO "Adding Laravel site to Caddy configuration skipped"
    return 0
  fi

  local sites_path="$CONFIG_DIR/sites"

  # Ask for domain
  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(prompt_with_default "Enter domain name for Laravel site" "")
  fi
  [ -z "$domain" ] && {
    message ERROR "Domain name cannot be empty"
    return 1
  }

  # Check if domain already exists
  local domain_file="$sites_path/$domain.caddy"
  if [ -f "$domain_file" ]; then
    message ERROR "Domain $domain already exists in $sites_path"
    return 1
  fi

  # Ask for root directory
  local root_directory
  root_directory="/home/infra-caddy-sites/${domain}/html"
  [ -z "$root_directory" ] && {
    message ERROR "Root directory cannot be empty"
    return 1
  }
  if [ ! -d "$root_directory" ]; then
    message NOTE "If your application is PHP and needs to run with FPM (eg: Laravel, WordPress ...), you need to deploy your source code to the /home/infra-caddy-sites/<domain>/html directory for the application to work."
    message INFO "Please change your application to path ${root_directory} and try again."
    return
  fi

  # Ask for Laravel container and port
  local laravel_container
  laravel_container=$(prompt_with_default "Enter Laravel container name" "")
  [ -z "$laravel_container" ] && {
    message ERROR "Laravel container name cannot be empty"
    return 1
  }

  local laravel_container_port
  laravel_container_port=$(prompt_with_default "Enter Laravel container port" "9000")
  [ -z "$laravel_container_port" ] && {
    message ERROR "Laravel container port cannot be empty"
    return 1
  }

  # Check if container exists
  if ! docker ps -a --format '{{.Names}}' | grep -q "^$laravel_container$"; then
    message ERROR "Container $laravel_container does not exist"
    return 1
  fi

  docker exec -it "${laravel_container}" "chmod -R 777 /var/www/${domain}/html/storage"
  docker exec -it "${laravel_container}" "chmod -R 777 /var/www/${domain}/html/bootstrap/cache"
  join_caddy_network "${laravel_container}"

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

  # Create Laravel config
  cat >"$domain_file" <<EOF
${domain} {
${basic_auth_config}
    #tls internal
    root * ${root_directory}
    encode zstd gzip

    # Serve PHP files through php-fpm:
    php_fastcgi ${laravel_container}:${laravel_container_port}

    # Laravel Routing
    @notStatic {
        file {
            try_files {path} /index.php
        }
    }
    rewrite @notStatic /index.php?{query}

    # Enable the static file server:
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

  # Test Caddy syntax
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Laravel site for $domain added and Caddy reloaded"
  else
    rm -f "$domain_file"
    message ERROR "Invalid Caddy configuration, Laravel site not added"
    return 1
  fi
}

delete_laravel() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')

  if [ -z "$site_files" ]; then
    message INFO "No Laravel sites available to delete"
    return 0
  fi

  # Let user select site with fzf
  local selected_site
  if [ -n "$1" ]; then
    selected_site="$1"
  else
    selected_site=$(echo "$site_files" | fzf --prompt="Select Laravel site to delete (use up/down keys): ")
  fi
  if [ -z "$selected_site" ] || ! validate_domain "$selected_site"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  local site_file="$sites_path/$selected_site.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Laravel site $selected_site not found"
    return 1
  }

  # Backup before deletion
  local backup_file="$BACKUP_DIR/$selected_site.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$site_file" "$backup_file"
  message INFO "Backed up $selected_site.caddy to $backup_file"

  # Confirm deletion
  confirm_action "Do you want to delete Laravel site $selected_site?" || {
    message INFO "Deletion canceled"
    return 0
  }

  # Remove site file
  rm -f "$site_file"
  message INFO "Laravel site $selected_site deleted"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
  else
    message ERROR "Caddy configuration invalid after deletion"
    return 1
  fi
}
