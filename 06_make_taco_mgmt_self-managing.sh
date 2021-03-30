#!/bin/bash

set -e

source common.sh

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]
  then
    echo "usage: $0 <assets dir> <clouds.yaml> <os_cloud_name> <values.yaml for mgmt cluster>"
    echo "See the example-clouds.yaml and example-values_mgmt_cluster.yaml."
    exit 1
fi

print_msg "Initializing cluster API provider components in TACO management cluster"

CLUSTER_NAME=$(yq eval .cluster_name $4)

clusterctl init --infrastructure openstack --kubeconfig kubeconfig_$CLUSTER_NAME

while true
do
  [ $(kubectl --kubeconfig kubeconfig_$CLUSTER_NAME get po -n capi-webhook-system | grep Running | wc -l) != 4 ] && continue
  sleep 30

  break
done

print_msg  "Pre-check before pivot"
clusterctl move --to-kubeconfig kubeconfig_$CLUSTER_NAME --dry-run -v10

print_msg "Pivoting to make TACO management cluster self-managing"
clusterctl move --to-kubeconfig kubeconfig_$CLUSTER_NAME

print_msg "Finished. Check the status of all cluster API resources"
