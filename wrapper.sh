#!/bin/bash
confirm() {
  echo $1
  read -p "계속 진행하시겠습니까?(y/n) : " name
  [[ $name == 'y' ]] && clear || exit -1
}


PAM=$1
while [ ! -f $PAM ] 
do
  echo 'ssh key는 aws의 해당 지점에 준비되어야 하며 key 파일도 로컬에 준비되어야 합니다.'
  read -p 'aws에서 생성한 ssh key 파일을 입력하세요.(type q to exit) : ' PAM
  [[ $PAM == 'q' ]] && exit -1
done

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
./06_make_tks-admin_self-managing.sh  $PAM
