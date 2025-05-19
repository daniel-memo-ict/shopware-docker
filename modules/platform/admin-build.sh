#!/usr/bin/env bash

checkParameter

cd "${SHOPWARE_FOLDER}" || exit 1

setup_node_version

bin/build-administration.sh