#!/usr/bin/env bash

# Prerequisites
# - env: YQ_PATH
# source lib/common.sh

declare -A capi_infra_acronym
capi_infra_acronym["aws"]="capa"
capi_infra_acronym["byoh"]="byoh"

provision_aws_iam_resources () {
	cat templates/bootstrap-manager-account.yaml.template | envsubst > bootstrap-manager-account.yaml
	clusterawsadm bootstrap iam update-cloudformation-stack --config bootstrap-manager-account.yaml
}

aws_cli() {
	sudo podman run --rm -it -v ~/.aws:/root/.aws public.ecr.aws/aws-cli/aws-cli $ASSET_DIR
}

install_clusterctl() {
	sudo cp $ASSET_DIR/cluster-api/$CAPI_VERSION/clusterctl-linux-amd64 /usr/local/bin/clusterctl
	sudo chmod +x /usr/local/bin/clusterctl
}

prepare_capi_providers () {
	TARGET_CLUSTER=$1
	export TARGET_REGISTRY=$2

	CAPI_OPERATOR_ASSETS_DIR="$ASSET_DIR/cluster-api-operator/$(ls $ASSET_DIR/cluster-api-operator)"
	$YQ_PATH 'select(.kind != "Deployment")' $CAPI_OPERATOR_ASSETS_DIR/operator-components.yaml > output/$TARGET_CLUSTER-capi-operator-components.yaml
	$YQ_PATH 'select(.kind == "Deployment")' $CAPI_OPERATOR_ASSETS_DIR/operator-components.yaml > output/$TARGET_CLUSTER-capi-operator-deployment.yaml
	export CAPI_OPERATOR_IMAGE_URL="${TARGET_REGISTRY}/cluster-api-operator:${CAPI_OPERATOR_VERSION}"
	$YQ_PATH -i '.spec.template.spec.containers[0].image = strenv(CAPI_OPERATOR_IMAGE_URL)' output/$TARGET_CLUSTER-capi-operator-deployment.yaml

	# XXX: where to move?
	for provider in ${CAPI_INFRA_PROVIDERS[@]}
	do
		case $provider in
			"aws")
				sudo cp $ASSET_DIR/cluster-api-provider-aws/$CAPA_VERSION/clusterawsadm-linux-amd64 /usr/local/bin/clusterawsadm
				sudo chmod +x /usr/local/bin/clusterawsadm
				;;
			"byoh")
				export ADMIN_KUBE_VERSION
				envsubst '${ADMIN_KUBE_VERSION} ${TARGET_REGISTRY}' < ./templates/example-byoh-admin.vo.template >helm-values/exmaple-byoh-admin.vo
				;;
		esac
	done

	envsubst '${TARGET_REGISTRY}' < ./templates/helm-cert-manager.vo.template >helm-values/$TARGET_CLUSTER-cert-manager.vo

	export CAPI_MANAGER_IMAGE="$TARGET_REGISTRY/cluster-api-controller:$CAPI_VERSION"
	export KUBEADM_BOOTSTRAP_MANAGER_IMAGE="$TARGET_REGISTRY/kubeadm-bootstrap-controller:$CAPI_VERSION"
	export KUBEADM_CONTROLPLANE_MANAGER_IMAGE="$TARGET_REGISTRY/kubeadm-control-plane-controller:$CAPI_VERSION"
	envsubst '${$CAPI_VERSION} ${CAPI_MANAGER_IMAGE}' < ./templates/cluster-api-core.yaml.template >output/$TARGET_CLUSTER-cluster-api-core.yaml
	envsubst '${$CAPI_VERSION} ${KUBEADM_BOOTSTRAP_MANAGER_IMAGE}' < ./templates/kubeadm-bootstrap.yaml.template >output/$TARGET_CLUSTER-kubeadm-bootstrap.yaml
	envsubst '${$CAPI_VERSION} ${KUBEADM_CONTROLPLANE_MANAGER_IMAGE}' < ./templates/kubeadm-controlplane.yaml.template >output/$TARGET_CLUSTER-kubeadm-controlplane.yaml
}

