#!/bin/bash

set -e

source lib/common.sh

declare -a DOCKER_PKGS_UBUNTU=("containerd.io_1.6.7-1_amd64.deb" "docker-ce-cli_20.10.17~3-0~ubuntu-focal_amd64.deb" "docker-ce_20.10.17~3-0~ubuntu-focal_amd64.deb" "docker-compose-plugin_2.6.0~ubuntu-focal_amd64.deb")
declare -a DOCKER_PKGS_CENTOS=("containerd.io-1.6.7-3.1.el8.x86_64.rpm" "docker-ce-20.10.17-3.el8.x86_64.rpm" "docker-ce-cli-20.10.17-3.el8.x86_64.rpm" "docker-compose-plugin-2.6.0-3.el8.x86_64.rpm")
KIND_ASSETS_URL="https://github.com/kubernetes-sigs/kind/releases"
KIND_ASSETS_FILES=(kind-linux-amd64)
KIND_VERSION="latest"
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
GUM_ASSETS_FILES=(gum_0.5.0_linux_x86_64.tar.gz)
GUM_VERSION="latest"

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
		sudo rpm -Uvh $ASSETS_DIR/docker-ce/*.rpm
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
for provider in ${CAPI_INFRA_PROVIDERS[@]}
do
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

# TODO: use associate arrays..
log_info "Downloading TACO Helm chart source"
#git clone --quiet https://github.com/openinfradev/helm-charts.git $ASSETS_DIR/taco-helm -b $TKS_RELEASE
git clone --quiet https://github.com/openinfradev/helm-charts.git $ASSETS_DIR/taco-helm -b byoh_v0.3.0

log_info "Downloading TACO Helm Repo"
git clone --quiet https://github.com/openinfradev/helm-repo.git $ASSETS_DIR/helm-repo -b $TKS_RELEASE

log_info "Downloading Argo Helm chart"
helm pull argo-cd --repo https://argoproj.github.io/argo-helm --version $ARGOCD_CHART_VERSION --untar --untardir $ASSETS_DIR/argo-cd-helm

log_info "Downloading AWS EBS CSI chart"
helm pull aws-ebs-csi-driver --repo https://kubernetes-sigs.github.io/aws-ebs-csi-driver --untar --untardir $ASSETS_DIR/aws-ebs-csi-driver

log_info "Downloading Decapod bootstrap"
git clone --quiet https://github.com/openinfradev/decapod-bootstrap $ASSETS_DIR/decapod-bootstrap -b $TKS_RELEASE

log_info "Downloading Decapod flow"
git clone --quiet https://github.com/openinfradev/decapod-flow $ASSETS_DIR/decapod-flow -b $TKS_RELEASE

log_info "Downloading TKS flow"
git clone --quiet https://$GITHUB_TOKEN@github.com/openinfradev/tks-flow $ASSETS_DIR/tks-flow -b $TKS_RELEASE

log_info "Downloading TKS proto"
git clone --quiet https://$GITHUB_TOKEN@github.com/openinfradev/tks-proto $ASSETS_DIR/tks-proto -b $TKS_RELEASE

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

log_info "...Done"
