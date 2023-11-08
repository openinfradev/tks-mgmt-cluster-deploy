#!/bin/bash

set -e

source lib/common.sh

if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "usage: $0 <assets dir> <values.yaml for admin cluster>"
    echo "See the example-values_admin_cluster.yaml."
    exit 1
fi

ASSET_DIR=$1
HELM_VALUE_FILE=$2
HELM_VALUE_K8S_ADDONS="--set cni.calico.enabled=true"
IS_MANAGED_CLUSTER="false"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export KUBECONFIG=~/.kube/config

log_info "Creating TKS Admin Cluster via Cluster API"

create_capa_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-aws
	helm upgrade -i tks-admin $CHART_DIR -f $HELM_VALUE_FILE

	if grep -Fq "eksEnabled: true" $HELM_VALUE_FILE;then
		KUBECONFIG_SECRET_NAME=$CLUSTER_NAME-user-kubeconfig
		IS_MANAGED_CLUSTER="true"

		EKSCTL_ASSET_DIR="$ASSET_DIR/eksctl/$(ls $ASSET_DIR/eksctl | grep v)"
		AWS_IAM_AUTHENTICATOR_ASSET_DIR="$ASSET_DIR/aws-iam-authenticator/$(ls $ASSET_DIR/aws-iam-authenticator | grep v)"
		sudo tar xfz $EKSCTL_ASSET_DIR/eksctl_linux_amd64.tar.gz -C /usr/local/bin/
		sudo cp $AWS_IAM_AUTHENTICATOR_ASSET_DIR/aws-iam-authenticator* /usr/local/bin/aws-iam-authenticator
		sudo chmod +x /usr/local/bin/aws-iam-authenticator
	else
		KUBECONFIG_SECRET_NAME=$CLUSTER_NAME-kubeconfig
	fi
}

create_byoh_cluster () {
	CHART_DIR=$ASSET_DIR/taco-helm/cluster-api-byoh
	helm upgrade -i tks-admin $CHART_DIR -f $HELM_VALUE_FILE

	KUBECONFIG_SECRET_NAME=$CLUSTER_NAME-kubeconfig
}

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
        "aws")
                create_capa_cluster
                ;;

        "byoh")
		create_byoh_cluster
                ;;
esac

CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
sed -i '/CLUSTER_NAME/d' $SCRIPT_DIR/conf.sh
echo CLUSTER_NAME=$CLUSTER_NAME >> $SCRIPT_DIR/conf.sh
log_info "TKS Admin cluster chart successfully installed"

gum spin --spinner dot --title "Verifing TKS Admin cluster is ready..." -- util/wait_for_cluster_ready.sh $CLUSTER_NAME $IS_MANAGED_CLUSTER

log_info  "Installing kubernetes addons for network and storage"
case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		if grep -Fq "eksEnabled: true" $HELM_VALUE_FILE;then
			kubectl get secret $CLUSTER_NAME-user-kubeconfig -o jsonpath={.data.value} | base64 --decode > output/kubeconfig_$CLUSTER_NAME
			chmod 600 output/kubeconfig_$CLUSTER_NAME
			export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME

			cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: taco-storage
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
EOF

		else
			clusterctl get kubeconfig $CLUSTER_NAME > output/kubeconfig_$CLUSTER_NAME
			chmod 600 output/kubeconfig_$CLUSTER_NAME
			helm upgrade -i k8s-addons $ASSET_DIR/taco-helm/kubernetes-addons $HELM_VALUE_K8S_ADDONS
			helm upgrade -i aws-ebs-csi-driver --namespace kube-system $ASSET_DIR/aws-ebs-csi-driver-helm/aws-ebs-csi-driver
		fi
		;;

	"byoh")
		clusterctl get kubeconfig $CLUSTER_NAME > output/kubeconfig_$CLUSTER_NAME
		chmod 600 output/kubeconfig_$CLUSTER_NAME
		export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME
		kubectl apply -f $ASSET_DIR/calico/calico.yaml
		helm upgrade -i local-path-provisioner --namespace kube-system --set storageClass.name=taco-storage $ASSET_DIR/local-path-provisioner/deploy/chart/local-path-provisioner
		;;
esac

log_info "Waiting for all nodes ready"
for node in $(kubectl get no -o jsonpath='{.items[*].metadata.name}');do
	kubectl wait --for=condition=Ready no/$node
done
echo "-----"
kubectl get no
log_info  "Make sure all node status are ready"

