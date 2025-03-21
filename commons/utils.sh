#!/bin/bash

# shellcheck source=./../commons/color.sh
source "$BASE_DIR/commons/color.sh"
# shellcheck source=./../commons/config.sh
source "$BASE_DIR/commons/config.sh"
# shellcheck source=./../commons/validation.sh
source "$BASE_DIR/commons/validation.sh"

message() {
  local level
  level=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  local message=$2
  # Color
  local RSC='\033[0m'
  local FATAL='\033[1;41m\033[1;33m'  # Nền đỏ - chữ vàng
  local ERROR='\033[41m\033[1;37m'    # Nền đỏ - Màu trắng đậm
  local FAILED='\033[0;31m'           # Màu đỏ
  local INFO='\033[0;92m'             # Màu xanh lá nhạt
  local DEBUG='\033[0;35m'            # Magenta
  local TRACE='\033[35m'              # Magenta
  local EMERGENCY='\033[41;1m'        # Màu nền đỏ đậm nhấp nháy
  local CRITICAL='\033[41m\033[1;32m' # Xanh lá cây đậm - Nền đỏ
  local ALERT='\033[1;31m'            # Màu cam đậm
  local WARNING='\033[0;33m'          # Màu vàng
  local NOTICE='\033[0;36m'           # Màu xanh dương nhạt
  local SUCCESS='\033[1;36m'          # Cyan đậm
  local LINK='\033[1;34m'             # Blue đậm
  local SUGGEST='\033[38;5;223m'      # Navajo white
  # Write message
  case $level in
  FATAL) echo -e "${level}: ${FATAL}${message}${RSC}" ;;
  ERROR | ERR) echo -e "${level}: ${ERROR}${message}${RSC}" ;;
  FAILED) echo -e "${level}: ${FAILED}${message}${RSC}" ;;
  WARN | WARNING) echo -e "${level}: ${WARNING}${message}${RSC}" ;;
  INFO) echo -e "${level}: ${INFO}${message}${RSC}" ;;
  SUCCESS | FINISHED) echo -e "${level}: ${SUCCESS}${message}${RSC}" ;;
  LINK | URL) echo -e "${level}: ${LINK}${message}${RSC}" ;;
  DEBUG) echo -e "${level}: ${DEBUG}${message}${RSC}" ;;
  TRACE | CURRENT) echo -e "${level}: ${TRACE}${message}${RSC}" ;;
  EMERGENCY) echo -e "${level}: ${EMERGENCY}${message}${RSC}" ;;
  ALERT) echo -e "${level}: ${ALERT}${message}${RSC}" ;;
  CRITICAL) echo -e "${level}: ${CRITICAL}${message}${RSC}" ;;
  NOTICE | NOTE) echo -e "${level}: ${NOTICE}${message}${RSC}" ;;
  SUGGEST) echo -e "${level}: ${SUGGEST}${message}${RSC}" ;;
  *) echo -e "${message}" ;;
  esac
}
break_line() {
  local terminal_columns
  terminal_columns=$(tput cols)
  local terminal_break_line=""
  local i
  for ((i = 1; i <= terminal_columns; i++)); do
    terminal_break_line="${terminal_break_line}="
  done
  local colored_terminal_break_line="${GREEN}${terminal_break_line}${NC}"
  echo -e "$colored_terminal_break_line"
  echo
}
print_message() {
  local NC='\033[0m'
  local CYAN='\033[0;36m'
  local LINE="--------------------------------------------------------------------------"
  local MSG=${1:-""}
  if [ -n "$MSG" ]; then
    echo -e "\n${LINE}\n${CYAN}$MSG${NC}\n${LINE}\n"
  else
    echo -e "\n${LINE}\n"
  fi
}
has_command() {
  command -v "$1" >/dev/null 2>&1
}
# Function OS detection
os_detect() {
  local os="Unknown"
  if [[ "$(uname)" == "Darwin" ]]; then
    os="MacOS"
  elif [[ -f /etc/os-release ]]; then
    source /etc/os-release
    case "$ID" in
    rhel | centos | rocky | rockylinux | almalinux | fedora | amzn)
      os="RHEL"
      ;;
    ubuntu | linuxmint | debian)
      os="Ubuntu"
      ;;
    alpine)
      os="Alpine"
      ;;
    opensuse)
      os="OpenSUSE"
      ;;
    sles)
      os="SLES"
      ;;
    esac
  elif command -v lsb_release >/dev/null 2>&1; then
    local distro
    distro=$(lsb_release -si)
    case "$distro" in
    Ubuntu | LinuxMint | Debian)
      os="Ubuntu"
      ;;
    Fedora | CentOS | RedHatEnterpriseServer | Rocky | RockyLinux | AlmaLinux | Amzn)
      os="RHEL"
      ;;
    openSUSE)
      os="OpenSUSE"
      ;;
    SUSE)
      os="SLES"
      ;;
    esac
  fi
  echo "$os"
}
# Function to ask the user whether to proceed with an action. Usage: confirm_action <ask_confirm_msg>
confirm_action() {
  local ask_confirm_msg confirmation
  ask_confirm_msg=$1
  # Display the question with color codes, without a newline at the end
  echo -ne "${ask_confirm_msg} (Y/N, ${GREEN}empty as No${NC}, press ${YELLOW}[Ctrl+C (macOS: Control+C)]${NC} quit proceed): "
  read -r confirmation # Read user input
  [[ $confirmation =~ ^(Y|y|YES|yes|Yes|OK|ok)$ ]]
}
# Function to prompt the user with a default option. Usage: prompt_with_default <prompt_message> [default_value]
prompt_with_default() {
  local prompt_message=$1 # Prompt message
  local default_value=$2  # Default value for the default option
  local user_input        # User input
  if [ -z "$default_value" ]; then
    read -rp "${prompt_message}: " user_input
  else
    read -rp "${prompt_message} [Default is: ${default_value}]: " user_input
  fi
  echo "${user_input:-$default_value}"
}
# Function to prompt the user with fuzzy search. Usage: prompt_with_fzf <prompt> <options> [default]
prompt_with_fzf() {
  local prompt="$1"
  local options="$2" # Space-separated list of options
  local default="$3"
  local selected

  # Run fzf and save the result to variable selected
  selected=$( (
    echo "$options" | tr ' ' '\n'
    echo "I want to enter manually"
  ) | fzf --prompt="$prompt> " --height=10 --select-1 --query="$default")

  # If user selects "I want to enter manually", manual entry is required.
  if [[ "$selected" == "I want to enter manually" ]]; then
    read -rp "$prompt (manual input): " selected
  fi

  # If nothing is entered, use the default value.
  [ -z "$selected" ] && selected="$default"

  echo "$selected"
}
# Function to install curl if missing
install_curl() {
  local OS
  OS=$(os_detect)
  if ! command -v curl &>/dev/null; then
    echo "curl is not installed. Installing curl..."
    case "$OS" in
    Ubuntu)
      sudo apt update && sudo apt install -y curl
      ;;
    RHEL)
      sudo yum install -y curl
      ;;
    *)
      echo "Unsupported OS: $OS. Please install curl manually."
      exit 1
      ;;
    esac
  fi
}
fetch_public_ip() {
  local CHECK_URL IP
  for CHECK_URL in "https://checkip.amazonaws.com/" "https://icanhazip.com/" "https://whatismyip.akamai.com/" "https://api.ipify.org/" "https://cpanel.net/showip.cgi" "https://myip.directadmin.com/" "https://ipinfo.io/ip"; do
    IP=$(curl -s --max-time 1 "${CHECK_URL}") && [ -n "${IP}" ] && echo "${IP}" && return 0
  done
  return 1
}
trim_whitespace() {
  local input="$1"
  echo "${input}" | awk '{$1=$1;print}' # Use awk to trim leading and trailing spaces
}
uppercase_txt() {
  local txt="$1"
  local bash_version="${BASH_VERSINFO[0]}" # Get major Bash version
  if ((bash_version >= 4)); then
    echo "${txt^^}" # Use Bash native syntax if version is 4 or higher
  else
    echo "$txt" | tr '[:lower:]' '[:upper:]' # Use tr command for older Bash versions
  fi
}
lowercase_txt() {
  local txt="$1"
  local bash_version="${BASH_VERSINFO[0]}" # Get major Bash version
  if ((bash_version >= 4)); then
    echo "${txt,,}" # Use Bash native syntax if version is 4 or higher
  else
    echo "$txt" | tr '[:upper:]' '[:lower:]' # Use tr command for older Bash versions
  fi
}
# Function to replace content in a file using SED. Usage: str_replace <search_value> <replace_value> <target_file>
str_replace() {
  local search_value="$1"  # The string to search for in the file.
  local replace_value="$2" # The string to replace the search_value with.
  local target_file="$3"   # The file where the replacement should occur.
  # Check if the required parameters are provided
  if [[ -z "$search_value" || -z "$target_file" ]]; then
    message ERROR "Missing required parameters: search_value, target_file"
    message TRACE "Usage: str_replace <search_value> <replace_value> <target_file>"
    return 1
  fi
  # Display warning if replace_value is empty
  if [[ -z "$replace_value" ]]; then
    message WARN "Parameters 'replace_value' is empty. It doesn't cause an error, but it will replace search_value (${search_value}) with an empty value."
  fi
  # Escape special characters in the search and replacement values
  local escaped_search_value
  local escaped_replace_value
  escaped_search_value=$(printf '%s\n' "$search_value" | sed 's/[\/&]/\\&/g')
  escaped_replace_value=$(printf '%s\n' "$replace_value" | sed 's/[\/&]/\\&/g')
  # Check if search_value exists in the target_file
  if ! grep -q "$escaped_search_value" "$target_file"; then
    message DEBUG "'${search_value}' not found in '$(basename "$target_file")'. No changes made."
    return 0
  fi
  # Detect the operating system type using uname
  local os_type uname_out
  uname_out="$(uname -s)"
  case "${uname_out}" in
  Linux*)
    if [ -f /etc/redhat-release ]; then
      os_type="rhel" # RHEL/CentOS/Fedora
    elif [ -f /etc/debian_version ]; then
      os_type="debian" # Ubuntu/Debian/Mint
    else
      os_type="linux" # Other Linux distributions
    fi
    ;;
  Darwin*)
    os_type="macos" # macOS
    ;;
  *)
    os_type="unknown" # Unknown operating system
    ;;
  esac
  # Check file ownership and use sudo if necessary
  local sed_command
  if [[ "$os_type" == "macos" ]]; then
    sed_command="sed -i"
  else
    if [[ "$(stat -c '%U:%G' "$target_file")" == "root:root" ]]; then
      sed_command="sudo sed -i"
    else
      sed_command="sed -i"
    fi
  fi
  # Perform the replacement using sed
  case "$os_type" in
  macos)
    $sed_command '' "s|$escaped_search_value|$escaped_replace_value|g" "$target_file"
    ;;
  rhel | debian | linux)
    $sed_command "s|$escaped_search_value|$escaped_replace_value|g" "$target_file"
    ;;
  esac
  # Display results
  message INFO "Replacement content from '${search_value}' to '${replace_value}' completed in file: '$(basename "$target_file")'!"
}
# Generate random strong password
generate_password() {
  openssl rand -base64 27 | tr -d '\n' | head -c 36
}
# Check if port is available
check_port() {
  local port="$1"
  if validate_port "$port"; then

    if has_command ss; then
      if ss -tuln | grep -q ":$port "; then
        message ERROR "Port $port is already in use"
        return 1
      fi
    fi

    if has_command netstat; then
      if netstat -tuln | grep -q ":$port\b"; then
        message ERROR "Port $port is already in use"
        return 1
      fi
    fi

    if has_command lsof; then
      if lsof -i :"$port"; then
        message ERROR "Port $port is already in use"
        return 1
      fi
    fi

    return 0
  fi
  return 1
}
# Function check bash version
check_bash_version() {
  if ! command -v bash &>/dev/null; then
    echo "❌ Bash is not installed!"
    exit 1
  fi

  local bash_version
  bash_version=$(bash --version | head -n1 | awk '{print $4}' | cut -d. -f1)
  if [[ "$bash_version" -lt 4 ]]; then
    echo "❌ Bash version must be ≥ 4 (Current: $bash_version)"
    exit 1
  fi

  return 0
}
# Install require packages
check_require_packages() {
  local packages="$1"
  if [ -n "$packages" ] && ! has_command "$packages"; then
    local OS
    OS=$(os_detect)
    local package_manager=""
    case "$OS" in
    MacOS)
      package_manager="brew"
      ;;
    Ubuntu)
      if has_command apt; then
        package_manager="sudo apt"
      else
        package_manager="sudo apt-get"
      fi
      ;;
    RHEL)
      if has_command dnf; then
        package_manager="sudo dnf"
      else
        package_manager="sudo yum"
      fi

      ;;
    *)
      message ERROR "Unsupported OS: $OS. Docker installation may vary."
      exit 1
      ;;
    esac

    if [ -n "$package_manager" ]; then
      message INFO "Installing required packages..."
      local os_id
      os_id=$(grep ^ID= /etc/*-release | cut -d= -f2 | tr -d '"')
      if [[ "$os_id" == "amzn" ]] && [[ "$packages" == "fzf" ]]; then
        install_fzf_on_amzn
      else
        if $package_manager install -y "$packages"; then
          message SUCCESS "$packages installed successfully"
        fi
      fi
    fi
  fi
}
install_fzf_on_amzn() {
  if ! has_command fzf; then
    sudo git clone --depth 1 https://github.com/junegunn/fzf.git /usr/local/fzf
    sudo /usr/local/fzf/install --all
    echo "export PATH=/usr/local/fzf/bin:\$PATH" | sudo tee -a /etc/profile.d/fzf.sh
    sudo chmod +x /etc/profile.d/fzf.sh
    source /etc/profile.d/fzf.sh
    message SUCCESS "fzf installed successfully"
  fi
}
# Check Docker installation
check_docker() {
  if ! command -v docker &>/dev/null; then
    message INFO "Docker is not installed"
    if confirm_action "Do you want to install Docker?"; then
      install_docker
    else
      message ERROR "Docker is required. Please install it manually."
      exit 1
    fi
  else
    if ! docker info >/dev/null 2>&1; then
      message ERROR "Docker daemon is not running. Please start Docker and try again."
      exit 1
    fi
  fi
  if ! check_docker_compose; then
    if confirm_action "Do you want to install Docker Compose?"; then
      install_docker_compose
    fi
  fi
}
# Install Docker (basic, may need customization per OS)
install_docker() {
  # Check if Docker is already installed
  if has_command docker; then
    message INFO "Docker is already installed."
    return
  fi
  if ! has_command curl; then
    install_curl || return 1
  fi
  message INFO "Installing Docker..."
  if confirm_action "Docker is not installed. Do you want to install Docker?"; then
    message INFO "Installing Docker..."
    local os_id
    os_id=$(grep ^ID= /etc/*-release | cut -d= -f2 | tr -d '"')
    if [[ "$os_id" == "amzn" ]]; then
      if has_command "dnf"; then
        sudo dnf install -y docker
      else
        sudo yum install -y docker
      fi
      sudo systemctl enable --now docker
    else
      curl -fsSL https://get.docker.com -o install-docker.sh
      sudo sh install-docker.sh
      rm install-docker.sh
    fi

    # Add the current user to the docker group
    sudo usermod -aG docker "$USER"
    newgrp docker
    message SUCCESS "Docker has been installed successfully!"
    message INFO "You may need to log out and back in for group changes to take effect."
  else
    message INFO "Docker installation skipped. Please install Docker manually to use this script."
    exit 1
  fi
}
# Check docker-compose installation
check_docker_compose() {
  if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
# Install Docker Compose (basic, may need customization per OS)
# Note: This script assumes Docker is already installed and running.
install_docker_compose() {
  if check_docker_compose; then
    message INFO "✅ Docker Compose is already installed."
    return 0
  fi
  message INFO "🔄 Installing Docker Compose..."
  local os_arch
  os_arch=$(uname -s)-$(uname -m)
  os_arch=$(lowercase_txt "${os_arch}")
  if [[ "$os_arch" == "darwin-arm64" ]]; then
    os_arch="darwin-aarch64"
  fi
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-${os_arch}" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose && sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
  if check_docker_compose; then
    message INFO "✅ Docker Compose installed successfully."
  else
    message ERROR "❌ Installation Docker Compose failed. Please check manually." >&2
    return 1
  fi
}
# Check docker logs
check_docker_container_logs() {
  if ! has_command docker; then
    message INFO "Docker is not installed. Please install Docker to use this script."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    message INFO "Docker daemon is not running. Please start Docker and try again."
    exit 1
  fi
  local list_docker_containers selected container_id
  if [ -n "$1" ]; then
    docker logs -f "$1"
  else
    list_docker_containers=$(docker ps -a --format "{{.Names}} | {{.ID}} | {{.CreatedAt}}" | grep "^${PREFIX_NAME}_")
    selected=$(echo "$list_docker_containers" | fzf --prompt="Select container to view logs: ")
    if [ -n "$selected" ]; then
      container_id=$(echo "$selected" | awk '{print $3}')
      docker logs -f "$container_id"
    fi
  fi
}
check_container_running() {
  docker ps --format '{{.Names}}' | grep -q "^$1$"
  return $?
}
get_containers_status() {
  local compose_file="$1"
  local containers=()
  local count=0
  local container
  while IFS= read -r container; do
    # Skip if empty line
    [ -z "$container" ] && continue
    containers+=("$container")
    ((count++))
  done < <(docker_compose_command -f "$compose_file" ps --status running --format '{{.Name}}')

  if [ $count -eq 0 ]; then
    message INFO "Status: No container is running"
  else
    echo -n "Status: $count containers are running: "
    printf "%s" "${containers[0]}"
    local i
    for ((i = 1; i < ${#containers[@]}; i++)); do
      printf " and %s" "${containers[$i]}"
    done
    echo
  fi
}
# Helper function to wait for container health
wait_for_health() {
  local container_name="$1"
  local service_type="$2"
  local retry_count=0
  local max_retries=18

  while [ "$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)" != "healthy" ]; do
    message INFO "${service_type} → ${container_name} is not healthy yet. Waiting..."
    sleep 10
    ((retry_count++))

    if [ "$retry_count" -ge "$max_retries" ]; then
      message ERROR "${service_type} → ${container_name} failed to become healthy after ${max_retries} attempts. Please check logs and try again"
      message INFO "Check docker logs: docker -f ${container_name} failed to become healthy"
      return 1
    fi
  done

  message INFO "${service_type} → ${container_name} is healthy"
}
# Docker hard reset and cleanup
docker_hard_reset() {
  docker ps
  if ! confirm_action "Do you want to hard reset all containers and cleanup docker data? Are you sure you want to?"; then
    message INFO "Aborting ...!"
    return
  fi
  message INFO "🛑 Stopping all running containers..."
  docker ps -q | xargs -r docker stop

  message INFO "🗑️ Removing all containers..."
  docker ps -aq | xargs -r docker rm -f

  message INFO "🗑️ Removing all volumes..."
  docker volume ls -q | xargs -r docker volume rm

  message INFO "🗑️ Removing all networks (except default ones)..."
  docker network ls | awk 'NR>1 && $2!="bridge" && $2!="host" && $2!="none" {print $1}' | xargs -r docker network rm

  message INFO "🗑️ Removing all images..."
  docker images -q | xargs -r docker rmi -f

  message INFO "⚙️ Pruning Docker system..."
  docker system prune -af --volumes

  message INFO "🔄 Restarting Docker service..."
  sudo systemctl restart docker

  message INFO "✅ Docker has been reset to a clean state!"
}
# Calculate Docker System Disk
docker_system_disk() {
  docker system df
}
# Prune Docker Build Cache
docker_clean_build_cache() {
  docker builder prune -a
}
docker_network_connect() {
  local connect_network_name=$1
  local connect_container_name=$2
  local connect_container_ip=$3

  if [ -z "$connect_network_name" ]; then
    connect_network_name=$(prompt_with_default "Please enter the network name you want ${connect_container_name} will disconnect it" "${NETWORK_NAME}")
  fi
  if [ -z "$connect_network_name" ]; then
    connect_network_name="${NETWORK_NAME}"
  fi

  if [ -z "$connect_container_name" ]; then
    connect_container_name=$(prompt_with_default "Please enter container name you want to connect to ${connect_container_name}")
  fi
  if [ -z "$connect_container_name" ]; then
    message ERROR "Network name, service name must be provided. Usage: $0 <network_name> <container_name> [container_ip]"
    return
  fi
  if ! docker network inspect "$connect_network_name" >/dev/null 2>&1; then
    message ERROR "Network '$connect_network_name' not exists." >&2
    return 1
  fi
  if ! docker inspect "$connect_container_name" >/dev/null 2>&1; then
    message ERROR "Container '$connect_container_name' not exists." >&2
    return 1
  fi
  # Check if the container is already connected to the network
  if docker network inspect "$connect_network_name" | jq -e ".[] | .Containers | has(\"$connect_container_name\")" >/dev/null; then
    message INFO "Container '$connect_container_name' is already connected to network '$connect_network_name'."
  else
    message INFO " Connecting container '$connect_container_name' to network '$connect_network_name'..."
    if [ -n "$connect_container_ip" ]; then
      docker network connect "$connect_network_name" "$connect_container_name" --ip "$connect_container_ip" >/dev/null 2>&1
    else
      docker network connect "$connect_network_name" "$connect_container_name" >/dev/null 2>&1
    fi
    message SUCCESS "Container '$connect_container_name' is now connected to network '$connect_network_name'."
  fi
}
docker_network_disconnect() {
  local disconnect_network_name=$1
  local disconnect_container_name=$2
  if [ -z "$disconnect_network_name" ]; then
    disconnect_network_name=$(prompt_with_default "Please enter the network name you want ${disconnect_container_name} will disconnect it" "${NETWORK_NAME}")
  fi
  if [ -z "$disconnect_network_name" ]; then
    disconnect_network_name="${NETWORK_NAME}"
  fi
  if [ -z "$disconnect_container_name" ]; then
    disconnect_container_name=$(prompt_with_default "Please enter container name you want to disconnect to ${disconnect_container_name}")
  fi
  if [ -z "$disconnect_container_name" ]; then
    message ERROR "Network name, service name must be provided. Usage: $0 <network_name> <container_name>"
    return
  fi
  if ! docker network inspect "$disconnect_network_name" >/dev/null 2>&1; then
    message ERROR "Network '$disconnect_network_name' not exists." >&2
    return 1
  fi
  if ! docker inspect "$disconnect_container_name" >/dev/null 2>&1; then
    message ERROR "Container '$disconnect_container_name' not exists." >&2
    return 1
  fi

  if docker network inspect "$disconnect_network_name" | jq -e ".[] | .Containers | has(\"$disconnect_container_name\")" >/dev/null; then
    message INFO "Disconnecting container '$disconnect_container_name' from network '$disconnect_network_name'..."
    docker network disconnect "$disconnect_network_name" "$disconnect_container_name" >/dev/null 2>&1
    message SUCCESS " Container '$disconnect_container_name' has been disconnected from network '$disconnect_network_name'."
  else
    message INFO " Container '$disconnect_container_name' is not connected to network '$disconnect_network_name'. No action needed."
  fi
}
join_caddy_network() {
  local container_name=$1
  if [ -z "$container_name" ]; then
    container_name=$(prompt_with_default "Please enter container name you want to connect to ${container_name}")
  fi
  if [ -z "$container_name" ]; then
    message ERROR "Container name must be provided. Usage: $0 <container_name>"
    return
  fi
  docker_network_connect "${NETWORK_NAME}" "$container_name"
}
set_compose_version() {
  local docker_version include_docker_version major_version minor_version
  docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
  major_version=$(echo "$docker_version" | cut -d'.' -f1)
  minor_version=$(echo "$docker_version" | cut -d'.' -f2)

  # Decide whether to include version (use 3.8 for engines < 19.03, omit for newer ones)
  if [ "$major_version" -lt 19 ] || { [ "$major_version" -eq 19 ] && [ "$minor_version" -lt 3 ]; }; then
    include_docker_version="version: '3.8'"
  else
    include_docker_version=""
  fi

  echo "$include_docker_version"
}
get_mapping_value() {
  local -n map=$1
  local key=$2
  echo "${map[$key]}"
}
# Function backup path: folder/file
backup_original_path() {
  local source_path=$1 # Get the source path from the first argument
  # Create the backup file name
  local default_backup_path="${source_path}${SCRIPT_BACKUP_ORIGIN_FILE}"
  local backup_path=${2:-"$default_backup_path"}
  # Check if the source file exists
  if [[ ! -e "$source_path" ]]; then
    # If the source file does not exist, display a warning and return 0
    message WARN "Source path '$(basename "$source_path")' does not exist."
    return 0
  fi
  # If the source path exists, create a backup of the source path
  if [ -f "$source_path" ]; then
    sudo cp -f "$source_path" "$backup_path"
  else
    sudo cp -rf "$source_path" "$backup_path"
  fi
  local copy_checked=$?
  if [[ "$copy_checked" -eq 0 ]]; then
    message SUCCESS "Backup created: '$(basename "$source_path")' successfully"
  else
    message ERROR "Failed to create backup: '$(basename "$source_path")'"
    return 1
  fi
}
# Function restore path (folder/file) from backup
restored_original_path() {
  local source_path=$1 # Get the source path from the first argument
  local default_backup_path="${source_path}${SCRIPT_BACKUP_ORIGIN_FILE}"
  local backup_path=${2:-"$default_backup_path"}
  if [[ ! -e "$backup_path" ]]; then
    message ERROR "Backup path '$(basename "$backup_path")' does not exist. Aborting restored!"
    return 1
  fi
  if [ -f "$backup_path" ]; then
    sudo cp -f "$backup_path" "$source_path"
  else
    sudo cp -rf "$backup_path" "$source_path"
  fi
  local copy_checked=$?
  if [[ "$copy_checked" -eq 0 ]]; then
    message SUCCESS "Restoring '$(basename "$source_path")' from '$(basename "$backup_path")' successfully"
  else
    message ERROR "Failed to restored '$(basename "$source_path")' from '$(basename "$backup_path")'"
    return 1
  fi
}
caddy_validate() {
  docker exec "${CADDY_CONTAINER_NAME}" caddy validate --config "/etc/caddy/Caddyfile"
}
caddy_reload() {
  message INFO "Reloading Caddy..."
  if docker restart "${CADDY_CONTAINER_NAME}"; then
    message SUCCESS "✅ Caddy reloaded successfully"
    wait_for_health "${CADDY_CONTAINER_NAME}" "Caddy Web Server"
  else
    message ERROR "❌ Failed to reload Caddy. Please check logs Caddy container"
    docker logs "${CADDY_CONTAINER_NAME}" --tail 50
    return 1
  fi
}
__display_header_information() {
  local os_compatibility os_name
  if [ -f /etc/os-release ]; then
    os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
    os_compatibility=$(grep '^ID_LIKE=' /etc/os-release | cut -d= -f2- | tr -d '"')
  fi
  break_line
  echo "
  ___        __               ____          _     _           ____
 |_ _|_ __  / _|_ __ __ _    / ___|__ _  __| | __| |_   _    / ___|_   _ _   _
  | || '_ \| |_| '__/ _| |  | |   / _| |/ _| |/ _| | | | |  | |  _| | | | | | |
  | || | | |  _| | | (_| |  | |__| (_| | (_| | (_| | |_| |  | |_| | |_| | |_| |
 |___|_| |_|_| |_|  \__,_|   \____\__,_|\__,_|\__,_|\__, |   \____|\__,_|\__, |
                                                    |___/                 |___/
"
  echo
  echo -e "${YELLOW}Powered by ${DEVELOP_BY}${NC}"
  echo -e "BEAR Caddy Docker Stack - ${GREEN}Premium${NC} scripts version ${YELLOW}${SCRIPT_VERSION}${NC}${NC}"
  echo
#  if has_command ip; then
#    local ServerIPv4 ServerIPv6
#    ServerIPv4="$(ip addr show | awk '/inet / && !/127.0.0.1/ {print $2}' | cut -d'/' -f1 | grep -Ev '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1]))')"
#    if [ -z "$ServerIPv4" ]; then
#      ServerIPv4=$(fetch_public_ip)
#    fi
#    ServerIPv6="$(ip addr show | awk '/inet6/ && !/scope link/ {print $2}' | cut -d'/' -f1 | grep -vE '^fe80|^::1' | head -n1)"
#    if [ -n "$ServerIPv6" ]; then
#      echo -e "Server Public IP      : IPv4 ${GREEN}${ServerIPv4}${NC}, IPv6 ${GREEN}${ServerIPv6}${NC}"
#    else
#      echo -e "Server Public IP      : ${GREEN}${ServerIPv4}${NC}"
#    fi
#  fi
#  if [ -n "$SSH_CLIENT" ]; then
#    echo -e "Your login SSH via IP : ${GREEN}$(echo "$SSH_CLIENT" | awk '{print $1}')${NC}"
#  fi
  echo -e "Server Time           : ${GREEN}$(date +"%a, %Y-%m-%d %H:%M:%S")${NC}"
  if [ -n "$os_name" ]; then
    echo -e "Server OS             : ${GREEN}${os_name}${NC} (Compatibility: ${YELLOW}$(uppercase_txt "$os_compatibility")${NC})"
  fi
  echo -e "System Uptime         : ${GREEN}$(trim_whitespace "$(uptime)")${NC}"
  echo -e "Users logged          : ${GREEN}$(trim_whitespace "$(who | wc -l)")${NC}"
  break_line
}
