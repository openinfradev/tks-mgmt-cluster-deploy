#!/bin/bash

set -e

source common.sh

if [ -z "$1" ]
then
	echo "usage: $0 <ssh_key.pem>"
	exit 1
fi

SSH_KEY=$1

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

print_msg "Copying all local resources to the bastion host"
BASTION_HOST_IP=$(kubectl get awscluster $CLUSTER_NAME -o jsonpath='{.status.bastion.addresses[?(@.type == "ExternalIP")].address}')
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$BASTION_HOST_IP sudo rm -rf "${PWD##*/}"
scp -r -q -i $SSH_KEY -o StrictHostKeyChecking=no $PWD ubuntu@$BASTION_HOST_IP:
print_msg "... done"

export KUBECONFIG=kubeconfig_$CLUSTER_NAME
print_msg "Initializing cluster API provider components in TKS admin cluster"
case $CAPI_INFRA_PROVIDER in
	"aws")
		export AWS_REGION
		export AWS_ACCESS_KEY_ID
		export AWS_SECRET_ACCESS_KEY

		export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
		export EXP_MACHINE_POOL=true
		;;
	"openstack")
		;;
esac

clusterctl init --infrastructure $CAPI_INFRA_PROVIDER

for ns in cert-manager capi-webhook-system capi-system capi-kubeadm-bootstrap-system capi-kubeadm-control-plane-system $CAPI_PROVIDER_NS; do
	for po in $(kubectl get po -n $ns -o jsonpath='{.items[*].metadata.name}');do
		kubectl wait --for=condition=Ready --timeout 180s -n $ns po/$po
	done
done
print_msg "... done"

print_msg "Copying TKS admin cluster kubeconfig secret to argo namespace"
kubectl get secret $CLUSTER_NAME-kubeconfig -ojsonpath={.data.value} | base64 -d > value
kubectl create secret generic tks-admin-kubeconfig-secret -n argo --from-file=value
rm value
print_msg "... done"

export KUBECONFIG=~/.kube/config

print_msg  "Pre-check before pivot"
clusterctl move --to-kubeconfig kubeconfig_$CLUSTER_NAME --dry-run -v10
print_msg "... done"

# Fix for 'MP_NAME is invalid: spec.awsLaunchTemplate.rootVolume.deviceName: Forbidden: root volume shouldn't have device name'
for awsmp_name in $(kubectl get mp -ojsonpath={.items[*].metadata.name}); do
	kubectl patch awsmp $awsmp_name --type json -p='[{"op": "remove", "path": "/spec/awsLaunchTemplate/rootVolume/deviceName"}]'
done

print_msg "Pivoting to make TKS admin cluster self-managing"
clusterctl move --to-kubeconfig kubeconfig_$CLUSTER_NAME

print_msg "Finished. Check the status of all cluster API resources in the admin cluster and use the bastion host: $BASTION_HOST_IP"
