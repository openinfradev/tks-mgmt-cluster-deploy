#!/bin/bash

set -ex

source lib/common.sh

declare -a PKGS_CENTOS=("nginx")

# Github assets
KIND_ASSETS_URL="https://github.com/kubernetes-sigs/kind"
KIND_ASSETS_FILES=(kind-linux-amd64)
KIND_VERSION="v0.22.0"
CAPI_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api"
CAPI_ASSETS_FILES=(metadata.yaml bootstrap-components.yaml clusterctl-linux-amd64 control-plane-components.yaml core-components.yaml)
CAPA_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api-provider-aws"
CAPA_ASSETS_FILES=(metadata.yaml clusterawsadm-linux-amd64 infrastructure-components.yaml)
BYOH_ASSETS_URL="https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost"
BYOH_ASSETS_FILES=(metadata.yaml infrastructure-components.yaml byoh-hostagent-linux-amd64)
ARGOWF_ASSETS_URL="https://github.com/argoproj/argo-workflows"
ARGOWF_ASSETS_FILES=(argo-linux-amd64.gz)
ARGOCD_ASSETS_URL="https://github.com/argoproj/argo-cd"
ARGOCD_ASSETS_FILES=(argocd-linux-amd64)
GUM_ASSETS_URL="https://github.com/charmbracelet/gum"
GUM_ASSETS_FILES=(gum_0.13.0_linux_x86_64.tar.gz)
GUM_VERSION="v0.13.0"
GITEA_ASSETS_URL="https://github.com/go-gitea/gitea"
GITEA_ASSETS_FILES=(gitea-1.18.1-linux-amd64)
GITEA_VERSION="v1.8.1"
EKSCTL_ASSETS_URL="https://github.com/eksctl-io/eksctl"
EKSCTL_ASSETS_FILES=(eksctl_linux_amd64.tar.gz)
EKSCTL_VERSION="latest"
AWS_IAM_AUTHENTICATOR_ASSETS_URL="https://github.com/kubernetes-sigs/aws-iam-authenticator"
AWS_IAM_AUTHENTICATOR_ASSETS_FILES=(aws-iam-authenticator_0.5.9_linux_amd64)
AWS_IAM_AUTHENTICATOR_VERSION="v0.5.9"
JQ_ASSETS_URL="https://github.com/jqlang/jq"
JQ_ASSETS_FILES=(jq-linux64)
JQ_VERSION="jq-1.6"
YQ_ASSETS_URL="https://github.com/mikefarah/yq"
YQ_ASSETS_FILES=(yq_linux_amd64)
YQ_VERSION="v4.41.1"
CAPI_OPERATOR_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api-operator"
CAPI_OPERATOR_ASSETS_FILES=(operator-components.yaml)
CAPI_OPERATOR_VERSION="${CAPI_OPERATOR_VERSION}"
IMGPKG_ASSETS_URL="https://github.com/carvel-dev/imgpkg"
IMGPKG_ASSETS_FILES=(imgpkg-linux-amd64)
IMGPKG_VERSION="${IMGPKG_VERSION}"

# Git repos
# "repo_url,tag/branch,dest_dir"
git_repos=("https://github.com/openinfradev/helm-charts.git,main,taco-helm")
git_repos+=("https://github.com/openinfradev/helm-repo.git,main,taco-helm-repo")
git_repos+=("https://github.com/openinfradev/decapod-bootstrap,main,decapod-bootstrap")
git_repos+=("https://github.com/openinfradev/decapod-flow,${TKS_RELEASE},decapod-flow")
git_repos+=("https://github.com/openinfradev/tks-flow,${TKS_RELEASE},tks-flow")
git_repos+=("https://github.com/openinfradev/decapod-base-yaml,${TKS_RELEASE},decapod-base-yaml")
git_repos+=("https://github.com/openinfradev/decapod-site,${TKS_RELEASE},decapod-site")
git_repos+=("https://github.com/rancher/local-path-provisioner.git,master,local-path-provisioner")

