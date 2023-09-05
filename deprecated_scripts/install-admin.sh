#!/bin/bash
set -e

confirm() {
  echo $1
  read -p "계속 진행하시겠습니까?(y/n) : " name
  [[ $name == 'y' ]] && clear || exit -1
}
BASEDIR=`pwd`/

# clone batch files
[[ -d "${BASEDIR}tks-mgmt-cluster-deploy" ]] && echo 'skip git clone'|| git clone https://github.com/openinfradev/tks-mgmt-cluster-deploy.git -b release-v2
cd tks-mgmt-cluster-deploy/

# prepare definitions for the target
PAM=$1
while [ -z $PAM ] || [ ! -f ${BASEDIR}$PAM  ] 
do
  echo "넘겨받은 파일 - ${BASEDIR}$PAM - 이 없어요.."
  echo 'ssh key는 aws의 해당 지점에 준비되어야 하며 key 파일도 로컬에 준비되어야 합니다.'
  read -p 'aws에서 생성한 ssh key 파일을 입력하세요.(type q to exit) : ' PAM
  [[ $PAM == 'q' ]] && exit -1
done

confirm  '접근 정보가 필요합니다. (aws, github)
- Admin Cluster 설치 Region}
- AWS ACCESS KEY ID
- AWS ACESS KEY}
- GITHUB USERNAME
- GITHUB TOKEN'

read -p "AWS_REGION={Admin Cluster 설치 Region}?: " AWS_REGION
read -p "AWS_ACCESS_KEY_ID={AWS ACCESS KEY ID?: " AWS_ACCESS_KEY
read -p "AWS_SECRET_ACCESS_KEY={AWS ACESS KEY}?: " AWS_SECRET_KEY
read -p "GIT_SVC_USERNAME={ex. demo-dacapod10}?: " GIT_SVC_USERNAME
read -p "GIT_SVC_TOKEN={TOKEN}?: " GIT_SVC_TOKEN

echo "TKS_RELEASE=release-v2

CAPI_INFRA_PROVIDER="aws" # aws or openstack
# when 'aws' is an infrastructure provider
AWS_REGION=$AWS_REGION
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY

GIT_SVC_USERNAME=$GIT_SVC_USERNAME
GIT_SVC_TOKEN=$GIT_SVC_TOKEN" > conf.sh

# value override on
echo "
sshKeyName: $PAM

cluster:
  name: admin-test
  region: $AWS_REGION
  kubernetesVersion: v1.22.8
  podCidrBlocks:
  - 192.168.0.0/16
  bastion:
    enabled: true
    instanceType: t3.micro
  baseOS: ubuntu-20.04

kubeadmControlPlane:
  replicas: 3
  controlPlaneMachineType: t3.large
  rootVolume:
    size: 20
    type: gp2

machinePool:
- name: mp
  machineType: t3.2xlarge
  replicas: 3
  minSize: 1
  maxSize: 10
  rootVolume:
    size: 200
    type: gp2
  subnets: []
  labels:
    taco-tks: enabled
" > helm-values/aws-admin.vo


confirm 'Artifcat 생성: "asset-YYYY-MM-DD" Directory 생성됨'
./01_prepare_assets.sh
confirm 'K3S install';
ASSETS_DIR=$(ls -d assets-*)
./02_create_bootstrap_cluster.sh $ASSETS_DIR
confirm 'K3S에 Cluster API for AWS 설치'
./03_initialize_capi_providers.sh $ASSETS_DIR
confirm 'AWS에 Admin Cluster로 사용한 K8S Cluster를 생성'
./04_create_tks-admin_cluster.sh $ASSETS_DIR ./helm-values/aws-admin.vo
confirm 'Admin Cluster에 Decapod 설치'
./05_install_decapod.sh $ASSETS_DIR
confirm 'Admin Cluster에 Keycloak 설치'
./05_z1_install_keycloak.sh
confirm 'Admin Clyster에 Ingress Controller설치'
./05_z2_install_nginx_ingress.sh
confirm 'Admin Clutser가 스스로를 Cluster API로 management하게 Pivoting'
./06_make_tks-admin_self-managing.sh ${BASEDIR}$PAM
