#!/bin/bash

set -e

if [ -z "$1" ]; then
        echo "usage: $0 <cluster name dir>"
        exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/../conf.sh

CLUSTER_NAME=$1
DECAPOD_RENDER_IMAGE="harbor-cicd.taco-cat.xyz/tks/decapod-render:v3.1.3"

function log() {
	level=$2
	msg=$3
	date=$(date '+%F %H:%M:%S')
	if [ $1 -eq 0 ];then
		echo "[$date] $level     $msg"
	else
		level="ERROR"
		echo "[$date] $level     $msg failed"
		exit $1
	fi
}

if [ "$GIT_SVC_TYPE" = "gitea" ];then
	GIT_SVC_HTTP="http"
	GIT_SVC_BASE_URL="localhost:3000"
else
	GIT_SVC_HTTP=${GIT_SVC_URL%://*}
	GIT_SVC_BASE_URL=${GIT_SVC_URL#*//}
fi

BASE_REPO_URL=$GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/decapod-base-yaml.git
BASE_REPO_BRANCH=main
SITE_REPO_URL=$GIT_SVC_HTTP://$(echo -n $GIT_SVC_TOKEN)@${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/${CLUSTER_NAME}
SITE_REPO_BRANCH=main
MANIFEST_REPO_URL=$GIT_SVC_HTTP://$(echo -n $GIT_SVC_TOKEN)@${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/${CLUSTER_NAME}-manifests
MANIFEST_REPO_BRANCH=main
SITE_DIR="decapod-$CLUSTER_NAME-site"
BASE_DIR="decapod-base-yaml"
OUTPUT_DIR="decapod-manifests-output"

sudo rm -rf tmp-decapod
mkdir tmp-decapod
cd tmp-decapod

# download site-yaml
git clone -b ${SITE_REPO_BRANCH} ${SITE_REPO_URL} ${SITE_DIR}
log $? "INFO" "Fetching ${SITE_REPO_URL} with ${SITE_REPO_BRANCH} branch/tag........."
cd ${SITE_DIR}
site_commit_msg=$(git show -s --format="[%h] %s" HEAD)
site_commit_id=$(git show -s --format="%h" HEAD)

# extract directory for rendering
site_list=$(ls -d */ | sed 's/\///g' | egrep -v "docs|^template|^deprecated|output|offline")

# download base-yaml
git clone -b ${BASE_REPO_BRANCH} ${BASE_REPO_URL} ${BASE_DIR}
log $? "INFO" "Fetching ${BASE_REPO_URL} with ${BASE_REPO_BRANCH} branch/tag........."
base_commit_msg=$(cd ${BASE_DIR}; git show -s --format="[%h] %s" HEAD)

mkdir -p ${OUTPUT_DIR}

for site in ${site_list}
do
	log 0 "INFO" "Starting build manifests for '${site}' site"
	for app in `ls ${site}/`
	do
		hr_file="${BASE_DIR}/${app}/${site}/${app}-manifest.yaml"
		mkdir -p ${BASE_DIR}/${app}/${site}
		cp -r ${site}/${app}/*.yaml ${BASE_DIR}/${app}/${site}/

		log 0 "INFO" ">>>>>>>>>> Rendering ${app}-manifest.yaml for ${site} site"
		sudo docker run --rm -i \
			--name kustomize-build \
			--mount type=bind,source="$(pwd)"/${BASE_DIR},target=/${BASE_DIR} \
			$DECAPOD_RENDER_IMAGE \
			kustomize build --enable-alpha-plugins /${BASE_DIR}/${app}/${site} -o /${BASE_DIR}/${app}/${site}/${app}-manifest.yaml
		log $? "INFO" "run kustomize build"

		if [ -f "${hr_file}" ]; then
			log 0 "INFO" "[${hr_file}] Successfully Generate Helm-Release Files!"
		else
			log 1 "ERROR" "[${hr_file}] Failed to render manifest yaml"
		fi

		sudo docker run --rm -i \
			--name generate-manifests \
			--mount type=bind,source="$(pwd)"/${BASE_DIR},target=/${BASE_DIR} \
			--mount type=bind,source="$(pwd)"/${OUTPUT_DIR},target=/${OUTPUT_DIR} \
			$DECAPOD_RENDER_IMAGE \
			helm2yaml -m /${hr_file} -t -o /${OUTPUT_DIR}/${site}/${app}
	
		log 0 "INFO" "Successfully Generate ${app} manifests Files!"

		rm -f $hr_file

	done
done

#-----------------------------------------------
# push manifests files
#-----------------------------------------------
git clone ${MANIFEST_REPO_URL} origin-manifests
log 0 "INFO" "git clone ${MANIFEST_REPO_URL}"
cd origin-manifests
if [ -z "${MANIFEST_REPO_BRANCH}" ]; then
	MANIFEST_REPO_BRANCH="decapod-${site_commit_id}"
fi
check_branch=$(git ls-remote --heads origin ${MANIFEST_REPO_BRANCH})
if [[ -z ${check_branch} ]]; then
	git checkout -b ${MANIFEST_REPO_BRANCH}
	log 0 "INFO" "create and checkout new branch: ${MANIFEST_REPO_BRANCH}"
else
	git checkout ${MANIFEST_REPO_BRANCH}
	log 0 "INFO" "checkout exist branch: ${MANIFEST_REPO_BRANCH}"
fi

rm -rf ./*
cp -r ../${OUTPUT_DIR}/* ./

git config --global user.email "taco_support@sk.com"
git config --global user.name "SKTelecom TACO"
git add -A
git commit -m "base: ${base_commit_msg}, site: ${site_commit_msg}"
git push origin ${MANIFEST_REPO_BRANCH}

log 0 "INFO" "pushed all manifests files"

cd $SCRIPT_DIR
rm -rf tmp-decapod