# Helm chart and images
# "chart_name,repo_url,chart_version,dest_dir"
helm_charts=("argo-cd,https://argoproj.github.io/argo-helm,$ARGOCD_CHART_VERSION,argo-cd-helm")
helm_charts+=("argocd-apps,https://argoproj.github.io/argo-helm,$ARGOCD_APPS_CHART_VERSION,argocd-apps-helm")
helm_charts+=("aws-ebs-csi-driver,https://kubernetes-sigs.github.io/aws-ebs-csi-driver,2.21.0,aws-ebs-csi-driver-helm")
helm_charts+=("postgresql,oci://registry-1.docker.io/bitnamicharts,12.6.5,postgresql-helm")
helm_charts+=("gitea,https://dl.gitea.io/charts,8.3.0,gitea-helm")
helm_charts+=("ingress-nginx,https://kubernetes.github.io/ingress-nginx,4.7.1,ingress-nginx-helm")
#helm_charts+=("cluster-api-operator,https://kubernetes-sigs.github.io/cluster-api-operator,0.8.1,cluster-api-operator")
helm_charts+=("cert-manager,https://charts.jetstack.io,1.13.2,cert-manager")

# deprecated
# Container images for Helm chart
# "chart name,chart dir,value file"
helm_images=("argo-cd,argo-cd-helm,decapod-bootstrap/argocd-install/values-override.yaml")
helm_images+=("aws-ebs-csi-driver,aws-ebs-csi-driver-helm,aws-ebs-csi-driver-helm/aws-ebs-csi-driver/values.yaml")

# Container images
# "image,tag"
admin_container_images=("registry.k8s.io/capi-operator/cluster-api-operator,${CAPI_OPERATOR_VERSION}")
admin_container_images+=("registry,2,true")
# kubeadm config images list --kubernetes-version vKUBE_VERSION
admin_container_images+=("registry.k8s.io/kube-apiserver,${ADMIN_KUBE_VERSION}")
admin_container_images+=("registry.k8s.io/kube-controller-manager,${ADMIN_KUBE_VERSION}")
admin_container_images+=("registry.k8s.io/kube-scheduler,${ADMIN_KUBE_VERSION}")
admin_container_images+=("registry.k8s.io/kube-proxy,${ADMIN_KUBE_VERSION}")
admin_container_images+=("registry.k8s.io/pause,3.9")
admin_container_images+=("registry.k8s.io/etcd,3.5.10-0")
admin_container_images+=("registry.k8s.io/coredns/coredns,v1.10.1")
admin_container_images+=("registry.k8s.io/coredns/coredns,v1.9.3")
admin_container_images+=("registry.k8s.io/cluster-api/cluster-api-controller,${CAPI_VERSION}")
admin_container_images+=("registry.k8s.io/cluster-api/kubeadm-bootstrap-controller,${CAPI_VERSION}")
admin_container_images+=("registry.k8s.io/cluster-api/kubeadm-control-plane-controller,${CAPI_VERSION}")
admin_container_images+=("harbor.taco-cat.xyz/cluster_api_provider_bringyourownhost/cluster-api-byoh-controller,${BYOH_TKS_VERSION}")
admin_container_images+=("gcr.io/kubebuilder/kube-rbac-proxy,v0.8.0")
admin_container_images+=("harbor.taco-cat.xyz/cluster_api_provider_bringyourownhost/byoh-bundle-rocky_linux_8_x86-64_k8s,${ADMIN_KUBE_VERSION}")
admin_container_images+=("registry.k8s.io/cluster-api-aws/cluster-api-aws-controller,${CAPA_VERSION}")
#calico

misc_container_images=("quay.io/prometheus-operator/prometheus-config-reloader,v0.46.0")
misc_container_images+=("docker.io/jaegertracing/jaeger-collector,1.22.0")

ASSETS_DIR="assets-`date "+%Y-%m-%d"`"

