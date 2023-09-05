#!/bin/bash

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
	echo "usage: $0 <cluster name dir> <is managed cluster?>"
	exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/../conf.sh

CLUSTER_NAME=$1
IS_MANAGED_CLUSTER=$2
export KUBECONFIG=~/.kube/config

echo "check control plane..."

while true
do
	sleep 10

	[ $(kubectl get cluster -o=jsonpath='{.items[?(@.metadata.name == "'$CLUSTER_NAME'")].status.phase}') != "Provisioned" ] && continue
	case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
		"aws")
			if $IS_MANAGED_CLUSTER = "true"; then
				kubectl wait --for=condition=Ready awsmcp/$CLUSTER_NAME || continue
			else
				CONTROL_PLANE_REPLICAS_DESIRED=$(kubectl get kcp -o=jsonpath='{.items[?(@.metadata.name == "'$CLUSTER_NAME-control-plane'")].status.replicas}')
				[ $(kubectl get machine | grep $CLUSTER_NAME | grep control-plane | grep Running | wc -l) -ne $CONTROL_PLANE_REPLICAS_DESIRED ] && continue
			fi
			;;
		"byoh")
			kubectl wait --for=condition=Available kcp/$CLUSTER_NAME || continue
			;;
	esac

	break
done

echo "control plane is ready"

while true
do
	sleep 10

	case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
		"aws")
			if $IS_MANAGED_CLUSTER = "true"; then
				AWSMPKIND="awsmanagedmachinepools"
			else
				AWSMPKIND="awsmachinepools"
			fi
			MP_LIST="$(kubectl get mp -ojsonpath='{.items[*].metadata.name}')"
			for mp in $MP_LIST
			do
				kubectl wait --for=condition=Ready $AWSMPKIND/$mp || continue 2
			done
			;;

		"byoh")
			MD_LIST="$(kubectl get md -ojsonpath='{.items[*].metadata.name}')"
			for md in $MD_LIST
			do
				WORKER_REPLICAS_DESIRED=$(kubectl get md -o=jsonpath='{.items[?(@.metadata.name == "'$md'")].status.replicas}')
				[ $(kubectl get machine | grep $md | grep Running | wc -l) -ne $WORKER_REPLICAS_DESIRED ] && continue 2
			done
			;;
	esac

	break
done
