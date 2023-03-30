#!/bin/bash

set -e

source lib/common.sh

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		if [ -z "$1" ] || [ -z "$2" ]
		then
			echo "usage: $0 <ssh_key.pem> <values.yaml for admin cluster>"
			exit 1
		fi
		SSH_KEY=$1
		HELM_VALUE_FILE=$2
		;;
	"byoh")
		;;
esac

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		log_info "Copying all local resources to the bastion host"
		if grep -Fq "eksEnabled: true" $HELM_VALUE_FILE;then
			BASTION_HOST_IP=$(kubectl get awsmanagedcontrolplanes $CLUSTER_NAME -o jsonpath='{.status.bastion.addresses[?(@.type == "ExternalIP")].address}')
		else
			BASTION_HOST_IP=$(kubectl get awscluster $CLUSTER_NAME -o jsonpath='{.status.bastion.addresses[?(@.type == "ExternalIP")].address}')
		fi
		ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$BASTION_HOST_IP sudo rm -rf "${PWD##*/}"
		scp -r -q -i $SSH_KEY -o StrictHostKeyChecking=no $PWD ubuntu@$BASTION_HOST_IP:
		;;
	"byoh")
		;;
esac

export KUBECONFIG=~/.kube/config

log_info  "Pre-check before pivot"
clusterctl move --to-kubeconfig output/kubeconfig_$CLUSTER_NAME --dry-run -v10

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		grep -Fq "eksEnabled: true" $HELM_VALUE_FILE
		eks_enabled=$?
		if test $eks_enabled -neq 0; then
			# Fix for 'MP_NAME is invalid: spec.awsLaunchTemplate.rootVolume.deviceName: Forbidden: root volume shouldn't have device name'
			for awsmp_name in $(kubectl get mp -ojsonpath={.items[*].metadata.name}); do
				kubectl patch awsmp $awsmp_name --type json -p='[{"op": "remove", "path": "/spec/awsLaunchTemplate/rootVolume/deviceName"}]'
			done
		fi
		;;
	"byoh")
		;;
esac

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		gum confirm "Are you sure you want to move the Cluster API objects to the admin cluster?" || exit 1
		log_info "Pivoting to make TKS admin cluster self-managing"
		clusterctl move --to-kubeconfig output/kubeconfig_$CLUSTER_NAME
		log_info "Finished. Check the status of all cluster API resources in the admin cluster and use the bastion host: $BASTION_HOST_IP"
		;;
	"byoh")

		# TODO: XXX: pivoting on BYOH does not works
		kubectl patch cluster tks-admin --type='json' -p='[{ "op": "add", "path": "/spec/paused", "value": true }]'
		log_info "BYOH infra provider does not support pivot."
		;;
esac
