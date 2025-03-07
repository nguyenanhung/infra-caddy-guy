#!/bin/bash

source "$BASE_DIR/commons/color.sh"
source "$BASE_DIR/commons/config.sh"
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
  if [ -z "$1" ]; then
    echo -e "\n${LINE}\n"
  else
    echo -e "\n${LINE}\n${CYAN}$1${NC}\n${LINE}\n"
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
      if $package_manager install -y "$packages"; then
        message SUCCESS "$packages installed successfully"
      fi
    fi
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
    curl -fsSL https://get.docker.com -o install-docker.sh
    sudo sh install-docker.sh
    rm install-docker.sh

    # Add the current user to the docker group
    sudo usermod -aG docker "$USER"

    message SUCCESS "Docker has been installed successfully!"
    message INFO "You may need to log out and back in for group changes to take effect."
  else
    message INFO "Docker installation skipped. Please install Docker manually to use this script."
    exit 1
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
  list_docker_containers=$(docker ps -a --format "{{.Names}} | {{.ID}} | {{.CreatedAt}}" | grep "^${PREFIX_NAME}_")
  selected=$(echo "$list_docker_containers" | fzf --prompt="Select container to view logs: ")
  if [ -n "$selected" ]; then
    container_id=$(echo "$selected" | awk '{print $3}')
    docker logs -f "$container_id"
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
  done < <(docker compose -f "$compose_file" ps --status running --format '{{.Name}}')

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
  local max_retries=5

  while [ "$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null)" != "healthy" ]; do
    message INFO "${service_type} → ${container_name} is not healthy yet. Retrying..."
    sleep 5
    ((retry_count++))

    if [ "$retry_count" -ge "$max_retries" ]; then
      message ERROR "${service_type} → ${container_name} failed to become healthy after ${max_retries} attempts. Please check logs and try again"
      message INFO "Check docker logs: docker -f ${container_name} failed to become healthy"
      return 1
    fi
  done

  message INFO "${service_type} → ${container_name} is healthy"
}
get_mapping_value() {
  local -n map=$1
  local key=$2
  echo "${map[$key]}"
}
__display_header_information() {
  local os_compatibility os_name
  if [ -f /etc/os-release ]; then
    os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
    os_compatibility=$(grep '^ID_LIKE=' /etc/os-release | cut -d= -f2- | tr -d '"')
  fi
  break_line
  echo "  _    _                           _   _    _____ "
  echo " | |  | |                         | \ | |  / ____|"
  echo " | |__| |  _   _   _ __     __ _  |  \| | | |  __ "
  echo " |  __  | | | | | | '_ \   / _\` | | . \` | | | |_ |"
  echo " | |  | | | |_| | | | | | | (_| | | |\  | | |__| |"
  echo " |_|  |_|  \__,_| |_| |_|  \__, | |_| \_|  \_____|"
  echo "                            __/ |                 "
  echo "                           |___/                  "
  echo
  echo -e "${YELLOW}Powered by ${DEVELOP_BY}${NC}"
  echo -e "BEAR Caddy Docker Stack - ${GREEN}Premium${NC} scripts version ${YELLOW}${SCRIPT_VERSION}${NC}${NC}"
  echo
  if has_command ip; then
    local ServerIPv4 ServerIPv6
    ServerIPv4="$(ip addr show | awk '/inet / && !/127.0.0.1/ {print $2}' | cut -d'/' -f1 | grep -Ev '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1]))')"
    if [ -z "$ServerIPv4" ]; then
      ServerIPv4=$(fetch_public_ip)
    fi
    ServerIPv6="$(ip addr show | awk '/inet6/ && !/scope link/ {print $2}' | cut -d'/' -f1 | grep -vE '^fe80|^::1')"
    if [ -n "$ServerIPv6" ]; then
      echo -e "Server Public IP      : IPv4 ${GREEN}${ServerIPv4}${NC}, IPv6 ${GREEN}${ServerIPv6}${NC}"
    else
      echo -e "Server Public IP      : ${GREEN}${ServerIPv4}${NC}"
    fi
  fi
  if [ -n "$SSH_CLIENT" ]; then
    echo -e "Your login SSH via IP : ${GREEN}$(echo "$SSH_CLIENT" | awk '{print $1}')${NC}"
  fi
  echo -e "Server Time           : ${GREEN}$(date +"%a, %Y-%m-%d %H:%M:%S")${NC}"
  if [ -n "$os_name" ]; then
    echo -e "Server OS             : ${GREEN}${os_name}${NC} (Compatibility: ${YELLOW}$(uppercase_txt "$os_compatibility")${NC})"
  fi
  echo -e "System Uptime         : ${GREEN}$(trim_whitespace "$(uptime)")${NC}"
  echo -e "Users logged          : ${GREEN}$(trim_whitespace "$(who | wc -l)")${NC}"
  break_line
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
