#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

setup_caddy() {
  check_docker

  # Define locations inside config/
  local caddy_compose_path_origin
  local caddy_compose_path
  local caddyfile_path
  local sites_path
  local certs_path
  local data_path
  local config_path
  local infra_caddy_sites_path
  caddy_compose_path_origin="${CONFIG_DIR}/docker-compose.yml"
  caddy_compose_path="${CONFIG_DIR}/docker-compose.yml"
  caddyfile_path="${CONFIG_DIR}/Caddyfile"
  sites_path="${CONFIG_DIR}/sites"
  certs_path="${CONFIG_DIR}/certs"
  data_path="${CONFIG_DIR}/caddy_data"
  config_path="${CONFIG_DIR}/caddy_config"
  infra_caddy_sites_path="${CADDY_HOME_DIR}"

  # Ensure required directories exist
  [ ! -d "$sites_path" ] && mkdir -p "$sites_path"
  [ ! -d "$certs_path" ] && mkdir -p "$certs_path"
  [ ! -d "$data_path" ] && mkdir -p "$data_path"
  [ ! -d "$config_path" ] && mkdir -p "$config_path"
  [ ! -d "$infra_caddy_sites_path" ] && sudo mkdir -p "$infra_caddy_sites_path" && sudo chown -R root:docker "$infra_caddy_sites_path"

  # Create default Caddyfile if not exists
  if [ ! -f "$caddyfile_path" ]; then
    cat >"$caddyfile_path" <<EOF
{
    # Global options
    admin off
    persist_config off
}
# Some static files Cache-Control.
(file_static_caching) {
	@static {
		path *.ico *.css *.js *.gif *.jpg *.jpeg *.png *.svg *.woff *.json
	}
	header @static Cache-Control max-age=2592000
}
# Security
(file_forbidden_restricted) {
    @forbidden {
        # Allowed
        not path /wp-includes/ms-files.php

        # Global Restricted
        path /.user.ini
        path /.htaccess
        path /web.config
        path /.env
        path /wp-config.php

        # Restricted file
        path /wp-admin/includes/*.php
        path /wp-includes/*.php
        path /wp-content/uploads/*.php
        path /wp-content/debug.log
        path /storage/logs/*.log

        # Laravel
        path /config/*.php
        path /storage/*
        path /vendor/*
        path /node_modules/*
        path /backup/*
        path /database/*
    }
    respond @forbidden "Access denied" 403
}

# Improve Header security
(header_security_default) {
    header {
        # Click-jacking protection
        # X-Frame-Options "SAMEORIGIN"

        # Disable clients from sniffing the media type
        X-Content-Type-Options "nosniff"
        Content-Security-Policy "upgrade-insecure-requests"

        # Keep referrer data off of HTTP connections
        Referrer-Policy no-referrer-when-downgrade

        # Enable HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

        # Enable XSS protection
        X-Xss-Protection "1; mode=block"

        # Hide server name
        -Server Caddy

        # CORS settings
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE"
        Access-Control-Allow-Headers "Content-Type, X-CSRF-TOKEN"
    }
}

(header_security_common) {
    header {
        # X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        -Server
    }
}

(header_security_php) {
    import header_security_common
    header {
        Content-Security-Policy "upgrade-insecure-requests"
        X-Xss-Protection "1; mode=block"
    }
}

(header_security_api) {
    import header_security_common
    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE"
        Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With"
    }
}

(header_security_spa) {
    import header_security_common
    header {
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;"
    }
}

(header_security_static) {
    import header_security_common
    header {
        Cache-Control "public, max-age=86400, immutable"
    }
}

(header_security_reverse_proxy) {
    import header_security_common
    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS, PUT, DELETE"
        Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With"
    }
}

# WordPress
(wordpress) {
	# Cache Enabler
	@cache_enabler {
		not header_regexp Cookie "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_logged_in"
		not path_regexp "(/wp-admin/|/xmlrpc.php|/wp-(app|cron|login|register|mail).php|wp-.*.php|/feed/|index.php|wp-comments-popup.php|wp-links-opml.php|wp-locations.php|sitemap(index)?.xml|[a-z0-9-]+-sitemap([0-9]+)?.xml)"
		not method POST
		not expression {query} != ''
	}

	route @cache_enabler {
		try_files /wp-content/cache/cache-enabler/{host}{uri}/https-index.html /wp-content/cache/cache-enabler/{host}{uri}/index.html {path} {path}/index.php?{query}
	}
}

# Site configurations will be imported below
import sites/*.caddy

EOF
    message INFO "Default Caddyfile created"
  fi

  # Create network if not exists
  local network_check
  docker network ls | grep -q "$NETWORK_NAME"
  network_check=$?
  if [ "$network_check" -ne 0 ]; then
    docker network create "$NETWORK_NAME"
    message INFO "Network $NETWORK_NAME created"
  fi

  # Check if Caddy container exists
  local container_check
  docker ps -a | grep -q "${CADDY_CONTAINER_NAME}"
  container_check=$?
  if [ "$container_check" -ne 0 ]; then
    local image
    image=$(prompt_with_default "Enter Caddy image" "$(get_mapping_value SERVICE_IMAGES caddy)")
    if ! docker image inspect "$image" >/dev/null 2>&1; then
      message INFO "Pulling image ${image}"
      docker pull "${image}"
    fi

    # Ask the container call to host-gateway

    # Create default docker-compose.yml if not already
    if [ ! -f "$caddy_compose_path" ]; then
      local include_docker_version
      include_docker_version=$(set_compose_version)
      cat >"${caddy_compose_path}" <<EOF
${include_docker_version}

networks:
  ${NETWORK_NAME}:
    external: true

services:
  ${CADDY_CONTAINER_NAME}:
    container_name: "${CADDY_CONTAINER_NAME}"
    image: "${image}"
    restart: unless-stopped
    networks:
      - "${NETWORK_NAME}"
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - "${caddyfile_path}:/etc/caddy/Caddyfile"
      - "${certs_path}:/etc/caddy/certs"
      - "${sites_path}:/etc/caddy/sites"
      - "${data_path}:/data"
      - "${config_path}:/config"
      - "${infra_caddy_sites_path}:/var/www"
    logging:
      driver: "${DEFAULT_CONTAINER_LOG_DRIVER}"
      options:
        max-size: "${DEFAULT_CONTAINER_LOG_MAX_SIZE}"
        max-file: "${DEFAULT_CONTAINER_LOG_MAX_FILE}"
    healthcheck:
      test: ["CMD", "pgrep", "caddy"]
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
        echo "    extra_hosts:" >>"${caddy_compose_path}"
        echo "      - \"host.docker.internal:host-gateway\"" >>"${caddy_compose_path}"
      fi
      message INFO "Default docker-compose.yml created at ${caddy_compose_path}"
    fi

    cd "$CONFIG_DIR" || {
      message ERROR "Failed go to ${CONFIG_DIR}"
      return 1
    }

    # Create Caddy container
    message INFO "Creating Caddy container"
    if [[ "${caddy_compose_path}" == "${caddy_compose_path_origin}" ]]; then
      docker_compose_command up -d --remove-orphans
    else
      docker_compose_command -f "${caddy_compose_path}" up -d --remove-orphans
    fi
    message SUCCESS "Caddy container ${CADDY_CONTAINER_NAME} created successfully"

    if wait_for_health "${CADDY_CONTAINER_NAME}" "Caddy Web Server"; then
      echo
      docker ps -a --filter "name=${CADDY_CONTAINER_NAME}"
      docker exec -it "${CADDY_CONTAINER_NAME}" apk add --no-cache netcat-openbsd curl # Install netcat-openbsd, curl for testing purposes
      docker exec -it "${CADDY_CONTAINER_NAME}" nc -zv host.docker.internal 80         # Test Caddy call to internal host
      echo
      message NOTE "If your application is PHP and needs to run with FPM (eg: Laravel, WordPress ...), you need to deploy your source code to the ${CADDY_HOME_DIR}/<domain>/html directory for the application to work. Other applications like NodeJS, ReactJS can use reverse-proxy so you can deploy anywhere."
    else
      message ERROR "Caddy container ${CADDY_CONTAINER_NAME} failed to start"
    fi
  else
    message INFO "Caddy container ${CADDY_CONTAINER_NAME} already exists"
  fi
}

restart_caddy() {
  if caddy_validate; then
    caddy_reload
  else
    message ERROR "Caddy configuration is not valid"
    return 1
  fi
}

# Helper function to list sites
list_sites() {
  find "$CONFIG_DIR/sites" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//'
}

# Helper function to get related containers for a site
get_site_containers() {
  local domain="$1"
  docker ps -a --format '{{.Names}}' | grep -E "^${PREFIX_NAME}_sites_${domain}$|^${PREFIX_NAME}_sites_cli_${domain}$|^db_${domain}$|^cache_${domain}$"
}

delete_site() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')

  if [ -z "$site_files" ]; then
    message INFO "No sites available to delete"
    return 0
  fi

  local selected_site
  if [ -n "$1" ]; then
    selected_site="$1"
  else
    # Let user select site with fzf
    selected_site=$(echo "$site_files" | fzf --prompt="Select site to delete (use up/down keys): ")
  fi
  if [ -z "$selected_site" ] || ! validate_domain "$selected_site"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  local site_file="$sites_path/$selected_site.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Site $selected_site not found"
    return 1
  }

  # Backup before deletion
  local backup_file
  backup_file="$BACKUP_DIR/$selected_site.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$site_file" "$backup_file"
  message INFO "Backed up $selected_site.caddy to $backup_file"

  # Confirm deletion
  confirm_action "Do you want to delete site $selected_site?" || {
    message INFO "Deletion canceled"
    return 0
  }

  # Remove site file
  rm -f "$site_file"
  message INFO "Site $selected_site deleted"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
  else
    message ERROR "Caddy configuration invalid after deletion"
    return 1
  fi
}

stop_site() {
  local stop_choice
  local selected_site
  if [ -n "$1" ]; then
    selected_site="$1"
    stop_choice="Stop one site"
  else
    local stop_options="Stop all sites Stop one site"
    stop_choice=$(echo "$stop_options" | fzf --prompt="Select stop option: ")
  fi
  if [ "$stop_choice" = "Stop all sites" ]; then
    docker stop "${CADDY_CONTAINER_NAME}" && message INFO "Caddy web server stopped"
    local sites
    sites=$(list_sites)
    if [ -n "$sites" ]; then
      for domain in $sites; do
        local containers
        containers=$(get_site_containers "$domain")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker stop && message INFO "Stopped containers for $domain"
        fi
      done
    else
      message INFO "No sites found to stop"
    fi
  elif [ "$stop_choice" = "Stop one site" ]; then
    local sites
    sites=$(list_sites)
    if [ -z "$sites" ]; then
      message INFO "No sites available to stop"
    else
      if [ -z "$selected_site" ]; then
        selected_site=$(echo "$sites" | fzf --prompt="Select site to stop (use up/down keys): ")
      fi
      if [ -n "$selected_site" ]; then
        local containers
        containers=$(get_site_containers "$selected_site")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker stop && message INFO "Stopped containers for $selected_site"
        else
          message INFO "No containers found for $selected_site"
        fi
      else
        message INFO "No site selected"
      fi
    fi
  fi
}

start_site() {
  local start_choice
  local selected_site
  if [ -n "$1" ]; then
    selected_site="$1"
    start_choice="Start one site"
  else
    local start_options="Start all sites Start one site"
    start_choice=$(echo "$start_options" | fzf --prompt="Select start option: ")
  fi

  if [ "$start_choice" = "Start all sites" ]; then
    local sites
    sites=$(list_sites)
    if [ -n "$sites" ]; then
      for domain in $sites; do
        local containers
        containers=$(get_site_containers "$domain")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker start && message INFO "Started containers for $domain"
          join_caddy_network "$containers"
        fi
      done
    else
      message INFO "No sites found to start"
    fi
    docker start "${CADDY_CONTAINER_NAME}" && message INFO "Caddy web server started"
  elif [ "$start_choice" = "Start one site" ]; then
    local sites
    sites=$(list_sites)
    if [ -z "$sites" ]; then
      message INFO "No sites available to start"
    else
      if [ -z "$selected_site" ]; then
        selected_site=$(echo "$sites" | fzf --prompt="Select site to start (use up/down keys): ")
      fi
      if [ -n "$selected_site" ]; then
        local containers
        containers=$(get_site_containers "$selected_site")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker start && message INFO "Started containers for $selected_site"
          join_caddy_network "$containers"
        else
          message INFO "No containers found for $selected_site"
        fi
      else
        message INFO "No site selected"
      fi
    fi
  fi
}

restart_site() {
  local restart_choice
  local selected_site
  if [ -n "$1" ]; then
    selected_site="$1"
    restart_choice="Restart one site"
  else
    local restart_options="Restart all sites Restart one site"
    restart_choice=$(echo "$restart_options" | fzf --prompt="Select restart option: ")
  fi
  if [ "$restart_choice" = "Restart all sites" ]; then
    local sites
    sites=$(list_sites)
    if [ -n "$sites" ]; then
      for domain in $sites; do
        local containers
        containers=$(get_site_containers "$domain")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker restart && message INFO "Restarted containers for $domain"
          join_caddy_network "$containers"
        fi
      done
    else
      message INFO "No sites found to restart"
    fi
    docker restart "${CADDY_CONTAINER_NAME}" && message INFO "Caddy web server restarted"
  elif [ "$restart_choice" = "Restart one site" ]; then
    local sites
    sites=$(list_sites)
    if [ -z "$sites" ]; then
      message INFO "No sites available to restart"
    else
      if [ -z "$selected_site" ]; then
        selected_site=$(echo "$sites" | fzf --prompt="Select site to restart (use up/down keys): ")
      fi
      if [ -n "$selected_site" ]; then
        local containers
        containers=$(get_site_containers "$selected_site")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker restart && message INFO "Restarted containers for $selected_site"
          join_caddy_network "$containers"
        else
          message INFO "No containers found for $selected_site"
        fi
      else
        message INFO "No site selected"
      fi
    fi
  fi
}

add_basic_auth() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files for selection
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message ERROR "No domains available to enable basic auth"
    return 1
  fi

  # Ask for domain with fzf
  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(echo "$site_files" | fzf --prompt="Select domain to enable basic auth (use up/down keys): ")
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  # Check if domain exists
  local domain_file="$sites_path/$domain.caddy"
  if [ ! -f "$domain_file" ]; then
    message ERROR "Domain $domain does not exist in $sites_path"
    return 1
  fi

  # Ask for username and password
  local username
  username=$(prompt_with_default "Enter basic auth username" "auth-admin")
  local password
  password=$(prompt_with_default "Enter basic auth password (leave blank for random)" "")
  [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"

  # Ask for scope (whole site or specific path)
  local scope_choice
  scope_choice=$(prompt_with_fzf "Apply basic auth to whole site or specific path?" "Whole-site Specific-path")
  local auth_path=""
  if [ "$scope_choice" = "Specific-path" ]; then
    auth_path=$(prompt_with_default "Enter path to protect (e.g., /admin)" "")
    [ -z "$auth_path" ] && {
      message ERROR "Path cannot be empty"
      return 1
    }
  fi

  # Check if username already exists in config
  local existing_auth
  if [ -n "$auth_path" ]; then
    existing_auth=$(grep -A 2 "basic_auth" "$domain_file" | grep "$username" || true)
  else
    existing_auth=$(grep -B 2 "basic_auth" "$domain_file" | grep "$username" || true)
  fi

  if [ -n "$existing_auth" ]; then
    local update_choice
    update_choice=$(prompt_with_fzf "Username $username already exists. Update password?" "Yes No")
    if [ "$update_choice" = "No" ]; then
      message INFO "Basic auth not updated for $username"
      return 0
    fi
    # Remove existing basic auth block
    if [ -n "$auth_path" ]; then
      sed -i "/@path.*$auth_path/,/}/d" "$domain_file"
    else
      sed -i "/basic_auth/,/}/d" "$domain_file"
    fi
  fi

  # Generate hashed password
  local hashed_password
  hashed_password=$(docker exec "${CADDY_CONTAINER_NAME}" caddy hash-password --plaintext "$password" | tail -n 1)

  # Backup config before modification
  local backup_file
  backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  message INFO "Backed up $domain.caddy to $backup_file"

  # Add basic auth to config
  if [ -n "$auth_path" ]; then
    # Specific path
    awk -v auth_path="$auth_path" -v username="$username" -v hashed_password="$hashed_password" '
    BEGIN { inserted = 0 }
    {
        print $0
        if (!inserted && /{/) {
            print "    @path_" auth_path " {"
            print "        path " auth_path
            print "    }"
            print "    handle @path_" auth_path " {"
            print "        basic_auth {"
            print "            " username " " hashed_password
            print "        }"
            print "    }"
            inserted = 1
        }
    }' "${domain_file}" >"${domain_file}.tmp" && mv "${domain_file}.tmp" "$domain_file"
  else
    # Whole site
    awk -v auth_path="$auth_path" -v username="$username" -v hashed_password="$hashed_password" '
    BEGIN { inserted = 0 }
    {
        print $0
        if (!inserted && /{/) {
            print "    @acmeChallenge path /.well-known/acme-challenge/*"
            print "    @notAcme {"
            print "        not path /.well-known/acme-challenge/*"
            print "    }"
            print "    basic_auth @notAcme {"
            print "        " username " " hashed_password
            print "    }"
            inserted = 1
        }
    }' "${domain_file}" >"${domain_file}.tmp" && mv "${domain_file}.tmp" "$domain_file"
  fi

  # Test Caddy syntax
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Basic auth enabled for $domain and Caddy reloaded"
  else
    mv "$backup_file" "$domain_file"
    message ERROR "Invalid Caddy configuration, restored backup"
    return 1
  fi
}

delete_basic_auth() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files for selection
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message ERROR "No domains available to disable basic auth"
    return 1
  fi

  # Ask for domain with fzf
  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(echo "$site_files" | fzf --prompt="Select domain to disable basic auth (use up/down keys): ")
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  # Check if domain exists
  local domain_file="$sites_path/$domain.caddy"
  if [ ! -f "$domain_file" ]; then
    message ERROR "Domain $domain does not exist in $sites_path"
    return 1
  fi

  # Ask for username
  local username
  username=$(prompt_with_default "Enter username to delete" "")
  [ -z "$username" ] && {
    message ERROR "Username cannot be empty"
    return 1
  }

  # Check if username exists in config
  local existing_auth
  existing_auth=$(grep "$username" "$domain_file" || true)
  if [ -z "$existing_auth" ]; then
    message INFO "Username $username not found in $domain config"
    return 0
  fi

  # Backup config before modification
  local backup_file
  backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  message INFO "Backed up $domain.caddy to $backup_file"

  # Confirm deletion
  confirm_action "Do you want to delete basic auth for $username in $domain?" || {
    message INFO "Deletion canceled"
    return 0
  }

  # Remove basic auth block
  awk '
    BEGIN { delete_block = 0 }
    /@notAcme|basic_auth/ { delete_block = 1 }
    delete_block && /\}/ { delete_block = 0; next }
    !delete_block
' "$domain_file" >"$domain_file.tmp" && mv "$domain_file.tmp" "$domain_file"

  # Test Caddy syntax
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Basic auth for $username in $domain deleted and Caddy reloaded"
  else
    mv "$backup_file" "$domain_file"
    message ERROR "Invalid Caddy configuration after deletion, restored backup"
    return 1
  fi
}

restricted_add_whitelist_ips() {
  message INFO "Please note that whitelisting is done on a per-domain basis"
  message INFO "When using this feature, the system will be configured to only allow access to the Whitelist IPs you provide, so be careful!"

  local sites_path="$CONFIG_DIR/sites"
  local site_files domain domain_file new_ips internal_ips all_ips backup_file

  # Get available domains
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message ERROR "No domains available"
    return 1
  fi

  # Select domain
  domain=$(echo "$site_files" | fzf --prompt="Select domain: ")
  if [ -z "$domain" ]; then
    message INFO "No domain selected"
    return 0
  fi

  domain_file="$sites_path/$domain.caddy"
  if [ ! -f "$domain_file" ]; then
    message ERROR "Domain file not found: $domain_file"
    return 1
  fi

  echo
  if ! confirm_action "Do you want to enable restricted Whitelist IPs for ${domain}!"; then
    message INFO "Operation cancelled!"
    return 1
  fi

  # Get new whitelist IPs
  new_ips=$(prompt_with_default "Enter IPs to whitelist (space-separated)" "")
  if [ -z "$new_ips" ]; then
    message ERROR "No IPs provided"
    return 1
  fi

  # Define internal IPs
  internal_ips="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"

  # Merge and remove duplicates
  all_ips=$(echo "$internal_ips $new_ips" | tr ' ' '\n' | sort -u | tr '\n' ' ')

  # Backup original file
  backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  message INFO "Backup saved: $backup_file"

  # Update whitelist using awk
  awk -v ips="$all_ips" '
    BEGIN { inserted = 0 }
    /@blocked_ips not remote_ip/ {
        print "    @blocked_ips not remote_ip " ips;
        inserted = 1;
        next;
    }
    /@acmeChallenge path \\/.well-known\\/acme-challenge\\/*/ {
        print;
        print "    @blocked_ips not remote_ip " ips;
        print "    respond @blocked_ips \"Access denied\" 403";
        inserted = 1;
        next;
    }
    /^{/ && inserted == 0 {
        print;
        print "    @blocked_ips not remote_ip " ips;
        print "    respond @blocked_ips \"Access denied\" 403";
        inserted = 1;
        next;
    }
    { print }
  ' "$backup_file" >"$domain_file"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Whitelist updated for $domain and Caddy reloaded"
  else
    mv "$backup_file" "$domain_file"
    message ERROR "Invalid Caddy config, restored backup"
    return 1
  fi
}

restricted_remove_whitelist_ips() {
  message INFO "Please note that whitelisting is done on a per-domain basis"
  message INFO "The system will remove the IPs you provided from the whitelist. This will make you inaccessible, be careful!"

  local sites_path="$CONFIG_DIR/sites"
  local site_files domain domain_file existing_ips remove_ips new_ips backup_file

  # Get available domains
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message ERROR "No domains available"
    return 1
  fi

  # Select domain
  domain=$(echo "$site_files" | fzf --prompt="Select domain: ")
  if [ -z "$domain" ]; then
    message INFO "No domain selected"
    return 0
  fi

  domain_file="$sites_path/$domain.caddy"
  if [ ! -f "$domain_file" ]; then
    message ERROR "Domain file not found: $domain_file"
    return 1
  fi

  echo
  if ! confirm_action "Do you want to remove IP from restricted Whitelist IPs for domain ${domain}!"; then
    message INFO "Operation cancelled!"
    return 1
  fi

  # Extract existing whitelist IPs
  existing_ips=$(grep -oP '(?<=@blocked_ips not remote_ip ).*' "$domain_file" | tr ' ' '\n' | sort -u)
  if [ -z "$existing_ips" ]; then
    message INFO "No whitelist IPs found"
    return 0
  fi

  # Select IPs to remove
  remove_ips=$(echo "$existing_ips" | fzf --multi --prompt="Select IPs to remove: ")
  if [ -z "$remove_ips" ]; then
    message INFO "No IPs selected for removal"
    return 0
  fi

  # Calculate new whitelist IPs
  new_ips=$(comm -23 <(echo "$existing_ips" | sort) <(echo "$remove_ips" | sort) | tr '\n' ' ')

  # Backup original file
  backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  message INFO "Backup saved: $backup_file"

  # Update file using awk
  awk -v ips="$new_ips" '
    BEGIN { updated = 0 }
    /@blocked_ips not remote_ip/ {
        if (ips != "") {
            print "    @blocked_ips not remote_ip " ips;
            updated = 1;
        }
        next;
    }
    { print }
  ' "$backup_file" >"$domain_file"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Whitelist updated for $domain and Caddy reloaded"
  else
    mv "$backup_file" "$domain_file"
    message ERROR "Invalid Caddy config, restored backup"
    return 1
  fi
}

restricted_unblock_ips() {
  message INFO "Please note that whitelisting is done on a per-domain basis"
  message INFO "The system will remove the IPs you provided from the whitelist. This will make you inaccessible, be careful!"

  local sites_path="$CONFIG_DIR/sites"
  local site_files domain domain_file backup_file

  # Get available domains
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message ERROR "No domains available"
    return 1
  fi

  # Select domain
  domain=$(echo "$site_files" | fzf --prompt="Select domain: ")
  if [ -z "$domain" ]; then
    message INFO "No domain selected"
    return 0
  fi

  domain_file="$sites_path/$domain.caddy"
  if [ ! -f "$domain_file" ]; then
    message ERROR "Domain file not found: $domain_file"
    return 1
  fi

  echo
  if ! confirm_action "Do you want to unblock access for website ${domain}!"; then
    message INFO "Operation cancelled!"
    return 1
  fi

  # Check if @blocked_ips rules exist
  if ! grep -qE '^\s*@blocked_ips not remote_ip' "$domain_file"; then
    message INFO "No block rule found in $domain_file"
    return 0
  fi

  # Backup original file
  backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  message INFO "Backup saved: $backup_file"

  # Remove block rules using awk
  awk '
    /^\s*@blocked_ips not remote_ip/ { skip=1; next }
    /^\s*respond @blocked_ips/ { skip=1; next }
    { if (!skip) print; skip=0 }
  ' "$backup_file" >"$domain_file"

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Unblocked all IP rules for $domain and reloaded Caddy"
  else
    mv "$backup_file" "$domain_file"
    message ERROR "Invalid Caddy config, restored backup"
    return 1
  fi
}
