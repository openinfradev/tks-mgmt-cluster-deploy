# TACO 구독형 서비스를 위한 관리 클러스터 구성 자동화

cluster-api를 활용하여 TACO 구독형 서비스를 위한 관리 클러스터 구성을 자동화
* Single Bootstrap VM으로부터 Self-managed TACO management cluster 구축

## Prerequisite for a bootstrap VM
* Ubuntu 배포본만 지원 (20.04)
* Bastion 호스트 접근을 위한 ssh 개인 키(~/.ssh/id_rsa): cluster-api manifest에 설정된 것과 동일
* OpenStack 서비스 접근을 위한 네트워크 및 DNS 등 설정

## 절차
1. Bootstrap VM 생성 및 설정
1. 01_prepare_assets.sh: assets-DATE 디렉토리에 구성에 필요한 바이너리, manifest 파일들을 다운로드
   * airgap 환경 설치인 경우 사전 준비 과정에서 실행 
1. clouds.yaml과 cluster-api-openstack Helm chart value 파일 생성
1. 02_create_bootstrap_cluster.sh: Bootstrap 클러스터 구성
1. 03_initialize_capi_providers.sh: cluster-api 컴포넌트 (CRD, Controller) 설치
1. 04_create_taco_mgmt_cluster.sh: 관리 클러스터 생성
1. 05_install_add-ons_in_taco_mgmt.sh: 관리 클러스터에 CNI 등 설치
1. 06_make_taco_mgmt_self-managing.sh: cluster-api 자원을 관리 클러스터로 이관하여 self-managing 클러스터로 구성

## TODO
* Air gap 환경 설치를 위한 컨테이너 이미지 구성

