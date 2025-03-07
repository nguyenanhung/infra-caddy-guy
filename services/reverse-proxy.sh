#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

add_reverse_proxy() {
  local sites_path="$CONFIG_DIR/sites"

  # Ask for domain
  local domain
  domain=$(prompt_with_default "Enter domain name for reverse proxy" "")
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

  # Ask for upstream URL
  local upstream_url
  upstream_url=$(prompt_with_default "Enter upstream URL (e.g., http://localhost:8080)" "")
  [ -z "$upstream_url" ] && {
    message ERROR "Upstream URL cannot be empty"
    return 1
  }

  # Ask if user wants basic auth
  local basic_auth_config=""
  if confirm_action "Enable ${GREEN}basic auth${NC} for this ${GREEN}reverse proxy${NC}?"; then
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

  # Create reverse proxy config with or without basic auth
  cat >"$domain_file" <<EOF
${domain} {
    reverse_proxy ${upstream_url}
${basic_auth_config}
}
EOF

  # Test Caddy syntax
  local validate_result
  docker exec "${PREFIX_NAME}_caddy" caddy validate --config "/etc/caddy/Caddyfile"
  validate_result=$?
  if [ "$validate_result" -eq 0 ]; then
    docker restart "${PREFIX_NAME}_caddy"
    message INFO "Reverse proxy for $domain added and Caddy reloaded"
  else
    rm -f "$domain_file"
    message ERROR "Invalid Caddy configuration, reverse proxy not added"
    return 1
  fi
}

delete_reverse_proxy() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')

  if [ -z "$site_files" ]; then
    message INFO "No reverse proxies available to delete"
    return 0
  fi

  # Let user select site with fzf
  local selected_site
  selected_site=$(echo "$site_files" | fzf --prompt="Select reverse proxy to delete (use up/down keys): ")
  if [ -z "$selected_site" ]; then
    message INFO "No reverse proxy selected"
    return 0
  fi

  local site_file="$sites_path/$selected_site.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Reverse proxy $selected_site not found"
    return 1
  }

  # Backup before deletion
  local backup_file="$BACKUP_DIR/$selected_site.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$site_file" "$backup_file"
  message INFO "Backed up $selected_site.caddy to $backup_file"

  # Confirm deletion
  confirm_action "Do you want to delete reverse proxy $selected_site?" || {
    message INFO "Deletion canceled"
    return 0
  }

  # Remove site file
  rm -f "$site_file"
  message INFO "Reverse proxy $selected_site deleted"

  # Validate and reload Caddy
  local validate_result
  docker exec "${PREFIX_NAME}_caddy" caddy validate --config "/etc/caddy/Caddyfile"
  validate_result=$?
  if [ "$validate_result" -eq 0 ]; then
    docker restart "${PREFIX_NAME}_caddy"
    message INFO "Caddy reloaded successfully"
  else
    message ERROR "Caddy configuration invalid after deletion"
    return 1
  fi
}
