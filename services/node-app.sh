#!/bin/bash

# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/utils.sh
source "$BASE_DIR/commons/utils.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

add_node_app() {
  local sites_path="$CONFIG_DIR/sites"
  local node_base_dir="/home/infra-caddy-sites"

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
      domain=$(prompt_with_default "Enter new domain name for Node.js app" "")
    fi
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  # Check if domain already exists
  local domain_file="$sites_path/$domain.caddy"
  if [ -f "$domain_file" ]; then
    message ERROR "Domain $domain already exists in $sites_path"
    return 1
  fi

  # Ask for port
  local port
  port=$(prompt_with_default "Enter port for Node.js app" "")
  [ -z "$port" ] && {
    message ERROR "Port cannot be empty"
    return 1
  }

  # Prepare Node.js app directory
  local node_dir="$node_base_dir/$domain/node-app"
  if [ ! -d "$node_dir" ]; then
    mkdir -p "$node_dir"
    local install_nestjs
    install_nestjs=$(prompt_with_fzf "Directory $node_dir does not exist. Install NestJS?" "Yes No")
    if [ "$install_nestjs" = "Yes" ]; then
      message INFO "Installing NestJS in $node_dir as user $PM2_USER..."
      sudo -u "$PM2_USER" bash -c "cd $node_dir && npm install -g @nestjs/cli && nest new . --skip-git --package-manager npm"
      # Start with PM2
      sudo -u "$PM2_USER" bash -c "cd $node_dir && pm2 start dist/main.js --name $domain -- --port $port"
      sudo -u "$PM2_USER" pm2 save
      message INFO "NestJS installed and started with PM2 on port $port"
    else
      message INFO "Directory $node_dir created, please deploy your Node.js app manually"
    fi
  else
    # If directory exists, assume app is deployed and start with PM2
    sudo -u "$PM2_USER" bash -c "cd $node_dir && pm2 start npm --name $domain -- start -- --port $port"
    sudo -u "$PM2_USER" pm2 save
    message INFO "Node.js app started with PM2 on port $port"
  fi

  # Ask if user wants basic auth
  local use_basic_auth
  use_basic_auth=$(prompt_with_fzf "Enable basic auth for this Node.js app?" "Yes No")
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

    # Generate hashed password
    local hashed_password
    hashed_password=$(docker exec "${CADDY_CONTAINER_NAME}" caddy hash-password --plaintext "$password" | tail -n 1)

    # Prepare basic auth config
    if [ -n "$auth_path" ]; then
      basic_auth_config="@path_$auth_path {\n    path $auth_path\n}\nhandle @path_$auth_path {\n    basic_auth {\n        $username $hashed_password\n    }\n}"
    else
      basic_auth_config="    basic_auth {\n        $username $hashed_password\n    }"
    fi
  fi

  # Create reverse proxy config with or without basic auth
  cat >"$domain_file" <<EOF
$domain {
    reverse_proxy http://host.docker.internal:$port
$basic_auth_config
}
EOF

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
  else
    rm -f "$domain_file"
    message ERROR "Invalid Caddy configuration, Node.js app not added"
    return 1
  fi
}

delete_node_app() {
  local sites_path="$CONFIG_DIR/sites"

  # List all .caddy files for selection
  local site_files
  site_files=$(find "$sites_path" -maxdepth 1 -type f -name "*.caddy" -exec basename {} \; | sed 's/\.caddy$//')
  if [ -z "$site_files" ]; then
    message ERROR "No Node.js apps available to delete"
    return 1
  fi

  # Ask for domain with fzf
  local domain
  if [ -n "$1" ]; then
    domain="$1"
  else
    domain=$(echo "$site_files" | fzf --prompt="Select Node.js app to delete (use up/down keys): ")
  fi
  if [ -z "$domain" ] || ! validate_domain "$domain"; then
    message INFO "No domain or invalid domain selected"
    return 0
  fi

  # Check if domain exists
  local domain_file="$sites_path/$domain.caddy"
  if [ ! -f "$domain_file" ]; then
    message ERROR "Node.js app $domain does not exist in $sites_path"
    return 1
  fi

  # Ask for username to delete (optional)
  local username
  username=$(prompt_with_default "Enter username to delete from basic auth (leave blank to delete entire app)" "")

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
    # Confirm deletion of entire app
    confirm_action "Do you want to delete Node.js app $domain? (This will stop PM2 process)" || {
      message INFO "Deletion canceled"
      return 0
    }
    sudo -u "$PM2_USER" pm2 stop "$domain"
    sudo -u "$PM2_USER" pm2 delete "$domain"
    sudo -u "$PM2_USER" pm2 save
    rm -f "$domain_file"
    message INFO "Node.js app $domain deleted and PM2 process stopped"
  fi

  # Validate and reload Caddy
  if caddy_validate; then
    caddy_reload || return 1
  else
    mv "$backup_file" "$domain_file"
    message ERROR "Invalid Caddy configuration after deletion, restored backup"
    return 1
  fi
}
