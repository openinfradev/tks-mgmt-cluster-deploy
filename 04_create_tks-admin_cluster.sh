#!/bin/bash

set -e

source lib/common.sh

if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "usage: $0 <assets dir> <values.yaml for admin cluster>"
    echo "See the example-values_admin_cluster.yaml."
    exit 1
fi

ASSET_DIR=$1
HELM_VALUE_FILE=$2
HELM_VALUE_K8S_ADDONS="--set cni.calico.enabled=true"

export KUBECONFIG=~/.kube/config

log_info "Creating TKS Admin Cluster via Cluster API"

create_capa_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-aws
	helm upgrade -i tks-admin $CHART_DIR -f $HELM_VALUE_FILE
}

create_byoh_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-byoh
	helm upgrade -i tks-admin $CHART_DIR -f $HELM_VALUE_FILE
}

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
        "aws")
                create_capa_cluster
                ;;

        "byoh")
		create_byoh_cluster
                ;;
esac

CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
log_info "TKS Admin cluster chart successfully installed"

gum spin --spinner dot --title "Verifing TKS Admin cluster is ready..." -- util/wait_for_cluster_ready.sh $CLUSTER_NAME
log_info "TKS Admin cluster is ready for installing addons!"

clusterctl get kubeconfig $CLUSTER_NAME > output/kubeconfig_$CLUSTER_NAME
chmod 600 output/kubeconfig_$CLUSTER_NAME
export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

log_info  "Installing kubernetes addons for network and stroage"
helm upgrade -i k8s-addons $ASSET_DIR/taco-helm/kubernetes-addons $HELM_VALUE_K8S_ADDONS
case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		helm upgrade -i aws-ebs-csi-driver --namespace kube-system $ASSET_DIR/aws-ebs-csi-driver/aws-ebs-csi-driver
		;;

	"byoh")
		helm upgrade -i local-path-provisioner --namespace kube-system --set storageClass.name=taco-storage $ASSET_DIR/helm-repo/local-path-provisioner-0.0.22.tgz
		;;
esac

log_info "Waiting for all nodes ready"
for node in $(kubectl get no -o jsonpath='{.items[*].metadata.name}');do
	kubectl wait --for=condition=Ready no/$node
done

echo "-----"
kubectl get no
log_info  "Make sure all node status are ready"
