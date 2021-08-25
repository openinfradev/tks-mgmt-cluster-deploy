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
cd -

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
  - name: "aws"
    url: "file://localhost$(realpath $1)/infrastructure-aws/$CAPA_VERSION/infrastructure-components.yaml"
    type: "InfrastructureProvider"
  - name: "openstack"
    url: "file://localhost$(realpath $1)/infrastructure-openstack/$CAPO_VERSION/infrastructure-components.yaml"
    type: "InfrastructureProvider"
EOF

print_msg "Installing Cluster API providers"

cp clusterctl.yaml ~/.cluster-api/

case $CAPI_INFRA_PROVIDER in
	"aws")
		sudo cp $1/cluster-api-provider-aws/$CAPA_VERSION/clusterawsadm-linux-amd64 /usr/local/bin/clusterawsadm
		sudo chmod +x /usr/local/bin/clusterawsadm

		export AWS_REGION
		export AWS_ACCESS_KEY_ID
		export AWS_SECRET_ACCESS_KEY

		export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
		export EXP_MACHINE_POOL=true

		cd $1
		[ ! -L infrastructure-aws ] && ln -s cluster-api-provider-aws infrastructure-aws
		cd -
		;;
	"openstack")
		cd $1
		[ ! -L infrastructure-openstack ] && ln -s cluster-api-provider-openstack infrastructure-openstack
		cd-
		;;
esac

clusterctl init --infrastructure $CAPI_INFRA_PROVIDER
