#!/bin/bash

set -e

source lib/common.sh

GITEA_NODE_PORT=$(kubectl get -n gitea -o jsonpath="{.spec.ports[0].nodePort}" services gitea-http)
GITEA_NODE_IP=$(kubectl get no -ojsonpath='{.items[0].status.addresses[0].address}')

kubectl delete secret byoh-hostagent-install-template -n argo || true
cp templates/install_byoh_hostagent.sh.template templates/install_byoh_hostagent.sh.template.orig
HOSTAGENT_CHECKSUM=$(sha1sum output/byoh-hostagent-linux-amd64 | awk '{print $1}')
export HOSTAGENT_CHECKSUM BYOH_TKS_VERSION GIT_SVC_USERNAME GITEA_NODE_PORT GITEA_NODE_IP
envsubst '$HOSTAGENT_CHECKSUM $BYOH_TKS_VERSION $GIT_SVC_USERNAME $GITEA_NODE_IP $GITEA_NODE_PORT' < templates/install_byoh_hostagent.sh.template.orig > templates/install_byoh_hostagent.sh.template
kubectl create secret generic byoh-hostagent-install-template -n argo --from-file=agent-install-template=templates/install_byoh_hostagent.sh.template
