#!/bin/bash

#!/bin/bash

set -e

source lib/common.sh

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

log_info "Installing Keycloak..."

argo submit --from wftmpl/install-admin-tools -p app_prefix=tks-admin -p revision=$TKS_RELEASE -n argo --watch

sleep 30

gum spin --spinner dot --title "Wait for all pods ready in keycloak namespace..." -- util/wait_for_all_pods_in_ns.sh keycloak

log_info "... done"