install_capi_to_admin_cluster() {
	export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME
	log_info "Initializing cluster API provider components in TKS admin cluster"
	for provider in ${CAPI_INFRA_PROVIDERS[@]}; do
		case $provider in
			"aws")
				export AWS_REGION
				export AWS_ACCESS_KEY_ID
				export AWS_SECRET_ACCESS_KEY

				export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
				export EXP_MACHINE_POOL=true
				export CAPA_EKS_IAM=true
				export CAPA_EKS_ADD_ROLES=true

				CAPI_PROVIDER_NS=capa-system
				;;
			"byoh")
				CAPI_PROVIDER_NS=byoh-system
				;;
		esac
	done

	case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
		"byoh")
			for no in $(kubectl get no -o name); do
				BYOH_TMP_NODE=${no#*/}
				kubectl taint nodes $no node-role.kubernetes.io/control-plane:NoSchedule- || true
			done
			;;
	esac
	gum spin --spinner dot --title "Waiting for providers to be installed..." -- clusterctl init --infrastructure $(printf -v joined '%s,' "${CAPI_INFRA_PROVIDERS[@]}"; echo "${joined%,}") --wait-providers
}

install_capi_to_admin_cluster

move_byoh_resources() {
	rc_kind=$1

	log_info "Move $rc_kind BYOH resources to the admin cluster"

	export KUBECONFIG=~/.kube/config
	for rc in $(kubectl get $rc_kind -o name); do
		rc_file=${rc#*/}
		kubectl get $rc -o yaml | egrep -v 'uid|resourceVersion|creationTimestamp|generation' > output/$rc_kind-"$rc_file".yaml
		kubectl apply --kubeconfig output/kubeconfig_$CLUSTER_NAME -f output/$rc_kind-"$rc_file".yaml
	done
}

if [ $TKS_ADMIN_CLUSTER_INFRA_PROVIDER == "byoh" ]; then
       gum spin --spinner dot --title "Deleting BYOH infra provider for a moment..." -- clusterctl delete --infrastructure byoh

       move_byoh_resources byoh
       move_byoh_resources k8sinstallerconfigtemplates

       export KUBECONFIG=output/kubeconfig_$CLUSTER_NAME
       gum spin --spinner dot --title "Reinstalling BYOH infra provider..." -- clusterctl init --infrastructure $(printf -v joined '%s,' "${CAPI_INFRA_PROVIDERS[@]}"; echo "${joined%,}") --wait-providers

       kubectl patch deploy -n byoh-system  byoh-controller-manager --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":"1000Mi"}]'
       deployment.apps/byoh-controller-manager patched
       kubectl patch deploy -n byoh-system  byoh-controller-manager --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value":"1000m"}]'

       ./06_make_tks-admin_self-managing.sh

       log_info "1. Generate byoh script and run byoh-hostagent on target hosts."
       log_info "2. Scale out a replica of the control plane and the tks node machinedeployment."
       log_info " $ kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME scale kcp --replicas 3 $CLUSTER_NAME"
       log_info " $ kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME scale md --replicas 3 $CLUSTER_NAME-md-tks"
       log_info "3. Remove the temporary admin node."
       log_info " $ kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME drain --ignore-daemonsets=true $BYOH_TMP_NODE"
       TMP_MACHINE_NAME=$(kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME get machine -ojsonpath="{.items[?(@.status.nodeRef.name == \"$BYOH_TMP_NODE\")].metadata.name}")
       TMP_BYOM_NAME=$(kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME get byomachine -ojsonpath="{.items[?(@.metadata.ownerReferences[].name == \"$TMP_MACHINE_NAME\")].metadata.name}")
       log_info " $ kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME delete machine $TMP_MACHINE_NAME"
       log_info " (if necessary) $ kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME patch machine -p '{"metadata":{"finalizers":null}}' --type=merge $TMP_MACHINE_NAME"
       log_info " (if necessary) $ kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME delete byomachines $TMP_BYOM_NAME"
       log_info " $ kubectl --kubeconfig output/kubeconfig_$CLUSTER_NAME delete byoh $BYOH_TMP_NODE"
       log_info "4. Copy util/byoh_host_uninstall.sh to the temporary node and Run the script."
       log_info " (example) $ ./byoh_host_uninstall.sh /var/lib/byoh/bundles/harbor.taco-cat.xyz/cluster_api_provider_bringyourownhost/byoh-bundle-rocky_linux_8.7_x86-64_k8s\:v1.25.11/"
       log_info "5. To reuse the temporary host as an admin cluster node, regenerate byoh script and run byoh-hostagent on the host."
fi
