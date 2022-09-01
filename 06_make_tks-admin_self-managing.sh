#!/bin/bash

set -e

source lib/common.sh

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		if [ -z "$1" ]
		then
			echo "usage: $0 <ssh_key.pem>"
			exit 1
		fi
		SSH_KEY=$1
		;;
	"byoh")
		;;
esac

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		log_info "Copying all local resources to the bastion host"
		BASTION_HOST_IP=$(kubectl get awscluster $CLUSTER_NAME -o jsonpath='{.status.bastion.addresses[?(@.type == "ExternalIP")].address}')
		ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$BASTION_HOST_IP sudo rm -rf "${PWD##*/}"
		scp -r -q -i $SSH_KEY -o StrictHostKeyChecking=no $PWD ubuntu@$BASTION_HOST_IP:
		;;
	"byoh")
		;;
esac

export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME
log_info "Initializing cluster API provider components in TKS admin cluster"
case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		export AWS_REGION
		export AWS_ACCESS_KEY_ID
		export AWS_SECRET_ACCESS_KEY

		export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
		export EXP_MACHINE_POOL=true

		CAPI_PROVIDER_NS=capa-system
		;;
	"byoh")
		CAPI_PROVIDER_NS=byoh-system
		;;
esac

gum spin --spinner dot --title "Waiting for providers to be installed..." -- clusterctl init --infrastructure $(printf -v joined '%s,' "${CAPI_INFRA_PROVIDERS[@]}"; echo "${joined%,}") --wait-providers

export KUBECONFIG=~/.kube/config

log_info "Copying TKS admin cluster kubeconfig secret to argo namespace"
kubectl get secret $CLUSTER_NAME-kubeconfig -ojsonpath={.data.value} | base64 -d > value
kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME create secret generic tks-admin-kubeconfig-secret -n argo --from-file=value
rm value

log_info  "Pre-check before pivot"
clusterctl move --to-kubeconfig output/kubeconfig_$CLUSTER_NAME --dry-run -v10

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		# Fix for 'MP_NAME is invalid: spec.awsLaunchTemplate.rootVolume.deviceName: Forbidden: root volume shouldn't have device name'
		for awsmp_name in $(kubectl get mp -ojsonpath={.items[*].metadata.name}); do
			kubectl patch awsmp $awsmp_name --type json -p='[{"op": "remove", "path": "/spec/awsLaunchTemplate/rootVolume/deviceName"}]'
		done
		;;
	"byoh")
		;;
esac

log_info "Pivoting to make TKS admin cluster self-managing"
clusterctl move --to-kubeconfig output/kubeconfig_$CLUSTER_NAME

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		log_info "Finished. Check the status of all cluster API resources in the admin cluster and use the bastion host: $BASTION_HOST_IP"
		;;
	"byoh")

		# TODO
		# create byoh in admin cluster
		kubectl get byoh -o yaml | KUBECONFIG=output/kubeconfig_$CLUSTER_NAME kubectl apply -f - 
		#kubectl apply -f byohs_in_bootstrap.yaml
		# restart agents in the hosts
		log_info "Finished."
		;;
esac
