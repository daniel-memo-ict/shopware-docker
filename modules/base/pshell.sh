#!/usr/bin/env bash

set -e

checkParameter

shift

PROJECT_NAME=$1

shift

PHP_VERSION=default
SUFFIX=""

if [ -f "${CODE_DIRECTORY}/${PROJECT_NAME}/.phprc" ]; then
  PHP_VERSION=$(cat ${CODE_DIRECTORY}/${PROJECT_NAME}/.phprc | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1\2/')
fi

if [[ $XDEBUG_ENABLE == "xdebug" ]]; then
  SUFFIX="-xdebug"
fi

if [ -n "$1" ]; then
  while (($#)); do
    case $1 in
    --php-version)
      shift
      PHP_VERSION=$1
      ;;
    --xdebug)
      SUFFIX="-xdebug"
      ;;
    *)
      break
      ;;
    esac

    shift
  done
fi

if [[ $PHP_VERSION == 'default' ]]; then
  if [[ -z "$1" ]]; then
    compose exec -w "/var/www/html/$PROJECT_NAME" -e COLUMNS -e LINES -e SHELL=bash cli bash
  else
    compose exec -T -w "/var/www/html/$PROJECT_NAME" -e COLUMNS -e LINES -e SHELL=bash cli "$@"
  fi
else
  docker run \
    --rm \
    -it \
    -w "/var/www/html/$PROJECT_NAME" \
    --env-file="${REALDIR}/docker.env" \
    --env-file="${REALDIR}/.env.dist" \
    --env=file=~/.config/swdc/env \
    --network shopware-docker_default \
    -v shopware-docker_nvm_cache:/nvm \
    -v "$CODE_DIRECTORY:/var/www/html/" \
    -v "/.config/swdc/:/swdc-cfg" \
    "ghcr.io/daniel-memo-ict/shopware-docker/cli:php$PHP_VERSION$SUFFIX" "$@"
fi