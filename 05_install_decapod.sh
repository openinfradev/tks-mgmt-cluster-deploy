#!/bin/bash

set -e

source common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

ASSET_DIR=$1
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

chmod +x $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64
sudo cp $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64 /usr/local/bin/argo

export KUBECONFIG=kubeconfig_$CLUSTER_NAME

print_msg "Installing Decapod-bootstrap..."

kubectl create ns argo
kubectl create ns decapod-db

helm install argo-cd $ASSET_DIR/argo-cd-helm/argo-cd -f $ASSET_DIR/decapod-bootstrap/argocd-install/values-override.yaml -n argo

for ns in decapod-db argo; do
	for po in $(kubectl get po -n $ns -o jsonpath='{.items[*].metadata.name}');do
		kubectl wait --for=condition=Ready -n $ns --timeout=180s po/$po
	done

done

print_msg "All applications for bootstrap have been installed successfully"

sleep 30

print_msg "Creating workflow templates from decapod-flow..."
kubectl apply -R -f $ASSET_DIR/decapod-flow/templates -n argo
print_msg "... done"

print_msg "Run prepare-argocd workflow..."
ARGOCD_PASSWD=$(kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argo submit --from wftmpl/prepare-argocd -n argo -p argo_server=argo-cd-argocd-server:80 -p argo_password=$ARGOCD_PASSWD
WF_NAME=$(argo list -n argo -o name| grep prepare | head -1)
print_msg "You can check the results with the following commands:"
echo "$ argo --kubeconfig $KUBECONFIG get -n argo $WF_NAME"
