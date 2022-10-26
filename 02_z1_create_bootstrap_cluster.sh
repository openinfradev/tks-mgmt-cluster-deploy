#!/bin/bash

set -e

source lib/common.sh

if [ -z "$1" ]; then
    echo "usage: $0 <assets dir>"
    exit 1
fi

ASSETS_DIR=$1
KIND_ASSETS_DIR="$1/kind/$(ls $1/kind | grep v)"

check_if_supported_os

# TODO: check if the bootstrap cluster already exist.
rm -rf ~/.kube/config

check_if_supported_os

log_info "Installing Docker-ce"
# TODO: install only when not installed
case $OS_ID in
	"rocky" | "centos" | "rhel")
		sudo dnf localinstall $ASSETS_DIR/docker-ce/*.rpm
		;;

	"ubuntu" )
		sudo dpkg -i $ASSETS_DIR/docker-ce/*.deb
		;;
esac
sudo systemctl start docker
sudo docker load -i $ASSETS_DIR/kind-node-image.tar.gz

log_info "Creating bootstrap cluster"

sudo cp $ASSETS_DIR/kubectl /usr/local/bin
sudo chmod +x /usr/local/bin/kubectl
sudo cp $KIND_ASSETS_DIR/kind-linux-amd64 /usr/local/bin
sudo chmod +x /usr/local/bin/kind
sudo cp $1/helm /usr/local/bin

export BOOTSTRAP_CLUSTER_SERVER_IP
envsubst '${BOOTSTRAP_CLUSTER_SERVER_IP}' < ./templates/kind-config.yaml.template >output/kind-config.yaml
kind create cluster --config=output/kind-config.yaml --image kindest/node:$KIND_NODE_IMAGE_TAG

while true
do
	node_status=$(kubectl get no -o=jsonpath='{.items[0].status.conditions[?(@.type == "Ready")].status}')
	if [ $node_status = "True" ]
	then
		break
	fi
	
	sleep 10
done

log_info "Bootstrap cluster created successfully. You can access bootstrap cluster using ~/.kube/config as a kubeconfig file"
