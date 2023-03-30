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
IS_MANAGED_CLUSTER="false"

export KUBECONFIG=~/.kube/config

log_info "Creating TKS Admin Cluster via Cluster API"

create_capa_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-aws
	helm upgrade -i tks-admin $CHART_DIR -f $HELM_VALUE_FILE

	if grep -Fq "eksEnabled: true" $HELM_VALUE_FILE;then
		KUBECONFIG_SECRET_NAME=$CLUSTER_NAME-user-kubeconfig
		IS_MANAGED_CLUSTER="true"

		EKSCTL_ASSET_DIR="$ASSET_DIR/eksctl/$(ls $ASSET_DIR/eksctl | grep v)"
		AWS_IAM_AUTHENTICATOR_ASSET_DIR="$ASSET_DIR/aws-iam-authenticator/$(ls $ASSET_DIR/aws-iam-authenticator | grep v)"
		sudo tar xfz $EKSCTL_ASSET_DIR/eksctl_linux_amd64.tar.gz -C /usr/local/bin/
		sudo cp $AWS_IAM_AUTHENTICATOR_ASSET_DIR/aws-iam-authenticator* /usr/local/bin/aws-iam-authenticator
		sudo chmod +x /usr/local/bin/aws-iam-authenticator
	else
		KUBECONFIG_SECRET_NAME=$CLUSTER_NAME-kubeconfig
	fi
}

create_byoh_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-byoh
	helm upgrade -i tks-admin $CHART_DIR -f $HELM_VALUE_FILE

	KUBECONFIG_SECRET_NAME=$CLUSTER_NAME-kubeconfig
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

gum spin --spinner dot --title "Verifing TKS Admin cluster is ready..." -- util/wait_for_cluster_ready.sh $CLUSTER_NAME $IS_MANAGED_CLUSTER

log_info  "Installing kubernetes addons for network and storage"
case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		if grep -Fq "eksEnabled: true" $HELM_VALUE_FILE;then
			kubectl get secret $CLUSTER_NAME-user-kubeconfig -o jsonpath={.data.value} | base64 --decode > output/kubeconfig_$CLUSTER_NAME
			chmod 600 output/kubeconfig_$CLUSTER_NAME
			export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

			cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: taco-storage
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
EOF

		else
			clusterctl get kubeconfig $CLUSTER_NAME > output/kubeconfig_$CLUSTER_NAME
			chmod 600 output/kubeconfig_$CLUSTER_NAME
			helm upgrade -i k8s-addons $ASSET_DIR/taco-helm/kubernetes-addons $HELM_VALUE_K8S_ADDONS
			helm upgrade -i aws-ebs-csi-driver --namespace kube-system $ASSET_DIR/aws-ebs-csi-driver-helm/aws-ebs-csi-driver
		fi
		;;

	"byoh")
		clusterctl get kubeconfig $CLUSTER_NAME > output/kubeconfig_$CLUSTER_NAME
		chmod 600 output/kubeconfig_$CLUSTER_NAME
		export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME
		kubectl apply -f $ASSET_DIR/calico/calico.yaml
		helm upgrade -i local-path-provisioner --namespace kube-system --set storageClass.name=taco-storage $ASSET_DIR/local-path-provisioner/deploy/chart/local-path-provisioner
		;;
esac

log_info "Waiting for all nodes ready"
for node in $(kubectl get no -o jsonpath='{.items[*].metadata.name}');do
	kubectl wait --for=condition=Ready no/$node
done
echo "-----"
kubectl get no
log_info  "Make sure all node status are ready"

export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME
log_info "Initializing cluster API provider components in TKS admin cluster"
case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		export AWS_REGION
		export AWS_ACCESS_KEY_ID
		export AWS_SECRET_ACCESS_KEY

		export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
		export EXP_MACHINE_POOL=true
		export CAPA_EKS_IAM=true
		export CAPA_EKS_ADD_ROLES=true

		CAPI_PROVIDER_NS=capa-system
		;;
	"byoh")
		CAPI_PROVIDER_NS=byoh-system
		;;
esac

gum spin --spinner dot --title "Waiting for providers to be installed..." -- clusterctl init --infrastructure $(printf -v joined '%s,' "${CAPI_INFRA_PROVIDERS[@]}"; echo "${joined%,}") --wait-providers
