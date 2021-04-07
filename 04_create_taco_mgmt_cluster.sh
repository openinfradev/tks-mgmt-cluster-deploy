#!/bin/bash

set -e

source common.sh

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]
  then
    echo "usage: $0 <assets dir> <clouds.yaml> <os_cloud_name> <values.yaml for mgmt cluster>"
    echo "See the example-clouds.yaml and example-values_mgmt_cluster.yaml."
    exit 1
fi

print_msg "Creating TACO Management Cluster via Cluster API"

YQ_VERSION=$(ls $1/yq)
sudo cp $1/yq/$YQ_VERSION/yq_linux_amd64 /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq

CAPI_CHART_DIR=$1/taco-helm/cluster-api-openstack
$CAPI_CHART_DIR/scripts/create_cloud-config_secret.sh $2 $3
helm install taco-mgmt $CAPI_CHART_DIR  -f $4

print_msg "TACO managed cluster chart successfully installed"
