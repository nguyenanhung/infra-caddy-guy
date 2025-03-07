#!/bin/bash

# Validate IP address
validate_ip() {
  local ip
  ip="$1"
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    local octets
    IFS='.' read -r -a octets <<<"$ip"
    for octet in "${octets[@]}"; do
      [ "$octet" -gt 255 ] && {
        message ERROR "Invalid IP address: $ip (octet $octet exceeds 255)"
        return 1
      }
      [[ "$octet" =~ ^0[0-9]+$ ]] && {
        message ERROR "Invalid IP address: $ip (leading zeros not allowed)"
        return 1
      }
    done
    return 0
  else
    message ERROR "Invalid IP address format: $ip"
    return 1
  fi
}

# Validate domain
validate_domain() {
  local domain
  domain="$1"
  if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9](\.[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9])*\.[a-zA-Z]{2,}$ ]]; then
    return 0
  else
    message ERROR "Invalid domain: $domain"
    return 1
  fi
}

# Validate URL
validate_url() {
  local url
  url="$1"
  if [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
    return 0
  else
    message ERROR "Invalid URL: $url"
    return 1
  fi
}

# Validate port
validate_port() {
  local port
  port="$1"
  if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
    return 0
  else
    message ERROR "Invalid port: $port (must be between 1 and 65535)"
    return 1
  fi
}

# Validate port mapping
validate_port_mapping() {
  local mapping
  mapping="$1"
  if [[ "$mapping" =~ ^([0-9]+)$ ]]; then
    validate_port "$mapping" || return 1
  elif [[ "$mapping" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
    local ip
    local port
    ip="${mapping%%:*}"
    port="${mapping##*:}"
    validate_ip "$ip" && validate_port "$port" || return 1
  else
    message ERROR "Invalid port mapping: $mapping (use port, ip:port, or 0.0.0.0:port)"
    return 1
  fi
  return 0
}

# Validate file existence
validate_file_exists() {
  local file
  file="$1"
  if [ -f "$file" ]; then
    return 0
  else
    message ERROR "File does not exist: $file"
    return 1
  fi
}

# Validate file not exists
validate_file_not_exists() {
  local file
  file="$1"
  if [ ! -f "$file" ]; then
    return 0
  else
    message ERROR "File already exists: $file"
    return 1
  fi
}
