#!/bin/bash

# Set BASE_DIR reliably based on main.sh location
if command -v realpath >/dev/null 2>&1; then
  BASE_DIR="$(dirname "$(realpath "$0")")"
else
  # Fallback for systems without realpath
  BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# Export BASE_DIR to be available in sourced files
export BASE_DIR

source "$BASE_DIR/commons/config.sh"
source "$BASE_DIR/commons/utils.sh"
source "$BASE_DIR/services/caddy.sh"
source "$BASE_DIR/commons/menu.sh"


# Ask for database usage
domain="abc.com"
use_db=$(prompt_with_fzf "Use a database?" "Yes No")
db_type=""
db_separate=""
db_container=""
if [ "$use_db" = "Yes" ]; then
  db_type=$(prompt_with_fzf "Select database type" "mariadb mongodb postgresql")
  db_separate=$(prompt_with_fzf "Create separate database container?" "Yes No")
  if [ "$db_separate" = "Yes" ]; then
    db_container="db_${domain}_${db_type}"
  else
    db_container="${PREFIX_NAME}_${db_type}"
  fi
fi
echo "$db_container"
