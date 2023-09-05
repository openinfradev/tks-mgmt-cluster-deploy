#!/bin/bash

set -e

source lib/common.sh

function usage {
        echo -e "\nUsage: $0 <kubeconfig> <hostname> [--output OUTPUT_SCRIPT_PATH]"
	echo -e "\n\tOUTPUT_SCRIPT_PATH (default): output/install_byoh_hostagent-<hostname>.sh"
        exit 1
}

[[ $# -ge 2 ]] || usage 

inarray=$(echo ${CAPI_INFRA_PROVIDERS[@]} | grep -ow "byoh" | wc -w)
[[ $inarray -ne 0 ]] || log_error "byoh infra provider is not configured"

export KUBECONFIG=$1
HOSTNAME=$2
shift
OUTPUT_SCRIPT_PATH=output/install_byoh_hostagent-$HOSTNAME.sh

ARGS=$(getopt -o 'o:h' --long 'output:,help' -- "$@") || usage
eval "set -- $ARGS"
while true; do
    case $1 in
      (-h|--help)
            usage; shift;;
      (-o|--output)
            OUTPUT_SCRIPT_PATH=$2; shift;;
      (--)  shift; break;;
      (*)   exit 1;;           # error
    esac
done

if [ -f "$OUTPUT_SCRIPT_PATH" ]; then
	log_warn "$OUTPUT_SCRIPT_PATH for the host $HOSTNAME is already exist"
	while true
	do
		read -r -p "Are you sure you want to create a new file and overwrite it? [Y/n] " input

		case $input in
			[yY][eE][sS]|[yY])
				echo "Yes"
				break
				;;
			[nN][oO]|[nN])
				echo "No"
				exit 1
				;;
			*)
				echo "Invalid input..."
				;;
		esac      
	done
fi

kubectl delete bootstrapkubeconfig bootstrap-kubeconfig-$HOSTNAME 2>/dev/null || true
kubectl delete csr byoh-csr-$HOSTNAME  2>/dev/null || true
# TODO: delete token secret 

APISERVER=$(kubectl config view -ojsonpath='{.clusters[0].cluster.server}')
CA_CERT=$(kubectl config view --flatten -ojsonpath='{.clusters[0].cluster.certificate-authority-data}')
cat <<EOF | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: BootstrapKubeconfig
metadata:
  name: bootstrap-kubeconfig-$HOSTNAME
  namespace: default
spec:
  apiserver: "$APISERVER"
  certificate-authority-data: "$CA_CERT"
EOF

log_info "Generating byoh agent install script"
sleep 3

kubectl get bootstrapkubeconfig bootstrap-kubeconfig-$HOSTNAME -n default -o=jsonpath='{.status.bootstrapKubeconfigData}' > output/bootstrap-kubeconfig-$HOSTNAME.conf

if kubectl get no | grep kind; then
	export KIND_PORT=$(sudo docker inspect kind-control-plane -f '{{ $published := index .NetworkSettings.Ports "6443/tcp" }}{{ range $published }}{{ .HostPort }}{{ end }}')
	sed -i 's/    server\:.*/    server\: https\:\/\/'"$BOOTSTRAP_CLUSTER_SERVER_IP:$KIND_PORT"'/g' output/bootstrap-kubeconfig-$HOSTNAME.conf
fi

bootstrap_kubeconfig=$(cat output/bootstrap-kubeconfig-$HOSTNAME.conf | base64 -w 0)
export bootstrap_kubeconfig
envsubst '$bootstrap_kubeconfig' < ./templates/install_byoh_hostagent.sh.template >$OUTPUT_SCRIPT_PATH
chmod +x $OUTPUT_SCRIPT_PATH

log_info "Copy below files to each host and run a script!"
echo "$OUTPUT_SCRIPT_PATH output/byoh-hostagent-linux-amd64"
