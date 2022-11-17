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

for i in `ls ${ASSETS_DIR}/decapod-image`
do
  echo sudo docker load -i $i
done 

for i in  `sudo docker images | grep -v ${REGISTRY} | awk '{print $1":"$2}'  `
do
  echo sudo docker tag $i ${REGISTRY}/"${i##*/}"
  echo sudo docker push ${REGISTRY}/"${i##*/}"
done