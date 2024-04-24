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

GUM_ASSETS_DIR="$ASSETS_DIR/gum/$(ls $ASSETS_DIR/gum | grep v)"
sudo cp $GUM_ASSETS_DIR/gum /usr/local/bin

log_info "Installing container engine"
case $OS_ID in
	"rocky" | "centos" | "rhel")
		sudo dnf install -y podman
		;;

	"ubuntu" )
		sudo apt-get -y install podman
		;;
esac

for img in $(ls $ASSETS_DIR/images); do
	sudo podman load -i $ASSETS_DIR/images/$img
done


sudo cp $ASSETS_DIR/kubectl /usr/local/bin
sudo chmod +x /usr/local/bin/kubectl
sudo cp $KIND_ASSETS_DIR/kind-linux-amd64 /usr/local/bin/kind
sudo chmod +x /usr/local/bin/kind
sudo cp $1/helm /usr/local/bin

log_info "Running local container registry"
reg_name='registry'
reg_port='5000'
if [ "$(sudo podman inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
  sudo podman run \
    -d --restart=always -p "0.0.0.0:${reg_port}:5000" --privileged --name "${reg_name}" \
    --net podman -v $(realpath $ASSETS_DIR)/registry:/var/lib/registry \
    localhost:5000/registry:2
fi
cat <<EOF | sudo tee /etc/containers/registries.conf.d/localregistry.conf
[[registry]]
location = "${BOOTSTRAP_CLUSTER_SERVER_IP}:5000"
insecure = true
EOF

log_info "Running nginx for downloading byoh scripts"
sudo dnf install nginx -y
sudo systemctl enable --now nginx
nginx -v
# /usr/share/nginx/html

log_info "Creating bootstrap cluster"
export BOOTSTRAP_CLUSTER_SERVER_IP
envsubst '${BOOTSTRAP_CLUSTER_SERVER_IP}' < ./templates/kind-config.yaml.template >output/kind-config.yaml
sudo /usr/local/bin/kind create cluster --config=output/kind-config.yaml --image ${BOOTSTRAP_CLUSTER_SERVER_IP}:5000/kind-node:${KIND_NODE_IMAGE_TAG%%@*}
mkdir -p ~/.kube
sudo cp /root/.kube/config ~/.kube
sudo chown $USER:$USER ~/.kube/config
sed -i "s/:6443/$BOOTSTRAP_CLUSTER_SERVER_IP:6443/g" ~/.kube/config

while true
do
	node_status=$(kubectl get no -o=jsonpath='{.items[0].status.conditions[?(@.type == "Ready")].status}')
	if [ $node_status = "True" ]
	then
		break
	fi
	
	sleep 10
done

# Add the registry config to the nodes
REGISTRY_DIR="/etc/containerd/certs.d/${BOOTSTRAP_CLUSTER_SERVER_IP}:5000"
for node in $(sudo /usr/local/bin/kind get nodes); do
          sudo podman exec "${node}" mkdir -p "${REGISTRY_DIR}"
            cat <<EOF | sudo podman exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${BOOTSTRAP_CLUSTER_SERVER_IP}:5000"]
EOF
done

# Document the local registry
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | /usr/local/bin/kubectl --kubeconfig /home/rocky/.kube/config apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "${BOOTSTRAP_CLUSTER_SERVER_IP}:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

log_info "Bootstrap cluster created successfully. You can access bootstrap cluster using ~/.kube/config as a kubeconfig file"
