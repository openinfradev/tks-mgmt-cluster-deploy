#!/bin/bash

set -e

source lib/common.sh
source lib/capi.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

ASSET_DIR=${1%%/}

YQ_ASSETS_DIR="$ASSET_DIR/yq/$(ls $ASSET_DIR/yq | grep v)"
YQ_PATH="$YQ_ASSETS_DIR/yq_linux_amd64"
chmod +x $YQ_PATH

log_info "Installing Cluster API providers"
install_clusterctl
prepare_capi_providers kind ${BOOTSTRAP_CLUSTER_SERVER_IP}:5000
install_capi_providers kind ~/.kube/config

log_info "...Done"
