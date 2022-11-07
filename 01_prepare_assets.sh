#!/bin/bash

set -e

source lib/common.sh

declare -a DOCKER_PKGS_UBUNTU=("containerd.io_1.6.7-1_amd64.deb" "docker-ce-cli_20.10.17~3-0~ubuntu-focal_amd64.deb" "docker-ce_20.10.17~3-0~ubuntu-focal_amd64.deb" "docker-compose-plugin_2.6.0~ubuntu-focal_amd64.deb")
declare -a DOCKER_PKGS_CENTOS=("containerd.io-1.6.7-3.1.el8.x86_64.rpm" "docker-ce-20.10.17-3.el8.x86_64.rpm" "docker-ce-cli-20.10.17-3.el8.x86_64.rpm" "docker-ce-rootless-extras-20.10.17-3.el8.x86_64.rpm " "docker-compose-plugin-2.6.0-3.el8.x86_64.rpm")

# Github assets
KIND_ASSETS_URL="https://github.com/kubernetes-sigs/kind/releases"
KIND_ASSETS_FILES=(kind-linux-amd64)
KIND_VERSION="v0.16.0"
CAPI_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api/releases"
CAPI_ASSETS_FILES=(metadata.yaml bootstrap-components.yaml cluster-api-components.yaml clusterctl-linux-amd64 control-plane-components.yaml core-components.yaml)
CAPA_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api-provider-aws/releases"
CAPA_ASSETS_FILES=(metadata.yaml clusterawsadm-linux-amd64 infrastructure-components.yaml)
BYOH_ASSETS_URL="https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost/releases"
BYOH_ASSETS_FILES=(metadata.yaml infrastructure-components.yaml byoh-hostagent-linux-amd64)
ARGOWF_ASSETS_URL="https://github.com/argoproj/argo-workflows/releases"
ARGOWF_ASSETS_FILES=(argo-linux-amd64.gz)
ARGOCD_ASSETS_URL="https://github.com/argoproj/argo-cd/releases"
ARGOCD_ASSETS_FILES=(argocd-linux-amd64)
GUM_ASSETS_URL="https://github.com/charmbracelet/gum/releases"
GUM_ASSETS_FILES=(gum_0.7.0_linux_x86_64.tar.gz)
GUM_VERSION="v0.7.0"

# Git repos
# "repo_url,tag/branch,dest_dir"
git_repos=("https://github.com/openinfradev/helm-charts.git,${TKS_RELEASE},taco-helm")
git_repos+=("https://github.com/openinfradev/helm-repo.git,${TKS_RELEASE},taco-helm-repo")
git_repos+=("https://github.com/openinfradev/decapod-bootstrap,${TKS_RELEASE},decapod-bootstrap")
git_repos+=("https://github.com/openinfradev/decapod-flow,${TKS_RELEASE},decapod-flow")
git_repos+=("https://github.com/openinfradev/tks-flow,${TKS_RELEASE},tks-flow")
git_repos+=("https://github.com/openinfradev/decapod-base-yaml,${TKS_RELEASE},decapod-base-yaml")
git_repos+=("https://github.com/openinfradev/decapod-site,${TKS_RELEASE},decapod-site")
git_repos+=("https://github.com/openinfradev/decapod-manifests,${TKS_RELEASE},decapod-manifests")

# Helm chart
# "chart_name,repo_url,chart_version,dest_dir"
helm_charts=("argo-cd,https://argoproj.github.io/argo-helm,$ARGOCD_CHART_VERSION,argo-cd-helm")
helm_charts+=("aws-ebs-csi-driver,https://kubernetes-sigs.github.io/aws-ebs-csi-driver,2.12.1,aws-ebs-csi-driver-helm")

# Container images for Helm chart
# "chart name,chart dir,value file"
helm_images=("argo-cd,argo-cd-helm,decapod-bootstrap/argocd-install/values-override.yaml")
helm_images+=("aws-ebs-csi-driver,aws-ebs-csi-driver-helm,aws-ebs-csi-driver-helm/aws-ebs-csi-driver/values.yaml")