github_get_latest_release() {
	curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
		grep '"tag_name":' |                                            # Get tag line
		sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

download_assets_from_github () {
	eval url='$'$1_ASSETS_URL
	eval files='$'{$1_ASSETS_FILES[@]}
	eval version='$'$1_VERSION

	owner=${url#*github.com/}
	owner=${owner%%/*}

	reponame=${url##*/}

	log_info "Downloading assets from $reponame"

	if [[ $version == "latest" ]]
	then
		tag=$(github_get_latest_release $owner/$reponame)
	else
		tag=$version
	fi

	dest_dir=$ASSETS_DIR/$(basename $reponame)/$tag
	mkdir -p $dest_dir

	for f in ${files[@]}
	do
		curl -sSL "$url/releases/download/$tag/$f" -o $dest_dir/$f
	done
}

download_git_repos() {
	log_info "Downloading Git repositories"
	for repo in ${git_repos[*]}; do
		url=$(echo $repo | awk -F',' '{print $1}')
		tag=$(echo $repo | awk -F',' '{print $2}')
		dest_dir=$(echo $repo | awk -F',' '{print $3}')

		if [ -z $url ] || [ -z $tag ] || [ -z $dest_dir ]; then
			log_error "wrong git repo"
		fi

		git clone --quiet $url -b $tag $ASSETS_DIR/$dest_dir
	done
}

push_images_to_local_registry() {
	image=$1
	tag=$2
	image_f=${image##*/}
	sudo podman tag $image:$tag localhost:5000/$image_f:$tag
	sudo podman push localhost:5000/$image_f:$tag
}

download_helm_chart_images() {
	chart_path=$1
	helm images get $chart_path

	for img in $(helm images get $chart_path); do
		if [ "$img" == "IfNotPresent" ]; then
			continue
		fi

		# remove SHA256 id
		_img=${img%%@*}
		image=${_img%%:*}
		tag=${_img##*:}
		sudo podman pull $image:$tag
		push_images_to_local_registry $image $tag
	done
}

download_helm_charts() {
	log_info "Downloading Helm charts"
	for chart in ${helm_charts[*]}; do
		name=$(echo $chart | awk -F',' '{print $1}')
		repo=$(echo $chart | awk -F',' '{print $2}')
		version=$(echo $chart | awk -F',' '{print $3}')
		dest_dir=$(echo $chart | awk -F',' '{print $4}')

		if [ -z $name ] || [ -z $repo ] || [ -z $version ] || [ -z $dest_dir ]; then
			log_error "wrong helm chart"
		fi

		if [ ${repo:0:3} = "oci" ]; then
			helm pull $repo/$name --version $version --untar --untardir $ASSETS_DIR/$dest_dir
		else
			helm pull $name --repo $repo --version $version --untar --untardir $ASSETS_DIR/$dest_dir
		fi

		download_helm_chart_images $ASSETS_DIR/$dest_dir/$name
	done
}

run_local_registry() {
	mkdir -p $ASSETS_DIR/registry || true
	reg_name='registry'
	reg_port='5000'
	if [ "$(sudo podman inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null)" == 'true' ]; then
		sudo podman rm -f "${reg_name}"
	fi
	sudo podman run \
		-d --restart=always -p "0.0.0.0:${reg_port}:5000" --privileged --name "${reg_name}" \
		-v $(realpath $ASSETS_DIR)/registry:/var/lib/registry \
		registry:2

	cat <<EOF | sudo tee /etc/containers/registries.conf.d/localregistry.conf
[[registry]]
location = "localhost:5000"
insecure = true
EOF
}

pull_helm_images() {
	log_info "Pulling images for Helm charts"
	for chart in ${helm_images[*]}; do
		name=$(echo $chart | awk -F',' '{print $1}')
		chart_dir=$(echo $chart | awk -F',' '{print $2}')
		value_path=$(echo $chart | awk -F',' '{print $3}')

		if [ -z $name ] || [ -z $chart_dir ] || [ -z $value_path ]; then
			log_error "wrong helm chart for image"
		fi

		helm template $ASSETS_DIR/$chart_dir/$name -f $ASSETS_DIR/$value_path > /tmp/$name.yaml
		sudo util/download_container_images_from_k8syaml.py /tmp/$name.yaml
	done
}

pull_container_images() {
	log_info "Pulling container images"
	mkdir -p $ASSETS_DIR/images || true

	eval images='$'{$1_container_images[*]}
	for item in ${images[*]}; do
		image=$(echo $item | awk -F',' '{print $1}')
		tag=$(echo $item | awk -F',' '{print $2}')
		saved=$(echo $item | awk -F',' '{print $3}')

		if [ -z $image ] || [ -z $tag ]; then
			log_error "wrong container image"
		fi

		sudo podman pull $image:$tag
		if [ $1 == "admin" ]; then
			push_images_to_local_registry $image $tag
			if [ "$saved" == "true" ]; then
				sudo podman save localhost:5000/$image_f:$tag | gzip > $ASSETS_DIR/images/$image_f-$tag.tar.gz
			fi
		fi
	done
}

pull_workflow_images () {
	log_info "Pulling images for argo workflows"
	cd $ASSETS_DIR/$1

	for img in $(grep -r "image:" * | awk '{print $3}'); do
		sudo podman pull $img
	done

	cd - >/dev/null
}

log_info "=== Download assets to the $ASSETS_DIR directory ==="

check_if_supported_os

if [ -d $ASSETS_DIR ]; then
	log_warn "$ASSETS_DIR is already exist"
	gum confirm "Are you sure you want to clear the current directory and proceed?" || exit 1
fi

sudo rm -rf $ASSETS_DIR

mkdir $ASSETS_DIR
mkdir -p output

download_assets_from_github GUM
GUM_ASSETS_DIR="$ASSETS_DIR/gum/$(ls $ASSETS_DIR/gum | grep v)"
cd $GUM_ASSETS_DIR
tar xfz $(ls)
sudo cp gum /usr/local/bin
cd - >/dev/null

log_info "Downloading Linux distribution packages"

mkdir -p $ASSETS_DIR/rpms
for pkg in ${PKGS_CENTOS[@]}; do
	yumdownloader  --downloadonly --downloaddir=$ASSETS_DIR/rpms $pkg --resolve
done

log_info "Installing container engine"
case $OS_ID in
	"rocky" | "centos" | "rhel")
		sudo dnf install -y podman python3
		;;

	"ubuntu" )
		sudo apt-get -y install podman
		;;
esac
sudo systemctl start podman

download_assets_from_github KIND
log_info "Downloading container images for bootstrap and admin cluster"
run_local_registry
pull_container_images admin
sudo podman pull kindest/node:$KIND_NODE_IMAGE_TAG
push_images_to_local_registry localhost:5000/kind-node ${KIND_NODE_IMAGE_TAG%%@*}

download_assets_from_github CAPI_OPERATOR
download_assets_from_github CAPI
for provider in ${CAPI_INFRA_PROVIDERS[@]}; do
	case $provider in
		"aws")
			download_assets_from_github CAPA
			;;
		"byoh")
			download_assets_from_github BYOH
			download_assets_from_github IMGPKG
			cp $ASSETS_DIR/cluster-api-provider-bringyourownhost/$BYOH_VERSION/byoh-hostagent-linux-amd64 output/byoh-hostagent
			chmod +x output/byoh-hostagent
			cp $ASSETS_DIR/imgpkg//$IMGPKG_VERSION/imgpkg-linux-amd64 output/imgpkg
			chmod +x output/imgpkg

			sed -i "s#projects.registry.vmware.com/cluster_api_provider_bringyourownhost/cluster-api-byoh-controller:$BYOH_VERSION#$TKS_BYOH_CONTOLLER_IMAGE:$BYOH_TKS_VERSION#g" $ASSETS_DIR/cluster-api-provider-bringyourownhost/$BYOH_VERSION/infrastructure-components.yaml
			;;
	esac