install_capi_providers() {
	TARGET_CLUSTER=$1
	TARGET_KUBECONFIG=$2

	export KUBECONFIG=$TARGET_KUBECONFIG

	for provider in ${CAPI_INFRA_PROVIDERS[@]}
	do
		case $provider in
			"aws")
				export AWS_REGION
				export AWS_ACCESS_KEY_ID
				export AWS_SECRET_ACCESS_KEY
				export AWS_ACCOUNT_ID

				gum confirm "Do you want to create IAM resources?" && provision_aws_iam_resources

				export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)
				export EXP_MACHINE_POOL=true
				export CAPA_EKS_IAM=true
				export CAPA_EKS_ADD_ROLES=true

				export CREDENTIALS_SECRET_NAME="tks-capi-variables"
				export CREDENTIALS_SECRET_NAMESPACE="default"

				kubectl delete secret "${CREDENTIALS_SECRET_NAME}" || true
				kubectl create secret generic "${CREDENTIALS_SECRET_NAME}" --namespace "${CREDENTIALS_SECRET_NAMESPACE}" \
					--from-literal=AWS_REGION="${AWS_REGION}" \
					--from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
					--from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
					--from-literal=EXP_MACHINE_POOL="${EXP_MACHINE_POOL}" \
					--from-literal=CAPA_EKS_IAM="${CAPA_EKS_IAM}" \
					--from-literal=CAPA_EKS_ADD_ROLES="${CAPA_EKS_ADD_ROLES}" \
					--from-literal=AWS_B64ENCODED_CREDENTIALS="${AWS_B64ENCODED_CREDENTIALS}"
				;;
			"byoh")
				;;
		esac
	done

	helm upgrade -i -n cert-manager --create-namespace cert-manager $ASSET_DIR/cert-manager/cert-manager -f helm-values/$TARGET_CLUSTER-cert-manager.vo
	./util/wait_for_all_pods_in_ns.sh cert-manager

	kubectl apply -f output/capi-operator-components.yaml
	kubectl apply -f output/capi-operator-deployment.yaml
	./util/wait_for_all_pods_in_ns.sh capi-operator-system

	create_provider_configmap capi core $ASSET_DIR/cluster-api/$CAPI_VERSION/core-components.yaml $ASSET_DIR/cluster-api/$CAPI_VERSION/metadata.yaml $CAPI_VERSION
	create_provider_configmap kubeadm bootstrap $ASSET_DIR/cluster-api/$CAPI_VERSION/bootstrap-components.yaml $ASSET_DIR/cluster-api/$CAPI_VERSION/metadata.yaml $CAPI_VERSION
	create_provider_configmap kubeadm controlplane $ASSET_DIR/cluster-api/$CAPI_VERSION/control-plane-components.yaml $ASSET_DIR/cluster-api/$CAPI_VERSION/metadata.yaml $CAPI_VERSION
	kubectl apply -f output/$TARGET_CLUSTER-cluster-api-core.yaml
	kubectl apply -f output/$TARGET_CLUSTER-kubeadm-bootstrap.yaml
	kubectl apply -f output/$TARGET_CLUSTER-kubeadm-controlplane.yaml

	CAPI_NAMESPACE="capi-system capi-kubeadm-bootstrap-system capi-kubeadm-control-plane-system"

	for provider in ${CAPI_INFRA_PROVIDERS[@]}
	do
		case $provider in
			"aws")
				create_provider_configmap capa infrastructure $ASSET_DIR/cluster-api-provider-aws/$CAPA_VERSION/infrastructure-components.yaml $ASSET_DIR/cluster-api-provider-aws/$CAPA_VERSION/metadata.yaml $CAPA_VERSION

				export CAPA_INFRA_MANAGER_IMAGE="$TARGET_REGISTRY/cluster-api-aws-controller:$CAPA_VERSION"
				envsubst '${CAPA_VERSION} ${CAPA_INFRA_MANAGER_IMAGE}' < ./templates/aws-infra.yaml.template >output/$TARGET_CLUSTER-aws-infra.yaml
				kubectl apply -f output/$TARGET_CLUSTER-aws-infra.yaml
				CAPI_NAMESPACE+=" capa-system"
				;;
			"byoh")
				create_provider_configmap byoh infrastructure $ASSET_DIR/cluster-api-provider-bringyourownhost/$BYOH_VERSION/infrastructure-components.yaml $ASSET_DIR/cluster-api-provider-bringyourownhost/$BYOH_VERSION/metadata.yaml $BYOH_VERSION

				export BYOH_INFRA_MANAGER_IMAGE="$TARGET_REGISTRY/cluster-api-byoh-controller:$BYOH_TKS_VERSION"
				export BYOH_INFRA_KUBE_RBAC_PROXY_IMAGE="$TARGET_REGISTRY/kube-rbac-proxy:v0.8.0"
				envsubst '${$BYOH_VERSION} ${$BYOH_TKS_VERSION} ${BYOH_INFRA_MANAGER_IMAGE} ${BYOH_INFRA_KUBE_RBAC_PROXY_IMAGE}' < ./templates/byoh-infra.yaml.template >output/$TARGET_CLUSTER-byoh-infra.yaml
				kubectl apply -f output/$TARGET_CLUSTER-byoh-infra.yaml
				CAPI_NAMESPACE+=" byoh-system"
				;;
		esac
	done

	for ns in $CAPI_NAMESPACE; do
		sleep 10
		./util/wait_for_all_pods_in_ns.sh $ns
	done
}