# Container images
# "image,tag"
container_images=("quay.io/prometheus-operator/prometheus-config-reloader,v0.46.0")
container_images+=("docker.io/jaegertracing/jaeger-collector,1.22.0")

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

	reponame=${url%/releases*}
	reponame=${reponame##*.com/}

	log_info "Downloading assets from $reponame"

	if [[ $version == "latest" ]]
	then
		tag=$(github_get_latest_release $reponame)
	else
		tag=$version
	fi

	dest_dir=$ASSETS_DIR/$(basename $reponame)/$tag
	mkdir -p $dest_dir

	for f in ${files[@]}
	do
		curl -sSL "$url/download/$tag/$f" -o $dest_dir/$f
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

		helm pull $name --repo $repo --version $version --untar --untardir $ASSETS_DIR/$dest_dir
	done
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

pull_misc_images() {
	log_info "Pulling container images"
	for chart in ${container_images[*]}; do
		image=$(echo $chart | awk -F',' '{print $1}')
		tag=$(echo $chart | awk -F',' '{print $2}')

		if [ -z $image ] || [ -z $tag ]; then
			log_error "wrong container image"
		fi

		sudo docker pull $image:$tag
	done
}

pull_workflow_images () {
	log_info "Pulling images for argo workflows"
	cd $ASSETS_DIR/$1

	for img in $(grep -r "image:" * | awk '{print $3}'); do
		sudo docker pull $img
	done

	cd - >/dev/null
}

log_info "=== Download assets to the $ASSETS_DIR directory ==="

check_if_supported_os

if [ -d $ASSETS_DIR ]; then
	log_warn "$ASSETS_DIR is already exist"
	gum confirm "Are you sure you want to clear the current directory and proceed?" || exit 1
fi

rm -rf $ASSETS_DIR

mkdir $ASSETS_DIR
mkdir -p output

download_assets_from_github GUM
GUM_ASSETS_DIR="$ASSETS_DIR/gum/$(ls $ASSETS_DIR/gum | grep v)"
cd $GUM_ASSETS_DIR
tar xfz $(ls)
sudo cp gum /usr/local/bin
cd - >/dev/null

log_info "Downloading docker packages"
mkdir $ASSETS_DIR/docker-ce
cd $ASSETS_DIR/docker-ce
for pkg in ${DOCKER_PKGS_UBUNTU[@]}
do
	curl -sSLO https://download.docker.com/linux/ubuntu/dists/focal/pool/stable/amd64/$pkg
done
for pkg in ${DOCKER_PKGS_CENTOS[@]}
do
	curl -sSLO https://download.docker.com/linux/centos/8/x86_64/stable/Packages/$pkg
done
cd - >/dev/null

log_info "Installing docker packages"
case $OS_ID in
	"rocky" | "centos" | "rhel")
		sudo dnf install -y container-selinux iptables libcgroup fuse-overlayfs slirp4netns
		sudo dnf localinstall $ASSETS_DIR/docker-ce/*.rpm
		;;

	"ubuntu" )
		sudo dpkg -i $ASSETS_DIR/docker-ce/*.deb
		;;
esac
sudo systemctl start docker

download_assets_from_github KIND
log_info "Downloading a kind node image"
sudo docker pull kindest/node:$KIND_NODE_IMAGE_TAG
sudo docker save kindest/node:$KIND_NODE_IMAGE_TAG | gzip > $ASSETS_DIR/kind-node-image.tar.gz

download_assets_from_github CAPI
for provider in ${CAPI_INFRA_PROVIDERS[@]}; do
	case $provider in
		"aws")
			download_assets_from_github CAPA
			;;
		"byoh")
			download_assets_from_github BYOH
			cp $ASSETS_DIR/cluster-api-provider-bringyourownhost/$BYOH_VERSION/byoh-hostagent-linux-amd64 output/
			chmod +x output/byoh-hostagent-linux-amd64
			;;
	esac
done

download_assets_from_github ARGOCD
download_assets_from_github ARGOWF && gunzip $ASSETS_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64.gz

log_info "Downloading and installing Helm client"
HELM_TAGS=$(github_get_latest_release helm/helm)
curl -sSL https://get.helm.sh/helm-$HELM_TAGS-linux-amd64.tar.gz -o helm.tar.gz
tar xvfz helm.tar.gz > /dev/null
cp linux-amd64/helm $ASSETS_DIR
sudo cp linux-amd64/helm /usr/local/bin/helm
rm -rf helm.tar.gz linux-amd64

download_git_repos
download_helm_charts

pull_helm_images
pull_misc_images

pull_workflow_images decapod-flow
pull_workflow_images tks-flow

log_info "Downloading kubectl"
curl -sL -o $ASSETS_DIR/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

log_info "Downloading gitea"
curl -sL -o $ASSETS_DIR/gitea https://dl.gitea.io/gitea/1.17.3/gitea-1.17.3-linux-amd64
chmod +x $ASSETS_DIR/gitea


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

log_info "call render.sh and download helm charts"
sudo ./util/render.sh
./util/download_helm_charts.py /tmp/hr-manifests ${ASSETS_DIR}/decapod-helm

log_info "...Done"
