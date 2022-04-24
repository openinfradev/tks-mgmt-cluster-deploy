#!/bin/bash

#!/bin/bash

set -e

source common.sh

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

export KUBECONFIG=kubeconfig_$CLUSTER_NAME

print_msg "Installing Keycloak..."

argo submit --from wftmpl/install-admin-tools -p app_prefix=tks-admin -p revision=$TKS_RELEASE -n argo

for ns in keycloak; do
        for po in $(kubectl get po -n $ns -o jsonpath='{.items[*].metadata.name}');do
                kubectl wait --for=condition=Ready -n $ns --timeout=180s po/$po
        done
done
print_msg "... done"
