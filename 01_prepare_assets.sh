#!/bin/bash

set -e

source common.sh

K3S_ASSETS_URL="https://github.com/k3s-io/k3s/releases"
K3S_ASSETS_FILES=(k3s k3s-airgap-images-amd64.tar)
CAPI_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api/releases"
CAPI_ASSETS_FILES=(metadata.yaml bootstrap-components.yaml cluster-api-components.yaml clusterctl-linux-amd64 control-plane-components.yaml core-components.yaml)
CAPA_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api-provider-aws/releases"
CAPA_ASSETS_FILES=(metadata.yaml clusterawsadm-linux-amd64 infrastructure-components.yaml)
CAPO_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api-provider-openstack/releases"
CAPO_ASSETS_FILES=(metadata.yaml infrastructure-components.yaml)
ARGOWF_ASSETS_URL="https://github.com/argoproj/argo-workflows/releases"
ARGOWF_ASSETS_FILES=(argo-linux-amd64.gz)
ARGOCD_ASSETS_URL="https://github.com/argoproj/argo-cd/releases"
ARGOCD_ASSETS_FILES=(argocd-linux-amd64)

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

	print_msg "Downloading from $reponame"

	if [ $version == "latest" ]
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

	print_msg "...Done"
}

print_msg "Download assets to the $ASSETS_DIR directory"

rm -rf  $ASSETS_DIR
mkdir $ASSETS_DIR

download_assets_from_github K3S
download_assets_from_github CAPI
case $CAPI_INFRA_PROVIDER in
	"aws")
		download_assets_from_github CAPA
		;;

	"openstack")
		download_assets_from_github CAPO
		;;
esac
download_assets_from_github ARGOCD
download_assets_from_github ARGOWF && gunzip $ASSETS_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64.gz

print_msg "Downloading K3S install scripts"
K3S_TAG=$(github_get_latest_release k3s-io/k3s)
curl -sSL https://get.k3s.io -o $ASSETS_DIR/k3s/$K3S_TAG/install.sh
print_msg "...Done"

print_msg "Downloading and installing Helm client"
HELM_TAGS=$(github_get_latest_release helm/helm)
curl -sSL https://get.helm.sh/helm-$HELM_TAGS-linux-amd64.tar.gz -o helm.tar.gz
tar xvfz helm.tar.gz > /dev/null
cp linux-amd64/helm $ASSETS_DIR
sudo cp linux-amd64/helm /usr/local/bin/helm
rm -rf helm.tar.gz linux-amd64
print_msg "...Done"

print_msg "Downloading TACO Helm chart"
git clone --quiet https://github.com/openinfradev/taco-helm.git $ASSETS_DIR/taco-helm
print_msg "...Done"

print_msg "Downloading Argo Helm chart"
helm pull argo-cd --repo https://argoproj.github.io/argo-helm --version $ARGOCD_CHART_VERSION --untar --untardir $ASSETS_DIR/argo-cd-helm
print_msg "...Done"

print_msg "Downloading AWS EBS CSI chart"
helm pull aws-ebs-csi-driver --repo https://kubernetes-sigs.github.io/aws-ebs-csi-driver --untar --untardir $ASSETS_DIR/aws-ebs-csi-driver
print_msg "...Done"

print_msg "Downloading Decapod bootstrap"
git clone --quiet https://github.com/openinfradev/decapod-bootstrap $ASSETS_DIR/decapod-bootstrap
print_msg "...Done"

print_msg "Downloading Decapod flow"
git clone --quiet https://github.com/openinfradev/decapod-flow $ASSETS_DIR/decapod-flow
print_msg "...Done"

print_msg "Downloading TKS flow"
git clone --quiet https://$GITHUB_TOKEN@github.com/openinfradev/tks-flow $ASSETS_DIR/tks-flow
print_msg "...Done"

cd $ASSETS_DIR
[ ! -L bootstrap-kubeadm ] && ln -s cluster-api bootstrap-kubeadm
[ ! -L control-plane-kubeadm ] && ln -s cluster-api control-plane-kubeadm

case $CAPI_INFRA_PROVIDER in
        "aws")
		[ ! -L infrastructure-aws ] && ln -s cluster-api-provider-aws infrastructure-aws
		;;
	"openstack")
		[ ! -L infrastructure-openstack ] && ln -s cluster-api-provider-openstack infrastructure-openstack
		;;
esac
cd -
