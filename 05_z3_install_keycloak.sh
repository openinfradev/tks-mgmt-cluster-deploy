#!/bin/bash

set -e

source lib/common.sh

if [ -z "$1" ]; then
    echo "usage: $0 <assets dir>"
    exit 1
fi

ASSETS_DIR=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

kubectl create ns keycloak || true

if [ -z "$DATABASE_HOST" ]; then
  INTERNAL_POSTGRESQL_ENABLED=true
else
  INTERNAL_POSTGRESQL_ENABLED=false
fi

case "$KEYCLOAK_TLS_SETTING" in
  "none")
    KEYCLOAK_ANNOTATIONS=""
    KEYCLOAK_EXISTING_CERTIFICATE="[]"
    KEYCLOAK_INGRESS_TLS_ENABLED=false
    KEYCLOAK_SELF_SIGNED=false
    ;;

  "self-signed")
    KEYCLOAK_ANNOTATIONS=""
    KEYCLOAK_EXISTING_CERTIFICATE="[]"
    KEYCLOAK_INGRESS_TLS_ENABLED=true
    KEYCLOAK_SELF_SIGNED=true
    ;;

  "letsencrypt")
    KEYCLOAK_ANNOTATIONS=$(cat << EOL
    acme.cert-manager.io/http01-edit-in-place: "true"
    cert-manager.io/cluster-issuer: tks-cluster-issuer
EOL
)
    KEYCLOAK_EXISTING_CERTIFICATE="[]"
    KEYCLOAK_INGRESS_TLS_ENABLED=true
    KEYCLOAK_SELF_SIGNED=false

    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: tks-cluster-issuer
spec:
  acme:
    email: "$KEYCLOAK_CERT_EMAIL"
    preferredChain: ""
    privateKeySecretRef:
      name: tks-cluster-issuer-account-key
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - http01:
        ingress:
          class: nginx
EOF


    ;;
  "exist-cert")
    KEYCLOAK_ANNOTATIONS=""
    KEYCLOAK_TLS_CERT=$(cat "$KEYCLOAK_TLS_CERT_PATH")
    KEYCLOAK_TLS_KEY=$(cat "$KEYCLOAK_TLS_KEY_PATH")
    KEYCLOAK_EXISTING_CERTIFICATE=$(cat << EOL

    - name: keycloak-tls
      key: |
        $KEYCLOAK_TLS_KEY
      certificate: |
        $KEYCLOAK_TLS_CERT
EOL
)
    KEYCLOAK_INGRESS_TLS_ENABLED=true
    KEYCLOAK_SELF_SIGNED=false
    ;;

  *)
    log_info "Wrong KEYCLOAK_TLS_SETTING value. Allowed values: none, self-signed, letsencrypt, exist-cert"
    exit 1
    ;;
esac

log_info "Installing Keycloak..."


export KEYCLOAK_ADMIN_USER
export KEYCLOAK_ADMIN_PASSWORD
export KEYCLOAK_HOSTNAME
export KEYCLOAK_ANNOTATIONS
export KEYCLOAK_EXISTING_CERTIFICATE
export DATABASE_HOST
export DATABASE_PORT
export DATABASE_USER
export DATABASE_PASSWORD
export INTERNAL_POSTGRESQL_ENABLED
export KEYCLOAK_SELF_SIGNED
export KEYCLOAK_INGRESS_TLS_ENABLED

cat templates/helm-keycloak.vo.template | envsubst > $SCRIPT_DIR/helm-values/keycloak.vo

helm upgrade -i keycloak $ASSETS_DIR/keycloak-helm/keycloak -f $SCRIPT_DIR/helm-values/keycloak.vo -n keycloak

sleep 10

gum spin --spinner dot --title "Wait for all pods ready in keycloak namespace..." -- util/wait_for_all_pods_in_ns.sh keycloak

log_info "...Done"
