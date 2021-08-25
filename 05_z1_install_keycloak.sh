#!/bin/bash

set -e

source common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <helm value file for overriding>"
    exit 1
fi

HELM_VALUE_FILE=$1
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')

export KUBECONFIG=kubeconfig_$CLUSTER_NAME

print_msg "Configure PostgreSQL DB for keycloak..."
PSQL_CMD="kubectl exec -n decapod-db postgresql-postgresql-0 -- bash -c \"PGPASSWORD=tacopassword /opt/bitnami/postgresql/bin/psql -U postgres -c"

eval ${PSQL_CMD} "\\\"CREATE DATABASE keycloak;\\\"\""
eval ${PSQL_CMD} "\\\"CREATE USER keycloak WITH ENCRYPTED PASSWORD 'keycloak';\\\"\""
eval ${PSQL_CMD} "\\\"GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;\\\"\""
print_msg "... done"

print_msg "Installing Keycloak..."
kubectl create ns keycloak
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install keycloak bitnami/keycloak -n keycloak -f $HELM_VALUE_FILE

for ns in keycloak; do
	for po in $(kubectl get po -n $ns -o jsonpath='{.items[*].metadata.name}');do
		kubectl wait --for=condition=Ready -n $ns --timeout=180s po/$po
	done
done
print_msg "... done"