done

download_assets_from_github ARGOCD
download_assets_from_github ARGOWF && gunzip $ASSETS_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64.gz

download_assets_from_github EKSCTL
download_assets_from_github AWS_IAM_AUTHENTICATOR
sudo podman pull public.ecr.aws/aws-cli/aws-cli

download_assets_from_github JQ
download_assets_from_github YQ

log_info "Downloading and installing Helm client"
HELM_TAGS=$(github_get_latest_release helm/helm)
curl -sSL https://get.helm.sh/helm-$HELM_TAGS-linux-amd64.tar.gz -o helm.tar.gz
tar xvfz helm.tar.gz > /dev/null
cp linux-amd64/helm $ASSETS_DIR
sudo cp linux-amd64/helm /usr/local/bin/helm
rm -rf helm.tar.gz linux-amd64
set +e
helm plugin list | grep ^images
ret_val=$?
if [ $ret_val -ne 0 ]; then
	helm plugin install https://github.com/nikhilsbhat/helm-images
fi
set -e

download_git_repos
download_helm_charts
download_helm_chart_images $ASSETS_DIR/local-path-provisioner/deploy/chart/local-path-provisioner

if [ "DOWNLOAD_IMAGES" = true ];then
	pull_helm_images
	pull_container_images misc

	pull_workflow_images decapod-flow
	pull_workflow_images tks-flow
