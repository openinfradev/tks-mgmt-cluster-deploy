#!/bin/bash

set -ex

source lib/common.sh

if [ -z "$1" ]
  then
    echo "usage: $0 <assets dir>"
    exit 1
fi

ASSET_DIR=$1

# "dest_filename,source_file_path,dest_dir,is_executable"
# $ASSET_DIR is appended to the source file path as a prefix
files=("kubectl,kubectl,/usr/local/bin,true")
files+=("helm,helm,/usr/local/bin,true")
files+=("argocd,argo-cd/$ARGOCD_VERSION/argocd-linux-amd64,/usr/local/bin,true")
files+=("argo,argo-workflows/$ARGOWF_VERSION/argo-linux-amd64,/usr/local/bin,true")
files+=("aws-iam-authenticator,aws-iam-authenticator/v0.5.9/aws-iam-authenticator_0.5.9_linux_amd64,/usr/local/bin,true")
files+=("clusterctl,cluster-api/$CAPI_VERSION/clusterctl-linux-amd64,/usr/local/bin,true")

function copy_file_to_dest() {
        for file in ${files[*]}; do
                dest_filename=$(echo $file | awk -F',' '{print $1}')
                src_file_path=$(echo $file | awk -F',' '{print $2}')
                dest_dir=$(echo $file | awk -F',' '{print $3}')
                is_executable=$(echo $file | awk -F',' '{print $4}')

                if [ -z $dest_filename ] || [ -z $src_file_path ] || [ -z $dest_dir ] || [ -z $is_executable ]; then
                        log_error "wrong copying file"
                fi

                sudo cp $ASSET_DIR/$src_file_path $dest_dir/$dest_filename

                if [ $is_executable == "true" ]; then
                        sudo chmod +x $dest_dir/$dest_filename
                fi
        done
}

copy_file_to_dest

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

KUBECONFIG=$(ls output/ | grep kubeconfig)
mkdir -p ~/.kube
cp output/$KUBECONFIG ~/.kube/config

kubectl get no
