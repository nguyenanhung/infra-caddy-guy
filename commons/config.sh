#!/bin/bash

# Default prefix name for containers/services
PREFIX_NAME="bear"
DEVELOP_BY="Hung Nguyen - hungna.dev@gmail.com"
SCRIPT_VERSION="1.0.0"
SCRIPT_BACKUP_ORIGIN_FILE=".bear.backup.original"
PM2_USER="hungna"

# Default network for Caddy
NETWORK_NAME="${PREFIX_NAME}_caddy_net"

# Base directory of the project (root of bear-caddy/)
# Use BASE_DIR from main.sh if set; otherwise calculate from config.sh
if [ -z "$BASE_DIR" ]; then
  if command -v realpath >/dev/null 2>&1; then
    BASE_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
  else
    # Fallback for systems without realpath
    BASE_DIR="$(cd "$(dirname "$(dirname "$0")")" && pwd)"
  fi
fi
CONFIG_DIR="$BASE_DIR/config"
CONTAINER_DIR="$BASE_DIR/container"
VOLUMES_DIR="$BASE_DIR/volumes"

# Default backup directory
BACKUP_DIR="/tmp/bear_caddy_backup"
[ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"

# Default mappings for services and images
declare -A SERVICE_IMAGES
SERVICE_IMAGES=(
  ["caddy"]="caddy:latest"
  ["redis"]="redis:latest"
  ["memcached"]="memcached:latest"
  ["mongodb"]="mongo:latest"
  ["mariadb"]="mariadb:latest"
  ["mysql"]="mysql:latest"
  ["percona"]="mysql:latest"
  ["postgresql"]="postgres:latest"
  ["influxdb"]="influxdb:latest"
  ["rabbitmq"]="rabbitmq:latest"
  ["beanstalkd"]="beanstalkd:latest"
  ["gearmand"]="gearmand:latest"
  ["elasticsearch"]="elasticsearch:8.17.3"
  ["mailhog"]="mailhog/mailhog:latest"
  ["phpmyadmin"]="phpmyadmin:latest"
  ["adminer"]="adminer:latest"
  ["uptime-kuma"]="louislam/uptime-kuma:latest"
)

# Default resource limits
declare -A SERVICE_RESOURCES
SERVICE_RESOURCES=(
  ["default"]="--cpus=1 --memory=512m"
  ["redis"]="--cpus=0.5 --memory=256m"
  ["memcached"]="--cpus=0.5 --memory=256m"
  ["mongodb"]="--cpus=1 --memory=1g"
  ["mariadb"]="--cpus=1 --memory=1g"
  ["mysql"]="--cpus=1 --memory=1g"
  ["percona"]="--cpus=1 --memory=1g"
  ["postgresql"]="--cpus=1 --memory=1g"
  ["influxdb"]="--cpus=1 --memory=1g"
  ["rabbitmq"]="--cpus=1 --memory=512m"
  ["beanstalkd"]="--cpus=0.5 --memory=256m"
  ["gearmand"]="--cpus=0.5 --memory=256m"
  ["elasticsearch"]="--cpus=0.5 --memory=512m"
  ["mailhog"]="--cpus=0.5 --memory=256m"
  ["phpmyadmin"]="--cpus=0.5 --memory=512m"
  ["adminer"]="--cpus=0.5 --memory=256m"
  ["uptime-kuma"]="--cpus=0.5 --memory=512m"
)

# Default ports (internal)
declare -A SERVICE_PORTS
SERVICE_PORTS=(
  ["redis"]="6379"
  ["memcached"]="11211"
  ["mongodb"]="27017"
  ["mariadb"]="3306"
  ["mysql"]="3306"
  ["percona"]="3306"
  ["postgresql"]="5432"
  ["influxdb"]="8086"
  ["rabbitmq"]="5672"
  ["beanstalkd"]="11300"
  ["gearmand"]="4730"
  ["elasticsearch"]="9200"
  ["mailhog"]="8025"
  ["phpmyadmin"]="80"
  ["adminer"]="8080"
  ["uptime-kuma"]="3001"
)

# Default healthcheck commands (customized per service)
declare -A SERVICE_HEALTHCHECKS
SERVICE_HEALTHCHECKS=(
  ["redis"]="redis-cli ping -h localhost"
  ["memcached"]="printf 'stats\n' | nc -w 1 localhost 11211"
  ["mongodb"]="mongosh --eval 'db.runCommand({ping:1})' --quiet"
  ["mariadb"]="mariadb-admin ping -h 127.0.0.1 -u\$MYSQL_USER -p\$MYSQL_PASSWORD --silent"
  ["mysql"]="mysql -h 127.0.0.1 -u\$MYSQL_USER -p\$MYSQL_PASSWORD -e 'SELECT 1' --silent --skip-column-names"
  ["percona"]="mysql -h 127.0.0.1 -u\$MYSQL_USER -p\$MYSQL_PASSWORD -e 'SELECT 1' --silent --skip-column-names"
  ["postgresql"]="pg_isready -h localhost"
  ["influxdb"]="influx ping || exit 1"
  ["rabbitmq"]="rabbitmq-diagnostics check_port_listener"
  ["beanstalkd"]="echo stats | nc -w 1 localhost 11300"
  ["gearmand"]="gearadmin --server-version"
  ["elasticsearch"]="curl -s -u \$ELASTIC_USERNAME:\$ELASTIC_PASSWORD \$ELASTICSEARCH_URL/_cluster/health | grep -q '\"status\":\"green\"'"
  ["mailhog"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:8025"
  ["phpmyadmin"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:80"
  ["adminer"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:8080"
  ["uptime-kuma"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:3001"
)
