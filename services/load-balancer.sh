#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

add_load_balancer() {
  local sites_path="$CONFIG_DIR/sites"

  # Ask for domain
  local domain
  domain=$(prompt_with_default "Enter domain name for load balancer" "")
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

  # Ask for path (optional)
  local path
  path=$(prompt_with_default "Enter path (leave blank for root '/')" "/")

  # Ask for backend servers
  local backends
  backends=$(prompt_with_default "Enter backend servers (comma-separated, e.g., http://localhost:8080,http://localhost:8081)" "")
  [ -z "$backends" ] && {
    message ERROR "Backend servers cannot be empty"
    return 1
  }
  local backends_list=$(echo "$backends" | tr ',' ' ')

  # Ask for load balancing algorithm
  local lb_options="round_robin random least_conn ip_hash"
  local lb_algorithm
  lb_algorithm=$(prompt_with_fzf "Select load balancing algorithm" "$lb_options" "round_robin")

  # Ask for sticky sessions
  local sticky_choice
  sticky_choice=$(prompt_with_fzf "Enable sticky sessions (keep user on same backend)?" "Yes No" "Yes")
  local sticky_config=""
  if [ "$sticky_choice" = "Yes" ]; then
    local session_name
    session_name=$(openssl rand -hex 8) # Random session name
    sticky_config="sticky cookie lb_$session_name ttl=7200"
  fi

  # Enable health check
  local health_check="health_check /health interval=10s timeout=5s"

  # Ask for WebSocket support
  local ws_choice
  ws_choice=$(prompt_with_fzf "Enable WebSocket support?" "Yes No" "No")
  local ws_config=""
  [ "$ws_choice" = "Yes" ] && ws_config="websocket"

  # Create load balancer config
  cat >"$domain_file" <<EOF
${domain} {
    @path {
        path ${path}
    }
    handle @path {
        reverse_proxy {
            to ${backends_list}
            lb_policy ${lb_algorithm}
            ${sticky_config}
            ${health_check}
            ${ws_config}
            fail_duration 30s
            max_fails 3
            unhealthy_status 5xx
        }
    }
    respond "We are busy mode" 503 {
        close
    }
}
EOF

  # Test Caddy syntax
  local validate_result
  validate_result=$(
    docker exec "${PREFIX_NAME}_caddy" caddy validate --config "/etc/caddy/Caddyfile"
    echo $?
  )
  if [ "$validate_result" -eq 0 ]; then
    docker exec "${PREFIX_NAME}_caddy" caddy reload --config "/etc/caddy/Caddyfile"
    message INFO "Load balancer for $domain added and Caddy reloaded"
  else
    rm -f "$domain_file"
    message ERROR "Invalid Caddy configuration, load balancer not added"
    return 1
  fi
}

delete_load_balancer() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')

  if [ -z "$site_files" ]; then
    message INFO "No load balancers available to delete"
    return 0
  fi

  # Let user select site with fzf
  local selected_site
  selected_site=$(echo "$site_files" | fzf --prompt="Select load balancer to delete (use up/down keys): ")
  if [ -z "$selected_site" ]; then
    message INFO "No load balancer selected"
    return 0
  fi

  local site_file="$sites_path/$selected_site.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Load balancer $selected_site not found"
    return 1
  }

  # Backup before deletion
  local backup_file="$BACKUP_DIR/$selected_site.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$site_file" "$backup_file"
  message INFO "Backed up $selected_site.caddy to $backup_file"

  # Confirm deletion
  confirm_action "Do you want to delete load balancer $selected_site?" || {
    message INFO "Deletion canceled"
    return 0
  }

  # Remove site file
  rm -f "$site_file"
  message INFO "Load balancer $selected_site deleted"

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

delete_load_balancer_backend() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')

  if [ -z "$site_files" ]; then
    message INFO "No load balancers available to modify"
    return 0
  fi

  # Let user select site with fzf
  local selected_site
  selected_site=$(echo "$site_files" | fzf --prompt="Select load balancer to modify (use up/down keys): ")
  if [ -z "$selected_site" ]; then
    message INFO "No load balancer selected"
    return 0
  fi

  local site_file="$sites_path/$selected_site.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Load balancer $selected_site not found"
    return 1
  }

  # Extract current backends
  local current_backends
  current_backends=$(grep -E "^\s*to " "$site_file" | sed 's/^\s*to //')
  if [ -z "$current_backends" ]; then
    message ERROR "No backends found in $selected_site configuration"
    return 1
  fi

  # Let user select backend to delete with fzf
  local backend_to_delete
  backend_to_delete=$(echo "$current_backends" | tr ' ' '\n' | fzf --prompt="Select backend to delete (use up/down keys): ")
  if [ -z "$backend_to_delete" ]; then
    message INFO "No backend selected"
    return 0
  fi

  # Confirm deletion
  confirm_action "Do you want to delete backend $backend_to_delete from $selected_site?" || {
    message INFO "Deletion canceled"
    return 0
  }

  # Remove the selected backend
  local updated_backends
  updated_backends=$(echo "$current_backends" | sed "s/\b$backend_to_delete\b//g" | tr -s ' ')
  if [ "$updated_backends" = "$current_backends" ]; then
    message ERROR "Backend $backend_to_delete not found in configuration"
    return 1
  fi

  # Backup before modification
  local backup_file="$BACKUP_DIR/$selected_site.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$site_file" "$backup_file"
  message INFO "Backed up $selected_site.caddy to $backup_file"

  # Update the config file
  sed -i "s/to .*/to $updated_backends/" "$site_file"
  message INFO "Backend $backend_to_delete removed from $selected_site"

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
    mv "$backup_file" "$site_file"
    message ERROR "Caddy configuration invalid after modification, restored backup"
    return 1
  fi
}
