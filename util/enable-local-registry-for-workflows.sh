#!/bin/bash

#set -x

LOCAL_REGISTRY="tacorepo:5000"
OFFICIAL_REGISTRIES=("k8s.gcr.io" "docker.io" "gcr.io" "ghcr.io")

change_registry_to_local() {
	for registry in ${OFFICIAL_REGISTRIES[*]}; do
		sed -i -e "s/${registry}/${LOCAL_REGISTRY}/g" $1
	done

	dockerhub_org=$(grep "image:" $1 | grep -v $LOCAL_REGISTRY | awk '{print $2}' | awk -F'/' '{print $1}' | uniq)
	for org in ${dockerhub_org}; do
		sed -i -e "s/image: ${org}/image: ${LOCAL_REGISTRY}\/$org/g" $1
	done
}

for wf in $(find $1 -name '*.yaml'); do
	change_registry_to_local $wf
done
