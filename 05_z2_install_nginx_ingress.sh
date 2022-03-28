#!/bin/bash

set -e

source common.sh

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
export KUBECONFIG=kubeconfig_$CLUSTER_NAME

print_msg "Installing NGINX Ingress..."
kubectl create ns ingress-nginx
helm repo add nginx-stable https://helm.nginx.com/stable
helm install nginx-ingress nginx-stable/nginx-ingress -n ingress-nginx

for ns in ingress-nginx; do
	for po in $(kubectl get po -n $ns -o jsonpath='{.items[*].metadata.name}');do
		kubectl wait --for=condition=Ready -n $ns --timeout=180s po/$po
	done
done
print_msg "... done"
