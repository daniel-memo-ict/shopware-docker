#!/usr/bin/env bash

Platform=$(uname -s)
export Platform="${Platform}"

function create_nginx() {
  if [[ ${CODE_FOLDER_CONTENT} ]]; then

    while IFS= read -r NAME; do
      d="${CODE_DIRECTORY}/${NAME}"

      hosts=$(get_hosts "$NAME")
      certName=$(get_cert_name "$NAME")
      documentRoot=$(get_document_root "$NAME" "$d")
      echo "  app_${NAME}:" >>"${DOCKER_COMPOSE_FILE}"

      if [[ -e "$d/.swdc/service.yml" ]]; then
        sed 's/^/    /' "$d/.swdc/service.yml" >> "${DOCKER_COMPOSE_FILE}"
      else
        if [[ -e "$d/.swdc/Dockerfile" ]]; then
          echo "    build: ${d}/.swdc/" >>"${DOCKER_COMPOSE_FILE}"
        else
          IMAGE=$(get_image "$NAME" "$d")
          echo "    image: ${IMAGE}" >>"${DOCKER_COMPOSE_FILE}"
        fi

        {
          echo "    env_file:"
          echo "      - ${REALDIR}/docker.env"
          echo "      - ~/.config/swdc/env"
          echo "    networks:"
          echo "      default:"
          echo "        aliases:"
        } >>"${DOCKER_COMPOSE_FILE}"

        for i in ${hosts//,/ }; do
          echo "          - ${i}" >>"${DOCKER_COMPOSE_FILE}"
        done

        {
          echo "    environment:"
          echo "      APP_DOCUMENT_ROOT: ${documentRoot}"
        } >>"${DOCKER_COMPOSE_FILE}"

        if [[ ${ENABLE_VARNISH} == "false" ]]; then
          {
            echo "      VIRTUAL_HOST: ${hosts}"
            echo "      CERT_NAME: ${certName}"
            echo "      HTTPS_METHOD: noredirect"
          } >>"${DOCKER_COMPOSE_FILE}"
        fi
        {
          echo "    volumes:"
          echo "      - ${REALDIR}:/opt/swdc"
        } >>"${DOCKER_COMPOSE_FILE}"
          if [[ -e "${d}/php.ini" ]]; then
            echo "      - ${d}/php.ini:/usr/local/etc/php/conf.d/swdc-custom.ini" >>"${DOCKER_COMPOSE_FILE}"
          fi
          if [[ -e "${d}/nginx.conf" ]]; then
            echo "      - ${d}/nginx.conf:/etc/nginx/sites-enabled/00-custom.conf" >>"${DOCKER_COMPOSE_FILE}"
          fi

          echo "      - ${CODE_DIRECTORY}:/var/www/html" >>"${DOCKER_COMPOSE_FILE}"
      fi
    done <<<"$(get_serve_folders)"
  fi
}

function create_mysql() {
  {
    echo "  mysql:"
    echo "    image: ${MYSQL_VERSION}"
    echo "    env_file: ${REALDIR}/docker.env"
  } >>"${DOCKER_COMPOSE_FILE}"
  if [[ ${EXPOSE_MYSQL_LOCAL} == "true" ]]; then
    {
      echo "    ports:"
      echo "      - 3306:3306"
    } >>"${DOCKER_COMPOSE_FILE}"
  fi
  if [[ ${PERSISTENT_DATABASE} == "false" ]]; then
    {
      echo "    tmpfs:"
      echo "      - /var/lib/mysql"
    } >>"${DOCKER_COMPOSE_FILE}"
  fi

  if [[ ${PERSISTENT_DATABASE} == "true" || -e "$HOME/.config/swdc/mysql.conf" ]]; then
    echo "    volumes:" >> "${DOCKER_COMPOSE_FILE}"
  fi

  if [[ ${PERSISTENT_DATABASE} == "true" ]]; then
    echo "      - ${MYSQL_DATA_DIR:-$REALDIR}/mysql-data:/var/lib/mysql:delegated" >> "${DOCKER_COMPOSE_FILE}"
  fi

  if [[ -e "$HOME/.config/swdc/mysql.conf" ]]; then
    echo "      - $HOME/.config/swdc/mysql.conf:/etc/mysql/conf.d/zz-override.cnf" >> "${DOCKER_COMPOSE_FILE}"
  fi
}

function create_start_mysql() {
  cat <<EOF >>"${DOCKER_COMPOSE_FILE}"
  start_mysql:
    image: busybox:latest
    volumes:
      - nvm_cache:/nvm
      - tool_cache:/tmp/swdc-tool-cache
    entrypoint:
      - sh
    command: >
      -c "
        chown 1000:1000 /nvm
        chown 1000:1000 /tmp/swdc-tool-cache
        while !(nc -z mysql 3306)
        do
          #echo -n '.'
          sleep 1
        done;
        #echo 'database ready!'
      "
    depends_on:
      - mysql
EOF
}

function create_cli() {
  {
    SUFFIX=""
    if [[ $XDEBUG_ENABLE == "xdebug" ]]; then
        SUFFIX="-xdebug"
    fi

    echo "  cli:"
    if [[ -e "$HOME/.config/swdc/cli/Dockerfile" ]]; then
      echo "    build: $HOME/.config/swdc/cli" >>"${DOCKER_COMPOSE_FILE}"
    else
      echo "    image: ghcr.io/daniel-memo-ict/shopware-docker/cli:php${PHP_VERSION}${SUFFIX}"
    fi
    echo "    env_file:"
    echo "      - ${REALDIR}/docker.env"
    echo "      - ${REALDIR}/.env.dist"
    echo "      - ~/.config/swdc/env"
    echo "    tty: true"
    echo "    ports:"
    echo "      - 8181:8181"
    echo "      - 8005:8005"
#    echo "      - 9998:9998"
#    echo "      - 9999:9999"
    echo "    volumes:"
    echo "      - ${REALDIR}:/opt/swdc"
    echo "      - nvm_cache:/nvm"
    echo "      - tool_cache:/tmp/swdc-tool-cache"
    echo "      - ~/.config/swdc/:/swdc-cfg"
  } >>"${DOCKER_COMPOSE_FILE}"

  if [[ ${CODE_FOLDER_CONTENT} ]]; then
    echo "      - ${CODE_DIRECTORY}:/var/www/html" >>"${DOCKER_COMPOSE_FILE}"
  fi
}

function create_es() {
  {
    echo "  elastic:"
    echo "    image: ${ELASTICSEARCH_IMAGE}"
    echo "    ports:"
    echo "      - 9200:9200"
    echo "    environment:"
    echo "      VIRTUAL_HOST: es.${DEFAULT_SERVICES_DOMAIN}"
    echo "      VIRTUAL_PORT: 9200"
    echo "      discovery.type: single-node"

    if [[ "${ELASTICSEARCH_IMAGE}" == *"amazon" ]]; then
      echo "      opendistro_security.ssl.http.enabled: 'false'"
    fi

    if [[ "${ELASTICSEARCH_IMAGE}" == *"opensearchproject"* ]]; then
      echo "      OPENSEARCH_INITIAL_ADMIN_PASSWORD: '${OPENSEARCH_INITIAL_ADMIN_PASSWORD}'"
    fi

    echo "  kibana:"
    echo "    image: ${KIBANA_IMAGE}"
    echo "    links:"
    echo "      - elastic:elasticsearch"
    echo "    environment:"
    echo "      VIRTUAL_HOST: kibana.${DEFAULT_SERVICES_DOMAIN}"
    echo "      VIRTUAL_PORT: 5601"

    if [[ "${ELASTICSEARCH_IMAGE}" == *"amazon" ]]; then
      echo "      ELASTICSEARCH_URL: http://elastic:9200"
      echo "      ELASTICSEARCH_HOSTS: http://elastic:9200"
    fi

    if [[ "${ELASTICSEARCH_IMAGE}" == *"opensearchproject"* ]]; then
      echo "      OPENSEARCH_HOSTS: '[\"http://elastic:9200\"]'"
      echo "      DISABLE_SECURITY_DASHBOARDS_PLUGIN: true"
    fi
  } >>"${DOCKER_COMPOSE_FILE}"
}

function create_redis() {
  {
    echo "  redis:"
    echo "    image: redis:6.2-alpine"
    echo "    volumes:"
    echo "      - redis_cache:/data"
  } >>"${DOCKER_COMPOSE_FILE}"
}

function create_minio() {
  {
    echo "  minio:"
    echo "    image: minio/minio"
    echo "    env_file: ${REALDIR}/docker.env"
    echo "    command: server /data --console-address=':9015'"
    echo "    ports:"
    echo "      - 9010:9000"
    echo "      - 9015:9015"
    echo "    environment:"
    echo "      VIRTUAL_HOST: s3.${DEFAULT_SERVICES_DOMAIN}"
    echo "      VIRTUAL_PORT: 9015"
  } >>"${DOCKER_COMPOSE_FILE}"
}

function create_database_tool() {
  if [[ ${DATABASE_TOOL} == "phpmyadmin" ]]; then
    {
      echo "  phpmyadmin:"
      echo "    image: phpmyadmin/phpmyadmin"
      echo "    env_file:"
      echo "      - ${REALDIR}/docker.env"
      echo "      - ${REALDIR}/phpmyadmin.env"
      echo "    environment:"
      echo "      VIRTUAL_HOST: db.${DEFAULT_SERVICES_DOMAIN}"
    } >>"${DOCKER_COMPOSE_FILE}"
  else
    {
      echo "  adminer:"
      echo "    image: ghcr.io/daniel-memo-ict/shopware-docker/adminer"
      echo "    env_file:"
      echo "      - ${REALDIR}/docker.env"
      echo "      - ${REALDIR}/adminer.env"
      echo "    environment:"
      echo "      VIRTUAL_HOST: db.${DEFAULT_SERVICES_DOMAIN}"
      echo "      VIRTUAL_PORT: 8080"
    } >>"${DOCKER_COMPOSE_FILE}"
  fi
}

function create_selenium() {
  cat <<EOF | tee -a "${DOCKER_COMPOSE_FILE}" > /dev/null
  selenium:
    image: selenium/standalone-chrome:84.0
    shm_size: 2g
    environment:
      DBUS_SESSION_BUS_ADDRESS: /dev/null
      SCREEN_WIDTH: 1920
      SCREEN_HEIGHT: 1080
      SCREEN_DPI: 72
    ports:
      - 5900:5900
EOF

  if [[ ${CODE_FOLDER_CONTENT} ]]; then
    echo "    links:" >>"${DOCKER_COMPOSE_FILE}"

    while IFS= read -r NAME; do
      hosts=$(get_hosts "$NAME")
      for i in ${hosts//,/ }; do
        echo "      - app_${NAME}:${i}" >>"${DOCKER_COMPOSE_FILE}"
      done
    done <<<"$(get_serve_folders)"
  fi
}

function create_cypress() {
  {
    echo "  cypress-backup-proxy:"
    echo "    image: ghcr.io/daniel-memo-ict/shopware-docker/cypress-backup-proxy:latest"
    echo "    env_file:"
    echo "      - ${REALDIR}/docker.env"
    echo "    volumes:"
    echo "      - /var/run/docker.sock:/var/run/docker.sock"
  } >>"${DOCKER_COMPOSE_FILE}"
}

function create_blackfire() {
  {
    echo "  blackfire:"
    echo "    image: blackfire/blackfire:2"
    echo "    environment:"
    echo "      BLACKFIRE_SERVER_ID: ${BLACKFIRE_SERVER_ID}"
    echo "      BLACKFIRE_SERVER_TOKEN: ${BLACKFIRE_SERVER_TOKEN}"
    echo "      BLACKFIRE_DISABLE_LEGACY_PORT: 1"
  } >>"${DOCKER_COMPOSE_FILE}"
}

function create_varnish() {
  {
    echo "  varnish:"
    echo "    image: varnish"
    echo "    environment:"
    echo "      VIRTUAL_HOST: '*.${DEFAULT_DOMAIN}'"
    echo "      CERT_NAME: shared"
    echo "      HTTPS_METHOD: noredirect"
    echo "    volumes:"
    echo "      - ${REALDIR}/default.vcl:/etc/varnish/default.vcl"
  } >>"${DOCKER_COMPOSE_FILE}"
}
function create_landing() {
  local landing_dir="${REALDIR}/swdc-landing"
  mkdir -p "${landing_dir}"

  # Build landing index.html dynamically based on known apps and tools
  {
    echo "<!doctype html>"
    echo "<html><head><meta charset=\"utf-8\"><title>SWDC Landing</title>"
    echo "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    echo "<style>body{font-family:system-ui,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:2rem;} h1{margin-top:0} ul{line-height:1.8} code{background:#f4f4f4;padding:2px 4px;border-radius:3px} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:12px} .card{border:1px solid #eee;border-radius:8px;padding:12px} .muted{color:#666;font-size:.9em}</style>"
    echo "</head><body>"
    echo "<h1>Shopware Docker Landing Page</h1>"
    echo "<p class=\"muted\">Generated at $(date -u +'%-d %b %Y %H:%M UTC').</p>"
    echo "<h2>Projects</h2>"
    echo "<div class=\"grid\">"
  } >"${landing_dir}/index.html"

  if [[ ${CODE_FOLDER_CONTENT} ]]; then
    while IFS= read -r NAME; do
      url=$(get_url "$NAME")
      hosts=$(get_hosts "$NAME")
      {
        echo "  <div class=\"card\">"
        echo "    <div><strong>${NAME}</strong></div>"
        echo "    <div><a href=\"${url}\">${url}</a></div>"
        echo "    <div><a href=\"${url}/admin\">${url}/admin</a></div>"
        echo "    <div class=\"muted\">hosts: <code>${hosts}</code></div>"
        echo "  </div>"
      } >>"${landing_dir}/index.html"
    done <<<"$(get_serve_folders)"
  else
    echo "  <div class=\"card\">No projects found in <code>${CODE_DIRECTORY}</code></div>" >>"${landing_dir}/index.html"
  fi

  {
    echo "</div>"
    echo "<h2>Tools</h2>"
    echo "<ul>"
    # Mailpit is always created by base up.sh
    echo "  <li><a href=\"http://mail.${DEFAULT_SERVICES_DOMAIN}\">Mailpit</a></li>"
  } >>"${landing_dir}/index.html"

  if [[ ${DATABASE_TOOL} == "phpmyadmin" ]]; then
    echo "  <li><a href=\"http://db.${DEFAULT_SERVICES_DOMAIN}\">phpMyAdmin</a></li>" >>"${landing_dir}/index.html"
  else
    echo "  <li><a href=\"http://db.${DEFAULT_SERVICES_DOMAIN}\">Adminer</a></li>" >>"${landing_dir}/index.html"
  fi

  if [[ ${ENABLE_ELASTICSEARCH} == "true" ]]; then
    echo "  <li><a href=\"http://kibana.${DEFAULT_SERVICES_DOMAIN}\">Kibana</a></li>" >>"${landing_dir}/index.html"
  fi
  if [[ ${ENABLE_MINIO} == "true" ]]; then
    echo "  <li><a href=\"http://s3.${DEFAULT_SERVICES_DOMAIN}:9015\">MinIO Console</a></li>" >>"${landing_dir}/index.html"
  fi

  echo "</ul>" >>"${landing_dir}/index.html"
  echo "</body></html>" >>"${landing_dir}/index.html"

  # Define minimal static server behind proxy
  {
    echo "  landing:"
    echo "    image: nginx:alpine"
    echo "    environment:"
    echo "      VIRTUAL_HOST: ${DEFAULT_SERVICES_DOMAIN}"
    echo "      VIRTUAL_PORT: 80"
    echo "    volumes:"
    echo "      - ${landing_dir}:/usr/share/nginx/html:ro"
  } >>"${DOCKER_COMPOSE_FILE}"
}