#!/bin/bash

set -e

source lib/common.sh

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

log_info "Installing cert-manager..."
result=$(helm show chart --repo https://harbor-cicd.taco-cat.xyz/chartrepo/tks cert-manager)
appVersion=$(echo "$result" | grep "^appVersion:" | cut -d ' ' -f 2);

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$appVersion/cert-manager.crds.yaml
helm upgrade --install cert-manager cert-manager \
  --repo https://harbor-cicd.taco-cat.xyz/chartrepo/tks \
  --namespace cert-manager --create-namespace

sleep 10

gum spin --spinner dot --title "Wait for all pods ready in cert-manager namespace..." -- util/wait_for_all_pods_in_ns.sh cert-manager

log_info "... done"