fi

log_info "Downloading kubectl"
curl -sL -o $ASSETS_DIR/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

cd $ASSETS_DIR
[ ! -L bootstrap-kubeadm ] && ln -s cluster-api bootstrap-kubeadm
[ ! -L control-plane-kubeadm ] && ln -s cluster-api control-plane-kubeadm

for provider in ${CAPI_INFRA_PROVIDERS[@]}
do
	case $provider in
		"aws")
			[ ! -L infrastructure-aws ] && ln -s cluster-api-provider-aws infrastructure-aws
			;;
		"byoh")
			[ ! -L infrastructure-byoh ] && ln -s cluster-api-provider-bringyourownhost infrastructure-byoh
			;;
	esac
done
cd - >/dev/null

if [ "DOWNLOAD_IMAGES" = true ];then
	log_info "call render.sh"
	sudo ./util/render.sh main byoh-reference

	log_info "download helm charts from rendered decapod manifests"
	./util/download_helm_charts.py /tmp/hr-manifests ${ASSETS_DIR}/decapod-helm

	log_info "download container images from rendered decapod manifests"
	[ ! -d /tmp/container-images/ ] && mkdir /tmp/container-images/
	cp util/*.container-images /tmp/container-images/
	[ ! -d ${ASSETS_DIR}/decapod-image/ ] && mkdir ${ASSETS_DIR}/decapod-image/
	for manifest in `ls /tmp/hr-manifests/*-manifest.yaml`
	do
		./util/download_container_images.py $manifest /tmp/container-images
	done

	for image in `cat /tmp/container-images/*-manifest.yaml.container-images | grep -v "^#" | sort | uniq`
	do
		ftemp=${image/\//\~}
		filename=${ftemp/\//\~}
		echo $filename
		if [ ! -f "${ASSETS_DIR}/decapod-image/${filename/:/^}.tar.gz" ]
		then
			sudo podman pull ${image}
			sudo podman save ${image} |gzip > "${ASSETS_DIR}/decapod-image/${filename/:/^}.tar.gz"
		fi
	done
fi

log_info "Downloading calico resources for BYOH"
mkdir $ASSETS_DIR/calico
curl -sL https://raw.githubusercontent.com/projectcalico/calico/$ADMIN_CALICO_VERSION/manifests/calico.yaml -o $ASSETS_DIR/calico/calico.yaml
sudo util/download_container_images_from_k8syaml.py $ASSETS_DIR/calico/calico.yaml
for img in $(grep "image:" $ASSETS_DIR/calico/calico.yaml | awk '{print $2}' | uniq); do
	_img=${img%%@*}
	image=${_img%%:*}
	tag=${_img##*:}

	push_images_to_local_registry $image $tag
done
sed -i "s/docker.io\/calico/$BOOTSTRAP_CLUSTER_SERVER_IP:5000/g" $ASSETS_DIR/calico/calico.yaml

log_info "...Done"
