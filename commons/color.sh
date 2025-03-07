#!/bin/bash

# Reset
NC='\033[0m' # No Color

# Regular Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

# Bold Colors
BBLACK='\033[1;30m'
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BPURPLE='\033[1;35m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

# Underline
UBLACK='\033[4;30m'
URED='\033[4;31m'
UGREEN='\033[4;32m'
UYELLOW='\033[4;33m'
UBLUE='\033[4;34m'
UPURPLE='\033[4;35m'
UCYAN='\033[4;36m'
UWHITE='\033[4;37m'

# Background Colors
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_PURPLE='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# Styling Helper Functions
print_header() {
  local text="$1"
  local padding=2 # Padding on each side
  local terminal_width=$(tput cols)
  local text_length=${#text}
  local total_padding=$(((terminal_width - text_length - 2) / 2))

  echo
  printf "${BBLUE}%${terminal_width}s${NC}\n" | tr ' ' '='
  printf "${BBLUE}|${NC}%${total_padding}s${BWHITE}%s${NC}%${total_padding}s${BBLUE}|${NC}\n" "" "$text" ""
  printf "${BBLUE}%${terminal_width}s${NC}\n" | tr ' ' '='
}

print_subheader() {
  local text="$1"
  echo -e "\n${BCYAN}> ${text}${NC}"
  echo -e "${CYAN}$(printf '%.s-' $(seq 1 $(tput cols)))${NC}"
}

print_menu_item() {
  local number="$1"
  local text="$2"
  local status="${3:-}"

  if [ -n "$status" ]; then
    echo -e "${BWHITE}$number)${NC} $text ${status}"
  else
    echo -e "${BWHITE}$number)${NC} $text"
  fi
}

print_menu_action() {
  local key="$1"
  local text="$2"
  echo -e "${BPURPLE}$key)${NC} $text"
}

print_success() {
  echo -e "${BGREEN}✓${NC} $1"
}

print_error() {
  echo -e "${BRED}✗${NC} $1"
}

print_warning() {
  echo -e "${BYELLOW}! $1${NC}"
}

print_info() {
  echo -e "${WHITE}$1${NC}"
}

print_separator() {
  echo -e "${BLUE}$(printf '%.s-' $(seq 1 $(tput cols)))${NC}"
}

# Status Indicators with simple ASCII
status_running() {
  echo -e "${BGREEN}[ RUNNING ]${NC}"
}

status_stopped() {
  echo -e "${BRED}[ STOPPED ]${NC}"
}

status_partial() {
  local running="$1"
  local total="$2"
  echo -e "${BYELLOW}[ PARTIAL: $running/$total ]${NC}"
}

status_loading() {
  echo -e "${BCYAN}[ LOADING ]${NC}"
}
