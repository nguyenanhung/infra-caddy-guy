#!/bin/bash

# Default prefix name for containers/services
PREFIX_NAME="bear"
DEVELOP_BY="Hung Nguyen - hungna.dev@gmail.com"
SCRIPT_VERSION="1.0.0"
SCRIPT_BACKUP_ORIGIN_FILE=".bear.backup.original"
PM2_USER="hungna"

# Default network for Caddy
NETWORK_NAME="${PREFIX_NAME}_caddy_net"

# Default Caddy Container
CADDY_CONTAINER_NAME="${PREFIX_NAME}_caddy"

# Default Home Directory -> mount to /var/www
CADDY_HOME_DIR="/home/infra-caddy-sites"

# Default Container Configuration
DEFAULT_CONTAINER_LOG_DRIVER="local"
DEFAULT_CONTAINER_LOG_MAX_SIZE="10m"
DEFAULT_CONTAINER_LOG_MAX_FILE="3"

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
  ["n8n"]="n8nio/n8n:latest"
  ["minio"]="bitnami/minio:latest"
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
  ["elasticsearch"]="--cpus=1 --memory=1g"
  ["mailhog"]="--cpus=0.5 --memory=256m"
  ["phpmyadmin"]="--cpus=0.5 --memory=512m"
  ["adminer"]="--cpus=0.5 --memory=256m"
  ["uptime-kuma"]="--cpus=0.5 --memory=512m"
  ["n8n"]="--cpus=1 --memory=1g"
  ["minio"]="--cpus=1 --memory=1g"
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
  ["n8n"]="5678"
  ["minio"]="9001"
)

# Default healthcheck commands (customized per service)
declare -A SERVICE_HEALTHCHECKS
SERVICE_HEALTHCHECKS=(
  ["redis"]="redis-cli -a \$REDIS_PASSWORD ping -h localhost"
  ["memcached"]="printf 'stats\n' | nc -w 1 localhost 11211"
  ["mongodb"]="mongosh -u \$MONGO_INITDB_ROOT_USERNAME -p \$MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval 'db.runCommand({ping:1})' --quiet"
  ["mariadb"]="mariadb-admin ping -h 127.0.0.1 -u\$MYSQL_USER -p\$MYSQL_PASSWORD --silent"
  ["mysql"]="mysql -h 127.0.0.1 -u\$MYSQL_USER -p\$MYSQL_PASSWORD -e 'SELECT 1' --silent --skip-column-names"
  ["percona"]="mysql -h 127.0.0.1 -u\$MYSQL_USER -p\$MYSQL_PASSWORD -e 'SELECT 1' --silent --skip-column-names"
  ["postgresql"]="PGPASSWORD=\$POSTGRES_USER pg_isready -h localhost -U \$POSTGRES_PASSWORD -d \$POSTGRES_DB"
  ["influxdb"]="influx -username \$INFLUXDB_ADMIN_USER-password \$INFLUXDB_ADMIN_PASSWORD -database \$INFLUXDB_DB ping"
  ["rabbitmq"]="rabbitmq-diagnostics check_port_listener"
  ["beanstalkd"]="echo stats | nc -w 1 localhost 11300"
  ["gearmand"]="gearadmin --server-version"
  ["elasticsearch"]="curl -s -u \$ELASTIC_USERNAME:\$ELASTIC_PASSWORD \$ELASTICSEARCH_URL/_cluster/health | grep -q '\"status\":\"green\"'"
  ["mailhog"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:8025"
  ["phpmyadmin"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:80"
  ["adminer"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:8080"
  ["uptime-kuma"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:3001"
  ["n8n"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:5678"
  ["minio"]="curl -s -o /dev/null -w '%{http_code}' http://localhost:9001"
)

declare -A SERVICE_MOUNT_PATHS
SERVICE_MOUNT_PATHS=(
  ["redis"]="/data"
  ["memcached"]=""
  ["mongodb"]="/data/db"
  ["mariadb"]="/var/lib/mysql"
  ["mysql"]="/var/lib/mysql"
  ["percona"]="/var/lib/mysql"
  ["postgresql"]="/var/lib/postgresql/data"
  ["influxdb"]="/var/lib/influxdb2"
  ["rabbitmq"]="/var/lib/rabbitmq"
  ["beanstalkd"]=""
  ["gearmand"]=""
  ["elasticsearch"]="/usr/share/elasticsearch/data"
  ["mailhog"]=""
  ["phpmyadmin"]=""
  ["adminer"]=""
  ["uptime-kuma"]="/app/data"
  ["n8n"]="/home/node/.n8n"
  ["minio"]="/data"
)
docker_compose_command() {
  if command -v docker-compose &>/dev/null; then
    docker-compose "$@"
  elif docker compose version &>/dev/null; then
    docker compose "$@"
  else
    echo "❌ Error: Neither 'docker-compose' nor 'docker compose' is installed." >&2
    return 1
  fi
}
