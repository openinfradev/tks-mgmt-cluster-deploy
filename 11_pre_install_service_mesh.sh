#!/bin/bash

set -e

source common.sh

CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
export KUBECONFIG=kubeconfig_$CLUSTER_NAME

print_msg "Labeling resources for Service Mesh ..."
for no in $(kubectl get node --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}'); do
	kubectl label nodes $no servicemesh=enabled --overwrite
	kubectl label nodes $no taco-ingress-gateway=enabled --overwrite
	kubectl label nodes $no taco-egress-gateway=enabled --overwrite
done
print_msg "... done"
