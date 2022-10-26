#!/bin/bash

set -e

source lib/common.sh

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

export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

log_info "Installing Decapod-bootstrap..."

kubectl create ns argo || true
kubectl create ns decapod-db || true

helm upgrade -i argo-cd $ASSET_DIR/argo-cd-helm/argo-cd -f $ASSET_DIR/decapod-bootstrap/argocd-install/values-override.yaml -n argo

sleep 10
gum spin --spinner dot --title "Wait for argo CD ready..." -- util/wait_for_all_pods_in_ns.sh argo

sleep 60
for ns in argo decapod-db ; do
	gum spin --spinner dot --title "Wait for all pods ready in $ns namespace..." -- util/wait_for_all_pods_in_ns.sh $ns
done
log_info "All applications for bootstrap have been installed successfully"

log_info "Creating workflow templates from decapod and tks-flow..."
kubectl apply -R -f $ASSET_DIR/decapod-flow/templates -n argo
for dir in $(ls -l $ASSET_DIR/tks-flow/ |grep "^d" | grep -v dockerfiles |awk '{print $9}'); do
	kubectl apply -R -f $ASSET_DIR/tks-flow/$dir -n argo
done

log_info "Creating configmap from tks-proto..."
kubectl create cm tks-proto -n argo --from-file=$ASSET_DIR/tks-proto/tks_pb_python -o yaml --dry-run=client | kubectl apply -f -
log_info "... done"

log_info "Creating aws secret..."
if [[ " ${CAPI_INFRA_PROVIDERS[*]} " =~ " aws " ]]; then
	argo submit --from wftmpl/tks-create-aws-conf-secret -n argo -p aws_access_key_id=$AWS_ACCESS_KEY_ID -p aws_secret_access_key=$AWS_SECRET_ACCESS_KEY --watch 
fi

log_info "Run prepare-argocd workflow..."
ARGOCD_PASSWD=$(kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argo submit --from wftmpl/prepare-argocd -n argo -p argo_server=argo-cd-argocd-server.argo.svc:80 -p argo_password=$ARGOCD_PASSWD --watch

log_info "Run tks-create-github-token-secret workflow..."
argo submit --from wftmpl/tks-create-github-token-secret -n argo -p user=$GITHUB_USERNAME -p token=$GITHUB_TOKEN --watch

log_info "Add tks-admin cluster to argocd..."
ARGOCD_SERVER=$(kubectl get node | grep -v NAME | head -n 1 | cut -d' ' -f1)
ARGOCD_PORT=$(kubectl get svc -n argo argo-cd-argocd-server -o=jsonpath='{.spec.ports[0].nodePort}')
CURRENT_CONTEXT=$(kubectl config current-context)
argocd login --plaintext $ARGOCD_SERVER:$ARGOCD_PORT --username admin --password $ARGOCD_PASSWD
argocd cluster add $CURRENT_CONTEXT --name tks-admin -y

log_info "...Done"
