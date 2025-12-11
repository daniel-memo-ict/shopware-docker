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
  echo "    image: axllent/mailpit:latest"
  echo "    environment:"
  echo "      VIRTUAL_HOST: mail.${DEFAULT_SERVICES_DOMAIN}"
  echo "      VIRTUAL_PORT: 8025"

  echo "  proxy:"
  echo "    image: ghcr.io/daniel-memo-ict/shopware-docker/proxy"
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
create_landing

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

# Optionally open the landing page in the default browser once services are ready
if [[ "${AUTO_OPEN_LANDING}" == "true" ]]; then
  # Build landing URL (landing served on DEFAULT_SERVICES_DOMAIN)
  if [[ "${USE_SSL_DEFAULT}" == "true" ]]; then
    __scheme="https"
    __port="${HTTPS_PORT}"
    if [[ "${HTTPS_PORT}" == "443" ]]; then
      __port_suffix=""
    else
      __port_suffix=":"${HTTPS_PORT}
    fi
  else
    __scheme="http"
    __port="${HTTP_PORT}"
    if [[ "${HTTP_PORT}" == "80" ]]; then
      __port_suffix=""
    else
      __port_suffix=":"${HTTP_PORT}
    fi
  fi

  __host="${DEFAULT_SERVICES_DOMAIN}"
  __url="${__scheme}://${__host}${__port_suffix}"

  # Wait until the landing becomes reachable (up to 120s)
  __max_wait=120
  __waited=0
  while true; do
    __code=$(curl -ks -o /dev/null -w "%{http_code}" "${__url}" || true)
    if [[ "${__code}" =~ ^2|3 ]]; then
      break
    fi
    sleep 1
    __waited=$((__waited+1))
    if [[ ${__waited} -ge ${__max_wait} ]]; then
      break
    fi
  done

  # Open URL depending on platform / environment
  __opener=""
  if command -v xdg-open >/dev/null 2>&1; then
    __opener="xdg-open"
  fi

  # Detect WSL and prefer wslview/cmd.exe
  if [[ -n "${WSL_DISTRO_NAME}" ]] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    if command -v wslview >/dev/null 2>&1; then
      wslview "${__url}" >/dev/null 2>&1 &
    else
      cmd.exe /c start "${__url}" >/dev/null 2>&1 &
    fi
  elif [[ "${Platform}" == "Darwin" ]]; then
    open "${__url}" >/dev/null 2>&1 &
  else
    if [[ -n "${__opener}" ]]; then
      ${__opener} "${__url}" >/dev/null 2>&1 &
    else
      echo "Landing page: ${__url}" >&2
    fi
  fi
fi


if [[ $WSL_XDEBUG_TUNNEL == "true" ]]; then
  if [[ -e "$REALDIR/xdebug.sock" ]]; then
    echo "Socat file exists. Skipping starting"
    exit 0
  fi

  nohup socat UNIX-LISTEN:"$REALDIR"/xdebug.sock,fork TCP:localhost:9000 >/dev/null 2>&1 &
fi
