#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

add_static_site() {
  local sites_path="$CONFIG_DIR/sites"
  local static_base_dir="/home/infra-caddy-sites"

  # List all .caddy files for selection
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')

  # Ask for domain with fzf
  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    if [ -n "$site_files" ]; then
      domain=$(echo "$site_files" | fzf --prompt="Select existing domain or press Enter to add new (use up/down keys): ")
    fi
    if [ -z "$domain" ]; then
      domain=$(prompt_with_default "Enter new domain name for static site" "")
    fi
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  # Check if domain already exists
  local domain_file="$sites_path/$domain.caddy"

  # Prepare static site directory
  local static_dir="$static_base_dir/$domain/dist"
  if [ ! -d "$static_dir" ]; then
    mkdir -p "$static_dir"
    echo "<!DOCTYPE html><html><body><h1>Welcome to $domain</h1></body></html>" >"$static_dir/index.html"
    message INFO "Created static site directory $static_dir with default index.html"
  fi

  # Ask if user wants basic auth
  local use_basic_auth
  use_basic_auth=$(prompt_with_fzf "Enable basic auth for this static site?" "Yes No")
  local basic_auth_config=""
  if [ "$use_basic_auth" = "Yes" ]; then
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

    # Ask for username and password
    local username
    username=$(prompt_with_default "Enter basic auth username" "auth-admin")
    local password
    password=$(prompt_with_default "Enter basic auth password (leave blank for random)" "")
    [ -z "$password" ] && password=$(generate_password) && message INFO "Generated password: $password"

    # Check if username already exists in config
    if [ -f "$domain_file" ]; then
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
    fi

    # Generate hashed password
    local hashed_password
    hashed_password=$(docker exec "${PREFIX_NAME}_caddy" caddy hash-password --plaintext "$password" | tail -n 1)

    # Prepare basic auth config
    if [ -n "$auth_path" ]; then
      basic_auth_config="@path_$auth_path {\n    path $auth_path\n}\nhandle @path_$auth_path {\n    basic_auth {\n        $username $hashed_password\n    }\n}"
    else
      basic_auth_config="    basic_auth {\n        $username $hashed_password\n    }"
    fi
  fi

  # Backup existing config if it exists
  if [ -f "$domain_file" ]; then
    local backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
    cp "$domain_file" "$backup_file"
    message INFO "Backed up $domain.caddy to $backup_file"
  fi

  # Create static site config with or without basic auth
  cat >"$domain_file" <<EOF
$domain {
    root * $static_dir
    encode zstd gzip
    file_server
    try_files {path} {path}/ /index.html /index.htm /dist.html /build.html
$basic_auth_config
}
EOF

  # Test Caddy syntax
  if caddy_validate; then
    caddy_reload || return 1
    message INFO "Static site for $domain configured and Caddy reloaded"
  else
    rm -f "$domain_file"
    message ERROR "Invalid Caddy configuration, static site not added"
    return 1
  fi
}

delete_static_site() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files for selection
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message ERROR "No static sites available to delete"
    return 1
  fi

  # Ask for domain with fzf
  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(echo "$site_files" | fzf --prompt="Select static site to delete (use up/down keys): ")
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  # Check if domain exists
  local domain_file="$sites_path/$domain.caddy"
  if [ ! -f "$domain_file" ]; then
    message ERROR "Static site $domain does not exist in $sites_path"
    return 1
  fi

  # Ask for username to delete (optional)
  local username
  username=$(prompt_with_default "Enter username to delete from basic auth (leave blank to delete entire site)" "")

  # Backup config before modification
  local backup_file="$BACKUP_DIR/$domain.caddy.$(date +%Y%m%d_%H%M%S)"
  cp "$domain_file" "$backup_file"
  message INFO "Backed up $domain.caddy to $backup_file"

  if [ -n "$username" ]; then
    # Check if username exists in config
    local existing_auth
    existing_auth=$(grep "$username" "$domain_file" || true)
    if [ -z "$existing_auth" ]; then
      message INFO "Username $username not found in $domain config"
      return 0
    fi

    # Confirm deletion
    confirm_action "Do you want to delete basic auth for $username in $domain?" || {
      message INFO "Deletion canceled"
      return 0
    }

    # Remove basic auth block
    if grep -A 2 "basic_auth" "$domain_file" | grep -q "$username"; then
      sed -i "/basic_auth/,/}/d" "$domain_file"
    elif grep -A 2 "@path" "$domain_file" | grep -q "$username"; then
      sed -i "/@path_.*{/{:a;N;/}/!ba;/$username/d}" "$domain_file"
    fi
  else
    # Confirm deletion of entire site
    confirm_action "Do you want to delete static site $domain?" || {
      message INFO "Deletion canceled"
      return 0
    }
    rm -f "$domain_file"
    message INFO "Static site $domain deleted"
  fi

  # Test Caddy syntax
  if caddy_validate; then
    caddy_reload || return 1
  else
    mv "$backup_file" "$domain_file"
    message ERROR "Invalid Caddy configuration after deletion, restored backup"
    return 1
  fi
}
