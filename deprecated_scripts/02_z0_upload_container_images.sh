#!/bin/bash

set -e

source lib/common.sh
if [ $# -ne 2 ]
then
  echo "usage: $0 <assets dir> <container image registry>"
  exit 1
fi

if [ $(sudo docker images | wc -l) -ne 0 ]; then
        log_warn "docker images are already exist"
        gum confirm "Are you sure you want to include the images and proceed?" || exit 1
fi

ASSETS_DIR=$1
REGISTRY=$2
cd $ASSETS_DIR/decapod-image

ls -1 *.gz | xargs --no-run-if-empty -L 1 docker load -i

# kube-webhook-certgen
for i in  `docker images | grep -v ${REGISTRY} | grep -v REPOSITORY | grep -v kube-webhook-certgen | grep -v '<none>' | awk '{print $1":"$2}' `
do
  docker tag $i ${REGISTRY}/"${i##*/}"
  docker push ${REGISTRY}/"${i##*/}"
done
