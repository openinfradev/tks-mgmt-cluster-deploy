#!/bin/bash

set -e

source lib/common.sh

export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

log_info "Installing NGINX Ingress..."
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace

sleep 10

gum spin --spinner dot --title "Wait for all pods ready in ingress-nginx namespace..." -- util/wait_for_all_pods_in_ns.sh ingress-nginx

log_info "... done"
