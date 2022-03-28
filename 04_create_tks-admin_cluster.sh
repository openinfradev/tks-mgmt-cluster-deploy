#!/bin/bash

set -e

source common.sh

if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "usage: $0 <assets dir> <values.yaml for admin cluster>"
    echo "See the example-values_admin_cluster.yaml."
    exit 1
fi

ASSET_DIR=$1
HELM_VALUE_FILE=$2
HELM_VALUE_K8S_ADDONS="--set cni.calico.enabled=true"

print_msg "Creating TKS Admin Cluster via Cluster API"

create_capa_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-aws
	helm install tks-admin $CHART_DIR -f $HELM_VALUE_FILE

	CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
}

create_capo_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-openstack
	helm install tks-admin $CHART_DIR -f $HELM_VALUE_FILE
}

case $CAPI_INFRA_PROVIDER in
        "aws")
                create_capa_cluster
                ;;

        "openstack")
		create_capo_cluster
                ;;
esac

print_msg "TKS Admin cluster chart successfully installed"

print_msg "Verifing TKS Admin cluster is ready"

echo -n "Checking... "
# https://www.shellscript.sh/tips/spinner/
spin()
{
  spinner="/|\\-/|\\-"
  while :
  do
    for i in `seq 0 7`
    do
      echo -n "${spinner:$i:1}"
      echo -en "\010"
      sleep 1
    done
  done
}
spin &
SPIN_PID=$!
trap "kill -9 $SPIN_PID  >/dev/null 2>&1" `seq 0 15`

while true
do
  sleep 30

  [ $(kubectl get cluster -o=jsonpath='{.items[?(@.metadata.name == "'$CLUSTER_NAME'")].status.phase}') != "Provisioned" ] && continue

  CONTROL_PLANE_REPLICAS_DESIRED=$(kubectl get kcp -o=jsonpath='{.items[?(@.metadata.name == "'$CLUSTER_NAME-control-plane'")].status.replicas}')
  [ $(kubectl get machine | grep $CLUSTER_NAME | grep control-plane | grep Running | wc -l) -ne $CONTROL_PLANE_REPLICAS_DESIRED ] && continue

  case $CAPI_INFRA_PROVIDER in
	  "aws")
		  MP_NAME=$(kubectl get mp -ojsonpath={.items[0].metadata.name})
		  kubectl wait --for=condition=Ready awsmachinepool/$MP_NAME || continue
		  ;;

	  "openstack")
		  WORKER_REPLICAS_DESIRED=$(kubectl get md -o=jsonpath='{.items[?(@.metadata.name == "'$CLUSTER_NAME-md-0'")].status.replicas}')
		  [ $(kubectl get machine | grep $CLUSTER_NAME | grep md-0 | grep Running | wc -l) -ne $WORKER_REPLICAS_DESIRED ] && continue
		  ;;
  esac

  break
done
kill -9 $SPIN_PID >/dev/null 2>&1

echo "Done\n"
print_msg "TKS Admin cluster is ready for installing addons!"

clusterctl get kubeconfig $CLUSTER_NAME > kubeconfig_$CLUSTER_NAME
chmod 600 kubeconfig_$CLUSTER_NAME

print_msg  "Installing kubernetes addons for network and stroage"
helm install --kubeconfig kubeconfig_$CLUSTER_NAME k8s-addons $ASSET_DIR/taco-helm/kubernetes-addons $HELM_VALUE_K8S_ADDONS
helm install --kubeconfig kubeconfig_$CLUSTER_NAME aws-ebs-csi-driver --namespace kube-system $ASSET_DIR/aws-ebs-csi-driver/aws-ebs-csi-driver

for node in $(kubectl get no --kubeconfig kubeconfig_$CLUSTER_NAME -o jsonpath='{.items[*].metadata.name}');do
	kubectl wait --kubeconfig kubeconfig_$CLUSTER_NAME --for=condition=Ready no/$node
done

echo "-----"
kubectl --kubeconfig=kubeconfig_$CLUSTER_NAME get no
print_msg  "Make sure all node status are ready"
