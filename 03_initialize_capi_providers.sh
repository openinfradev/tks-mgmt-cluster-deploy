#!/bin/bash

set -e

source common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

print_msg "Preparing Cluster API providers initilizaiton"

cd $1
[ ! -L bootstrap-kubeadm ] && ln -s cluster-api bootstrap-kubeadm
[ ! -L control-plane-kubeadm ] && ln -s cluster-api control-plane-kubeadm
[ ! -L infrastructure-openstack ] && ln -s cluster-api-provider-openstack infrastructure-openstack
cd -

CAPI_VERSION=$(ls $1/cluster-api)
CAPO_VERSION=$(ls $1/cluster-api-provider-openstack)

sudo cp $1/cluster-api/$CAPI_VERSION/clusterctl-linux-amd64 /usr/local/bin/clusterctl
sudo chmod +x /usr/local/bin/clusterctl
clusterctl version # TODO: air gap?

cat > clusterctl.yaml <<EOF
providers:
  - name: "cluster-api"
    url: "file://localhost$(realpath $1)/cluster-api/$CAPI_VERSION/core-components.yaml"
    type: "CoreProvider"
  - name: "kubeadm"
    url: "file://localhost$(realpath $1)/bootstrap-kubeadm/$CAPI_VERSION/bootstrap-components.yaml"
    type: "BootstrapProvider"
  - name: "kubeadm"
    url: "file://localhost$(realpath $1)/control-plane-kubeadm/$CAPI_VERSION/control-plane-components.yaml"
    type: "ControlPlaneProvider"
  - name: "openstack"
    url: "file://localhost$(realpath $1)/infrastructure-openstack/$CAPO_VERSION/infrastructure-components.yaml"
    type: "InfrastructureProvider"
EOF

print_msg "Installing Cluster API providers"
cp clusterctl.yaml ~/.cluster-api/
clusterctl init --infrastructure openstack
