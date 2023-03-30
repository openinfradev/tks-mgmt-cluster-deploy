#!/bin/sh

# dirty script for clean up decapod things...

set -x

source lib/common.sh

if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

ASSET_DIR=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
export KUBECONFIG=$SCRIPT_DIR/output/kubeconfig_$CLUSTER_NAME

DECAPOD_BOOTSTRAP_COMMIT="3879b95a66176a06b7bd9b53cdc1a2075b988b1d"

delete_argo() {
        ARGOCD_SERVER=$(kubectl get no -ojsonpath='{.items[0].status.addresses[?(@.type == "InternalIP")].address}')
        ARGOCD_PORT=30080
        ARGOCD_PASSWD=$(kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        argocd login --plaintext $ARGOCD_SERVER:$ARGOCD_PORT --username admin --password $ARGOCD_PASSWD

        for app in argo-workflows argo-workflows-crds db-secret-argo  decapod-apps decapod-projects; do
                argocd app set $app  --sync-policy none
        done
        argocd app delete argo-workflows argo-workflows-crds db-secret-argo  decapod-apps decapod-projects -y

        sleep 60
        argocd app list
        read -p "===== Press enter key ========"

        helm uninstall -n argo argo-cd-apps
        helm uninstall -n argo argo-cd
}

delete_argo

helm uninstall -n gitea gitea
helm uninstall -n tks-db  postgresql
kubectl delete pvc -n gitea       data-gitea-0
kubectl delete pvc -n tks-db      data-postgresql-0

kubectl delete -R -f $ASSET_DIR/decapod-manifests/decapod-reference/decapod-controller/argo-workflows-operator-crds/
cd $ASSET_DIR/decapod-bootstrap/
git reset --hard $DECAPOD_BOOTSTRAP_COMMIT
git remote rm gitea
cd -
