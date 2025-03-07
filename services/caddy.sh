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
  local caddyfile_path
  local sites_path
  local data_path
  local config_path
  caddyfile_path="$CONFIG_DIR/Caddyfile"
  sites_path="$CONFIG_DIR/sites"
  data_path="$CONFIG_DIR/caddy_data"
  config_path="$CONFIG_DIR/caddy_config"

  # Create network if not exists
  local network_check
  network_check=$(
    docker network ls | grep -q "$NETWORK_NAME"
    echo $?
  )
  if [ "$network_check" -ne 0 ]; then
    docker network create "$NETWORK_NAME"
    message INFO "Network $NETWORK_NAME created"
  fi

  # Check if Caddy container exists
  local container_check
  container_check=$(
    docker ps -a | grep -q "${PREFIX_NAME}_caddy"
    echo $?
  )
  if [ "$container_check" -ne 0 ]; then
    local image
    image=$(prompt_with_default "Enter Caddy image" "$(get_mapping_value SERVICE_IMAGES caddy)")
    if ! docker image inspect "$image" >/dev/null 2>&1; then
      message INFO "Pulling image ${image}"
      docker pull "${image}"
    fi
    # Create Caddy container
    # -p 80:80 -p 443:443 expose HTTP and HTTPS ports
    message INFO "Creating Caddy container"
    docker run -d \
      --name "${PREFIX_NAME}_caddy" \
      --network "$NETWORK_NAME" \
      --restart unless-stopped \
      -p 80:80 -p 443:443 \
      -v "$caddyfile_path:/etc/caddy/Caddyfile" \
      -v "$sites_path:/etc/caddy/sites" \
      -v "$data_path:/data" \
      -v "$config_path:/config" \
      --add-host=host.docker.internal:host-gateway \
      --log-opt max-size=10m \
      --log-opt max-file=3 \
      --health-cmd='pgrep caddy' \
      --health-interval=30s \
      --health-retries=3 \
      --health-start-period=10s \
      "$image"
    message SUCCESS "Caddy container ${PREFIX_NAME}_caddy created successfully"
    sleep 5
    echo
    docker ps -a --filter "name=${PREFIX_NAME}_caddy"
  else
    message INFO "Caddy container ${PREFIX_NAME}_caddy already exists"
  fi

  # Ensure required directories exist
  [ ! -d "$sites_path" ] && mkdir -p "$sites_path"
  [ ! -d "$data_path" ] && mkdir -p "$data_path"
  [ ! -d "$config_path" ] && mkdir -p "$config_path"

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
        not path /wp-includes/ms-files.php
        path /wp-admin/includes/*.php
        path /wp-includes/*.php
        path /wp-config.php
        path /wp-content/uploads/*.php
        path /wp-content/debug.log
        path /.user.ini
        path /.env
        path /storage/logs/laravel.log
    }
    respond @forbidden "Access denied" 403
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

  # Let user select site with fzf
  local selected_site
  selected_site=$(echo "$site_files" | fzf --prompt="Select site to delete (use up/down keys): ")
  if [ -z "$selected_site" ]; then
    message INFO "No site selected"
    return 0
  fi

  local site_file="$sites_path/$selected_site.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Site $selected_site not found"
    return 1
  }

  # Backup before deletion
  local backup_file="$BACKUP_DIR/$selected_site.caddy.$(date +%Y%m%d_%H%M%S)"
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
  local validate_result
  validate_result=$(
    docker exec "${PREFIX_NAME}_caddy" caddy validate --config "/etc/caddy/Caddyfile"
    echo $?
  )
  if [ "$validate_result" -eq 0 ]; then
    docker exec "${PREFIX_NAME}_caddy" caddy reload --config "/etc/caddy/Caddyfile"
    message INFO "Caddy reloaded successfully"
  else
    message ERROR "Caddy configuration invalid after deletion"
    return 1
  fi
}

stop_site() {
  local stop_options="Stop all sites Stop one site"
  local stop_choice
  stop_choice=$(echo "$stop_options" | fzf --prompt="Select stop option: ")
  if [ "$stop_choice" = "Stop all sites" ]; then
    docker stop "${PREFIX_NAME}_caddy" && message INFO "Caddy web server stopped"
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
      local selected_site
      selected_site=$(echo "$sites" | fzf --prompt="Select site to stop (use up/down keys): ")
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
  local start_options="Start all sites Start one site"
  local start_choice
  start_choice=$(echo "$start_options" | fzf --prompt="Select start option: ")
  if [ "$start_choice" = "Start all sites" ]; then
    local sites
    sites=$(list_sites)
    if [ -n "$sites" ]; then
      for domain in $sites; do
        local containers
        containers=$(get_site_containers "$domain")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker start && message INFO "Started containers for $domain"
        fi
      done
    else
      message INFO "No sites found to start"
    fi
    docker start "${PREFIX_NAME}_caddy" && message INFO "Caddy web server started"
  elif [ "$start_choice" = "Start one site" ]; then
    local sites
    sites=$(list_sites)
    if [ -z "$sites" ]; then
      message INFO "No sites available to start"
    else
      local selected_site
      selected_site=$(echo "$sites" | fzf --prompt="Select site to start (use up/down keys): ")
      if [ -n "$selected_site" ]; then
        local containers
        containers=$(get_site_containers "$selected_site")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker start && message INFO "Started containers for $selected_site"
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
  local restart_options="Restart all sites Restart one site"
  local restart_choice
  restart_choice=$(echo "$restart_options" | fzf --prompt="Select restart option: ")
  if [ "$restart_choice" = "Restart all sites" ]; then
    local sites
    sites=$(list_sites)
    if [ -n "$sites" ]; then
      for domain in $sites; do
        local containers
        containers=$(get_site_containers "$domain")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker restart && message INFO "Restarted containers for $domain"
        fi
      done
    else
      message INFO "No sites found to restart"
    fi
    docker restart "${PREFIX_NAME}_caddy" && message INFO "Caddy web server restarted"
  elif [ "$restart_choice" = "Restart one site" ]; then
    local sites
    sites=$(list_sites)
    if [ -z "$sites" ]; then
      message INFO "No sites available to restart"
    else
      local selected_site
      selected_site=$(echo "$sites" | fzf --prompt="Select site to restart (use up/down keys): ")
      if [ -n "$selected_site" ]; then
        local containers
        containers=$(get_site_containers "$selected_site")
        if [ -n "$containers" ]; then
          echo "$containers" | xargs docker restart && message INFO "Restarted containers for $selected_site"
        else
          message INFO "No containers found for $selected_site"
        fi
      else
        message INFO "No site selected"
      fi
    fi
  fi
}