get_namespace_for_capi_provider() {
        if [ $# != 2 ]; then
                log_error "$0: wrong number of parametes"
                exit 1
        fi

        PROVIDER_NAME=$1
        PROVIDER_TYPE=$2

	case $PROVIDER_TYPE in
		core)
			# only for cluster-api
			echo "capi-system"
			;;

		bootstrap)
			# only for kubeadm
			echo "capi-kubeadm-bootstrap-system"
			;;

		controlplane)
			# only for kubeadm
			echo "capi-kubeadm-control-plane-system"
			;;

		infrastructure)
			# capa, byoh
			echo "$PROVIDER_NAME-system"
			;;

		*)
			echo "ERROR> $0: wrong provider type $PROVIDER_TYPE"
			;;
	esac

}

# these confingmaps have original provider yamls only.
create_provider_configmap() {
        if [ $# != 5 ]; then
                log_error "$0: wrong number of parametes"
        fi

        PROVIDER_NAME=$1
        PROVIDER_TYPE=$2
        COMPONENT_FILE=$3
        METADATA_FILE=$4
        VERSION=$5

        #gzip -c components.yaml > components.gz
	NAMESPACE=$(get_namespace_for_capi_provider $PROVIDER_NAME $PROVIDER_TYPE)

	CONFIGMAP_FILE_PATH="output/configmap-$PROVIDER_NAME-$PROVIDER_TYPE-$VERSION.yaml"
        kubectl create ns $NAMESPACE || true
        kubectl create configmap $PROVIDER_NAME-$PROVIDER_TYPE-$VERSION --namespace=$NAMESPACE --from-file=components=$COMPONENT_FILE --from-file=metadata=$METADATA_FILE --dry-run=client -o yaml > $CONFIGMAP_FILE_PATH

        #$YQ_PATH eval -i '.metadata.annotations += {"provider.cluster.x-k8s.io/compressed": "true"}' $CONFIGMAP_FILE_PATH
        $YQ_PATH eval -i '.metadata.labels += {"provider-components": "'${PROVIDER_NAME}-${PROVIDER_TYPE}'"}' $CONFIGMAP_FILE_PATH

        $YQ_PATH eval -i '.metadata.labels += {"provider.cluster.x-k8s.io/name": "'${PROVIDER_NAME}'"}' $CONFIGMAP_FILE_PATH
        $YQ_PATH eval -i '.metadata.labels += {"provider.cluster.x-k8s.io/type": "'${PROVIDER_TYPE}'"}' $CONFIGMAP_FILE_PATH
        $YQ_PATH eval -i '.metadata.labels += {"provider.cluster.x-k8s.io/version": "'${VERSION}'"}' $CONFIGMAP_FILE_PATH

        kubectl delete -f $CONFIGMAP_FILE_PATH || true
        kubectl create -f $CONFIGMAP_FILE_PATH
}
