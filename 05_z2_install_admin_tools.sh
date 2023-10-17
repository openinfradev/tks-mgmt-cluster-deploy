#!/bin/bash

set -e

source lib/common.sh

export KUBECONFIG=~/.kube/config

##TODO: add workflow-template for tks-admin-tools


log_info "Calling workflow to install admin-tools(keycloak, harbor, etc)..."

argo submit --from wftmpl/tks-install-admin-tools -n argo -p install_nginx=$INSTALL_NGINX_INGRESS -p manifest_repo_url="${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/${CLUSTER_NAME}-manifests" -p site_name=${CLUSTER_NAME} --watch

log_info "...Done"
