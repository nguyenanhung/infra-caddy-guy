#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

add_reverse_proxy() {
  message INFO "This feature is suitable for only performing load balancer configuration to existing backends, and does not create any additional containers. Please make sure the backends are available and ready beforehand!"

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
    domain=$(prompt_with_default "Enter domain name for reverse proxy" "")
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
    hashed_password=$(docker exec "${CADDY_CONTAINER_NAME}" caddy hash-password --plaintext "$password" | tail -n 1)

    # Prepare basic auth config
    local auth_path=""
    if [ -n "$auth_path" ]; then
      basic_auth_config="@path_$auth_path {\n    path $auth_path\n}\nhandle @path_$auth_path {\n    basic_auth {\n        $username $hashed_password\n    }\n}"
    else
      basic_auth_config="@notAcme {\n    not path /.well-known/acme-challenge/*\n}\nbasic_auth @notAcme {\n    $username $hashed_password\n}"
    fi
  fi
  # Only HTTP Mode
  local domain_block_name="${domain}"
  if confirm_action "The system will automatically register an SSL certificate for the domain ${GREEN}${domain}${NC}. Do you want ${YELLOW}to automatically disable HTTPs usage and only use HTTP${NC}?. ${YELLOW}Consideration${NC}: This will affect the security of ${domain}!"; then
    local domain_block_name="http://${domain}"
  fi
  # Create reverse proxy config with or without basic auth
  cat >"$domain_file" <<EOF
${domain_block_name} {
${basic_auth_config}
    import header_security_reverse_proxy
    reverse_proxy ${upstream_url}
}
EOF

  # Test Caddy syntax
  if caddy_validate; then
    caddy_reload || return 1
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
  if [ -n "$1" ]; then
    selected_site="$1"
  else
    selected_site=$(echo "$site_files" | fzf --prompt="Select reverse proxy to delete (use up/down keys): ")
  fi
  if [ -z "$selected_site" ] || ! validate_domain "$selected_site"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi
  local site_file="$sites_path/$selected_site.caddy"
  validate_file_exists "$site_file" || {
    message ERROR "Reverse proxy $selected_site not found"
    return 1
  }

  # Backup before deletion
  local backup_file
  backup_file="$BACKUP_DIR/$selected_site.caddy.$(date +%Y%m%d_%H%M%S)"
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
  if caddy_validate; then
    caddy_reload || return 1
  else
    message ERROR "Caddy configuration invalid after deletion"
    return 1
  fi
}
