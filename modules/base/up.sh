#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${HOME}/.config/swdc/env"

if [[ "$RUN_MODE" == 'local' ]]; then
  # shellcheck source=modules/defaults/local-up.sh
  source "${REALDIR}/modules/defaults/local-up.sh"

  exit 0
fi

# shellcheck source=modules/defaults/base-up.sh
source "${REALDIR}/modules/defaults/base-up.sh"

if [[ ! -d "${CODE_DIRECTORY}" ]]; then
  mkdir -p "${CODE_DIRECTORY}"
fi

CODE_FOLDER_CONTENT="$(ls -A "${CODE_DIRECTORY}")"
export CODE_FOLDER_CONTENT="${CODE_FOLDER_CONTENT}"

PHP_VERSION="${PHP_VERSION//\./}"
export XDEBUG_ENABLE=$2

if [[ -n $XDEBUG_ENABLE ]]; then
  shift
fi
{
  echo "services:"

  echo "  smtp:"
  echo "    image: ghcr.io/shyim/shopware-docker/mailhog"
  echo "    environment:"
  echo "      VIRTUAL_HOST: mail.${DEFAULT_SERVICES_DOMAIN}"
  echo "      VIRTUAL_PORT: 8025"

  echo "  proxy:"
  echo "    image: ghcr.io/shyim/shopware-docker/proxy"
  echo "    volumes:"
  echo "      - /var/run/docker.sock:/tmp/docker.sock:ro"
  echo "      - ${HOME}/.config/swdc/ssl:/etc/nginx/certs"
  echo "    ports:"
  echo "      - ${HTTP_PORT}:80"
  echo "      - ${HTTPS_PORT}:443"
} >"${DOCKER_COMPOSE_FILE}"

create_nginx
create_mysql
create_start_mysql
create_cli

if [[ ${ENABLE_VARNISH} == "true" ]]; then
  create_varnish
fi

# Build alias for cli
if [[ ${ENABLE_ELASTICSEARCH} == "true" ]]; then
  create_es
fi

if [[ ${ENABLE_REDIS} == "true" ]]; then
  create_redis
fi

if [[ ${ENABLE_MINIO} == "true" ]]; then
  create_minio
fi

create_database_tool

if [[ ${ENABLE_SELENIUM} == "true" ]]; then
  create_selenium
fi

if [[ ${ENABLE_CYPRESS} == "true" ]]; then
  create_cypress
fi

if [[ ${ENABLE_BLACKFIRE} == "true" ]]; then
  create_blackfire
fi

{
  echo "volumes:"
  echo "  nvm_cache:"
  echo "    driver: local"
  echo "  tool_cache:"
  echo "    driver: local"

  if [[ ${ENABLE_REDIS} == "true" ]]; then
    echo "  redis_cache:"
    echo "    driver: local"
  fi
} >>"${DOCKER_COMPOSE_FILE}"

compose run --rm start_mysql
compose up -d --remove-orphans "${@:2}"

if [[ $WSL_XDEBUG_TUNNEL == "true" ]]; then
  if [[ -e "$REALDIR/xdebug.sock" ]]; then
    echo "Socat file exists. Skipping starting"
    exit 0
  fi

  nohup socat UNIX-LISTEN:"$REALDIR"/xdebug.sock,fork TCP:localhost:9000 >/dev/null 2>&1 &
fi
