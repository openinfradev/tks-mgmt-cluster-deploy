#!/bin/bash

set -e

source common.sh

K3S_ASSETS_URL="https://github.com/k3s-io/k3s/releases/latest/download"
K3S_ASSETS_FILES=(k3s k3s-airgap-images-amd64.tar)
CAPI_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api/releases/latest/download"
CAPI_ASSETS_FILES=(bootstrap-components.yaml cluster-api-components.yaml clusterctl-linux-amd64 control-plane-components.yaml core-components.yaml)
CAPO_ASSETS_URL="https://github.com/kubernetes-sigs/cluster-api-provider-openstack/releases/latest/download"
CAPO_ASSETS_FILES=(infrastructure-components.yaml metadata.yaml)
YQ_ASSETS_URL="https://github.com/mikefarah/yq/releases/latest/download"
YQ_ASSETS_FILES=(yq_linux_amd64)

ASSETS_DIR="assets-`date "+%Y-%m-%d"`"

github_get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

download_assets () {
	eval url='$'$1_ASSETS_URL
	eval files='$'{$1_ASSETS_FILES[@]}

	reponame=${url%/releases*}
	reponame=${reponame##*.com/}

	print_msg "Downloading assets from $reponame"

	tag=$(github_get_latest_release $reponame)
	dest_dir=$ASSETS_DIR/$(basename $reponame)/$tag
	mkdir -p $dest_dir

	for f in ${files[@]}
	do
		curl -L "$url/$f" > $dest_dir/$f
	done
}

rm -rf  $ASSETS_DIR
mkdir $ASSETS_DIR

download_assets K3S
download_assets CAPI
download_assets CAPO
download_assets YQ

print_msg "Downloading K3S install scripts"
K3S_TAG=$(github_get_latest_release k3s-io/k3s)
curl https://get.k3s.io > $ASSETS_DIR/k3s/$K3S_TAG/install.sh

print_msg "Downloading TACO Helm chart"
git clone https://github.com/openinfradev/taco-helm.git $ASSETS_DIR/taco-helm

print_msg "Downloading Helm client"
HELM_TAGS=$(github_get_latest_release helm/helm)
curl https://get.helm.sh/helm-$HELM_TAGS-linux-amd64.tar.gz -o helm.tar.gz
tar xvfz helm.tar.gz
cp linux-amd64/helm $ASSETS_DIR
rm -rf helm.tar.gz linux-amd64

cd $ASSETS_DIR
print_msg "Downloading Calico install manifest"
curl https://docs.projectcalico.org/manifests/calico.yaml -O
cd -
