#!/bin/bash

set -e

source lib/common.sh

if [ -z "$2" ]; then
  echo "usage: $0 <assets dir> <admin cluster kubeconfig>"
  exit 1
fi

ASSET_DIR=$1
ADMIN_KUBECONFIG=$2
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export KUBECONFIG=$ADMIN_KUBECONFIG
CLUSTER_NAME=$(kubectl get cl -o=jsonpath='{.items[0].metadata.name}')

NUM_CLUSTERS=$(kubectl get cl -A -ojsonpath={.items[*].metadata.name} | wc -w)
if [ $NUM_CLUSTERS -ne 1 ]; then
        log_info "ERROR: There are $NUM_CLUSTERS clusters.\n=== Only one management cluster should remain."
        exit 1
fi

read -r -p "Are you sure you want to delete the \"$CLUSTER_NAME\" admin cluster? [y/N] " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log_info "All TKS service apps in admin cluster are being deleted"
else
        log_info "Aborts cleanup operations"
        exit 1
fi

log_info  "Pre-check before pivot"
clusterctl move --to-kubeconfig ~/.kube/config --dry-run -v10
log_info "... done"

for provider in ${CAPI_INFRA_PROVIDERS[@]}
do
	case $provider in
		"aws")
			if grep -Fq "aws-iam-authenticator" $SCRIPT_DIR/$ADMIN_KUBECONFIG;then
				# do nothing
				:
			else
				# Fix for 'MP_NAME is invalid: spec.awsLaunchTemplate.rootVolume.deviceName: Forbidden: root volume shouldn't have device name'
				for awsmp_name in $(kubectl get mp -ojsonpath={.items[*].metadata.name}); do
					kubectl patch awsmp $awsmp_name --type json -p='[{"op": "remove", "path": "/spec/awsLaunchTemplate/rootVolume/deviceName"}]'
				done
			fi
			;;
		"byoh")
			;;
	esac
done

log_info "Pivoting to delete TKS admin cluster"
clusterctl move --to-kubeconfig ~/.kube/config
log_info "... done"

export KUBECONFIG=~/.kube/config
kubectl get cl $CLUSTER_NAME
if [ $? -ne 0 ]; then
        log_info "ERROR: There is not $CLUSTER_NAME cluster"
        exit 1
fi

log_info "Deleting $CLUSTER_NAME admin cluster"
kubectl delete cl $CLUSTER_NAME
log_info "... done"
