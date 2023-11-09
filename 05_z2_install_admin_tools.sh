#!/bin/bash

set -e

source lib/common.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export KUBECONFIG=$SCRIPT_DIR/output/kubeconfig_$CLUSTER_NAME

log_info "Calling workflow to install admin-tools(keycloak, harbor, etc)..."

argo submit --from wftmpl/tks-install-admin-tools -n argo -p install_nginx=$INSTALL_NGINX_INGRESS -p manifest_repo_url="${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/${CLUSTER_NAME}-manifests" -p site_name=${CLUSTER_NAME} -p db_common_password=$DATABASE_PASSWORD --watch

log_info "...Done"
