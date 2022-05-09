#!/bin/bash

set -e

source common.sh

if [ -z "$2" ]; then
  echo "usage: $0 <assets dir> <admin cluster kubeconfig>"
  exit 1
fi

ASSET_DIR=$1
ADMIN_KUBECONFIG=$2

export KUBECONFIG=$ADMIN_KUBECONFIG
CLUSTER_NAME=$(kubectl get cl -o=jsonpath='{.items[0].metadata.name}')

NUM_CLUSTERS=$(kubectl get cl -A -ojsonpath={.items[*].metadata.name} | wc -w)
if [ $NUM_CLUSTERS -ne 1 ]; then
        print_msg "ERROR: There are $NUM_CLUSTERS clusters.\n=== Only one management cluster should remain."
        exit 1
fi

chmod +x $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64
sudo cp $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64 /usr/local/bin/argo

read -r -p "Are you sure you want to delete the \"$CLUSTER_NAME\" admin cluster? [y/N] " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        print_msg "All TKS service apps in admin cluster are being deleted"
else
        print_msg "Aborts cleanup operations"
        exit 1
fi

argo submit --from wftmpl/remove-servicemesh-all -p cluster_id=$CLUSTER_NAME -p app_prefix=admin -n argo
argo watch -n argo @latest
argo submit --from wftmpl/remove-lma-federation -p cluster_id=$CLUSTER_NAME -p app_prefix=admin -n argo
argo watch -n argo @latest
argo submit --from wftmpl/remove-admin-tools -p app_prefix=tks-admin -n argo
argo watch -n argo @latest

helm uninstall -n ingress-nginx ingress-nginx
helm uninstall -n argo argo-cd

kubectl delete deploy -n argo argo-workflows-operator-server argo-workflows-operator-workflow-controller
kubectl delete sts -n decapod-db postgresql-postgresql
kubectl delete pvc -n decapod-db data-postgresql-postgresql-0

print_msg  "Pre-check before pivot"
clusterctl move --to-kubeconfig ~/.kube/config --dry-run -v10
print_msg "... done"

# Fix for 'MP_NAME is invalid: spec.awsLaunchTemplate.rootVolume.deviceName: Forbidden: root volume shouldn't have device name'
for awsmp_name in $(kubectl get mp -ojsonpath={.items[*].metadata.name}); do
        kubectl patch awsmp $awsmp_name --type json -p='[{"op": "remove", "path": "/spec/awsLaunchTemplate/rootVolume/deviceName"}]'
done

print_msg "Pivoting to delete TKS admin cluster"
clusterctl move --to-kubeconfig ~/.kube/config
print_msg "... done"

export KUBECONFIG=~/.kube/config
kubectl get cl $CLUSTER_NAME
if [ $? -ne 0 ]; then
        print_msg "ERROR: There is not $CLUSTER_NAME cluster"
        exit 1
fi

print_msg "Deleting $CLUSTER_NAME admin cluster"
kubectl delete cl $CLUSTER_NAME
print_msg "... done"
