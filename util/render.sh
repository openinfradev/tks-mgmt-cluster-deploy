#!/bin/bash
DECAPOD_SITE_URL=https://github.com/openinfradev/decapod-site.git
SITE_BRANCH="main"
DECAPOD_BASE_URL=https://github.com/openinfradev/decapod-base-yaml.git
BRANCH="main"
DOCKER_IMAGE_REPO="docker.io"
MANIFESTS_OUTPUT_DIR="hr-manifests"

sudo pip install pyyaml

echo "Fetch decapod-site with ${SITE_BRANCH} branch/tag........"
rm -rf /tmp/${MANIFESTS_OUTPUT_DIR} && mkdir /tmp/${MANIFESTS_OUTPUT_DIR}
rm -rf /tmp/decapod-site
git clone -b ${SITE_BRANCH} ${DECAPOD_SITE_URL} /tmp/decapod-site
if [ $? -ne 0 ]; then
  exit $?
fi

echo "Change directory to decapod-site"
cd /tmp/decapod-site

site_list=$(ls -d */ | sed 's/\///g' | grep -v 'docs' | grep -v 'offline' | grep -v 'openstack')
if [ $# -eq 1 ]; then
  BRANCH=$1
elif [ $# -eq 2 ]; then
  BRANCH=$1
  site_list=$2
fi

echo "Fetch decapod-base-yaml with ${BRANCH} branch/tag........"
rm -rf decapod-base-yaml
git clone -b ${BRANCH} ${DECAPOD_BASE_URL}
if [ $? -ne 0 ]; then
  exit $?
fi

for i in ${site_list}
do
  echo "Starting build manifests for '$i' site"

  for app in `ls $i/`
  do
    output="decapod-base-yaml/$app/$i/$app-manifest.yaml"
    mkdir decapod-base-yaml/$app/$i
    cp -r $i/$app/*.yaml decapod-base-yaml/$app/$i/

    echo "Rendering $app-manifest.yaml for $i site"
    docker run --rm -i -v $(pwd)/decapod-base-yaml/$app:/$app --name kustomize-build ${DOCKER_IMAGE_REPO}/sktcloud/decapod-render:v2.0.0 kustomize build --enable-alpha-plugins /${app}/${i} -o /${app}/${i}/${app}-manifest.yaml
    build_result=$?

    if [ $build_result != 0 ]; then
      exit $build_result
    fi

    if [ -f "$output" ]; then
      echo "[$i] Successfully Completed!"
      cp ${output} ../${MANIFESTS_OUTPUT_DIR}/
    else
      echo "[$i] Failed to render $app-manifest.yaml"
      exit 1
    fi
  done
done

echo "Delete decapod-base-yaml"
rm -rf decapod-base-yaml

