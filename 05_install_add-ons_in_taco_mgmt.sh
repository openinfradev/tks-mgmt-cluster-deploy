#!/bin/bash

set -e

source common.sh

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]
  then
    echo "usage: $0 <assets dir> <clouds.yaml> <os_cloud_name> <values.yaml for mgmt cluster>"
    echo "See the example-clouds.yaml and example-values_mgmt_cluster.yaml."
    exit 1
fi

CLUSTER_NAME=$(yq eval  .cluster_name $4)

print_msg "Verifing TACO management cluster is ready"

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

  WORKER_REPLICAS_DESIRED=$(kubectl get md -o=jsonpath='{.items[?(@.metadata.name == "'$CLUSTER_NAME-md-0'")].status.replicas}')
  [ $(kubectl get machine | grep $CLUSTER_NAME | grep md-0 | grep Running | wc -l) -ne $WORKER_REPLICAS_DESIRED ] && continue

  break
done
kill -9 $SPIN_PID >/dev/null 2>&1

echo "Done\n"
print_msg "TACO management cluster is ready for installing addons!"

clusterctl get kubeconfig $CLUSTER_NAME > kubeconfig_$CLUSTER_NAME

print_msg  "Installing calico CNI"
kubectl --kubeconfig=kubeconfig_$CLUSTER_NAME apply -f $1/calico.yaml
sleep 120
echo "-----"
kubectl --kubeconfig=kubeconfig_$CLUSTER_NAME get no
print_msg  "Make sure all node status are ready"

