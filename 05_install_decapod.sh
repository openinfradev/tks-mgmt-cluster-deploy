#!/bin/bash

set -e

source common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

ASSET_DIR=$1
export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

chmod +x $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64
sudo cp $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64 /usr/local/bin/argo

export KUBECONFIG=kubeconfig_$CLUSTER_NAME

print_msg "Installing Decapod-bootstrap..."

kubectl create ns argo || true
kubectl create ns decapod-db || true

helm upgrade -i argo-cd $ASSET_DIR/argo-cd-helm/argo-cd -f $ASSET_DIR/decapod-bootstrap/argocd-install/values-override.yaml -n argo

for ns in decapod-db argo; do
	for po in $(kubectl get po -n $ns -o jsonpath='{.items[*].metadata.name}');do
		kubectl wait --for=condition=Ready -n $ns --timeout=180s po/$po
	done

done

print_msg "All applications for bootstrap have been installed successfully"

sleep 30

print_msg "Creating workflow templates from decapod and tks-flow..."
kubectl apply -R -f $ASSET_DIR/decapod-flow/templates -n argo
for dir in $(ls -l $ASSET_DIR/tks-flow/ |grep "^d"|awk '{print $9}'); do
	kubectl apply -R -f $ASSET_DIR/tks-flow/$dir -n argo
done
print_msg "... done"

print_msg "Creating configmap from tks-proto..."
kubectl create cm tks-proto -n argo --from-file=$ASSET_DIR/tks-proto/tks_pb_python -o yaml --dry-run=client | kubectl apply -f -
print_msg "... done"

print_msg "Creating aws secret..."
argo submit --from wftmpl/tks-create-aws-conf-secret -n argo -p aws_access_key_id=$AWS_ACCESS_KEY_ID -p aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
argo watch -n argo @latest
print_msg "... done"

print_msg "Run prepare-argocd workflow..."
ARGOCD_PASSWD=$(kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argo submit --from wftmpl/prepare-argocd -n argo -p argo_server=argo-cd-argocd-server.argo.svc:80 -p argo_password=$ARGOCD_PASSWD
argo watch -n argo @latest
print_msg "... done"

print_msg "Run tks-create-github-token-secret workflow..."
argo submit --from wftmpl/tks-create-github-token-secret -n argo -p user=$GITHUB_USERNAME -p token=$GITHUB_TOKEN
argo watch -n argo @latest
print_msg "... done"

