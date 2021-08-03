#!/bin/bash

set -e

source common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <ssh_key.pem>"
    exit 1
fi

SSH_KEY=$1
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

export KUBECONFIG=kubeconfig_$CLUSTER_NAME

print_msg "Configuring worker nodes for elastisearch..."
for node in $(kubectl get node --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].status.addresses[?(@.type == "InternalIP")].address}'); do
	ssh -i $SSH_KEY -o StrictHostKeyChecking=no $node sudo sed -i '/vm.max_map_count/d' /etc/sysctl.conf
	ssh -i $SSH_KEY -o StrictHostKeyChecking=no $node echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
	ssh -i $SSH_KEY -o StrictHostKeyChecking=no $node sudo sysctl -w vm.max_map_count=262144
done
print_msg "... done"

print_msg "Creating and labeling resources for LMA ..."
kubectl create ns lma 
kubectl label namespace lma name=lma --overwrite

for no in $(kubectl get node --selector='!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}'); do
	kubectl label nodes $no taco-lma=enabled --overwrite
done
print_msg "... done"

print_msg "Creating etcd-client-cert secret..."
MASTER_NODE=$(kubectl get node --selector='node-role.kubernetes.io/master' -o jsonpath='{.items[0].status.addresses[?(@.type == "InternalIP")].address}')
ssh -i $SSH_KEY -o StrictHostKeyChecking=no $MASTER_NODE "rm -rf ~/etcd_pki && mkdir ~/etcd_pki"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no $MASTER_NODE sudo cp /etc/kubernetes/pki/etcd/ca.key ~/etcd_pki
ssh -i $SSH_KEY -o StrictHostKeyChecking=no $MASTER_NODE sudo cp /etc/kubernetes/pki/etcd/peer.crt ~/etcd_pki
ssh -i $SSH_KEY -o StrictHostKeyChecking=no $MASTER_NODE sudo cp /etc/kubernetes/pki/etcd/peer.key ~/etcd_pki
ssh -i $SSH_KEY -o StrictHostKeyChecking=no $MASTER_NODE sudo chown ubuntu:ubuntu ~/etcd_pki/*
scp -i $SSH_KEY -o StrictHostKeyChecking=no -r $MASTER_NODE:etcd_pki/ .
kubectl create secret generic etcd-client-cert --from-file=etcd-ca=./etcd_pki/ca.key --from-file=etcd-client=./etcd_pki/peer.crt --from-file=etcd-client-key=./etcd_pki/peer.key --namespace lma
print_msg "... done"
