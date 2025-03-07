#!/bin/bash
_infra_caddy_completions_build() {
  # List of available options for the "container" command
  local commands=(
    "init"
    "reload-caddy"
    "list"
    "enable-"
    "stop-"
    "start-"
    "restart-"
    "remove-"
    "log-"
    "logs"
    "install"
    "delete"
    "stop"
    "start"
    "restart"
    "basic-auth"
    "delete-basic-auth"
    "add-laravel"
    "delete-laravel"
    "add-reverse-proxy"
    "delete-reverse-proxy"
    "add-load-balancer"
    "delete-load-balancer"
    "delete-load-balancer-backend"
    "laravel-up"
    "laravel-down"
    "laravel-restore"
    "laravel-remove"
  )
  local cur="${COMP_WORDS[COMP_CWORD]}"
  mapfile -t COMPREPLY < <(compgen -W "${commands[*]}" -- "$cur")
}
complete -F _infra_caddy_completions_build infra-caddy
complete -F _infra_caddy_completions_build bear-caddy
