#!/bin/bash

set -e

source lib/common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

log_info "Preparing Cluster API providers initilizaiton"

sudo cp $1/cluster-api/$CAPI_VERSION/clusterctl-linux-amd64 /usr/local/bin/clusterctl
sudo chmod +x /usr/local/bin/clusterctl

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

log_info "Installing Cluster API providers"

cp clusterctl.yaml ~/.cluster-api/

CAPI_NAMESPACE="cert-manager capi-system capi-kubeadm-bootstrap-system capi-kubeadm-control-plane-system"

for provider in ${CAPI_INFRA_PROVIDERS[@]}
do
	case $provider in
		"aws")
			sudo cp $1/cluster-api-provider-aws/$CAPA_VERSION/clusterawsadm-linux-amd64 /usr/local/bin/clusterawsadm
			sudo chmod +x /usr/local/bin/clusterawsadm

			export AWS_REGION
			export AWS_ACCESS_KEY_ID
			export AWS_SECRET_ACCESS_KEY

			export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
			export EXP_MACHINE_POOL=true
			
			CAPI_NAMESPACE+=" $provider-system"
			;;
		"byoh")
			CAPI_NAMESPACE+=" $provider-system"
			;;
	esac
done

gum spin --spinner dot --title "Waiting for providers to be installed..." -- clusterctl init --infrastructure $(printf -v joined '%s,' "${CAPI_INFRA_PROVIDERS[@]}"; echo "${joined%,}") --wait-providers

log_info "...Done"
