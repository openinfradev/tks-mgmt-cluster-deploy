#!/bin/bash

set -e

source  common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

if [[ $(cat /etc/os-release  | awk -F= '/^ID=/{print $2}') != "ubuntu" ]]
then
  echo "Only Ubuntu distributions are supported."
  exit 1
fi

ASSETS_DIR="$1/k3s/$(ls $1/k3s | grep v)"

print_msg "Creating bootstrap cluster"

sudo mkdir -p /var/lib/rancher/k3s/agent/images/
sudo cp $ASSETS_DIR/k3s-airgap-images-amd64.tar /var/lib/rancher/k3s/agent/images/
sudo cp $ASSETS_DIR/k3s /usr/local/bin
sudo chmod +x /usr/local/bin/k3s
sudo cp $1/helm /usr/local/bin

chmod +x $ASSETS_DIR/install.sh
INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_EXEC="server --cluster-domain taco_tmp" $ASSETS_DIR/install.sh

sleep 60
while true
do
	node_count=$(sudo kubectl get no --kubeconfig /etc/rancher/k3s/k3s.yaml | grep master | wc -l)
	if [ $node_count -eq 1 ]
	then
		break
	fi
	
	sleep 10
done

while true
do
	node_status=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get no -o=jsonpath='{.items[0].status.conditions[?(@.type == "Ready")].status}')
	if [ $node_status = "True" ]
	then
		break
	fi
	
	sleep 10
done

[ -d ~/.kube ] || mkdir ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config

print_msg "Bootstrap cluster created successfully. You can access bootstrap cluster using ~/.kube/config as a kubeconfig file"
