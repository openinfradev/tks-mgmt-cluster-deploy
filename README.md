# 관리 클러스터 (Admin/Mgmt Cluster) 구성 자동화

cluster-api를 활용한 kubernetes Cluster 배포시 필요한 관리 클러스터 구성을 자동화
* Single Bootstrap VM으로부터 Self-managed TACO management cluster 구축

## Prerequisite for a bootstrap VM
* Ubuntu 배포본만 지원 (20.04)
* Bastion 호스트 접근을 위한 ssh 개인 키(~/.ssh/id_rsa): cluster-api manifest에 설정된 것과 동일
* Infrastructure Provider 별 필요/준비 사항
  * OpenStack 서비스 접근을 위한 clouds.yaml 파일, 네트워크 및 DNS 등 설정
  * AWS 서비스 접근을 위한 키

## 절차
1. Bootstrap VM 생성 및 설정
1. 01_prepare_assets.sh: assets-DATE 디렉토리에 구성에 필요한 바이너리, manifest 파일들을 다운로드
1. 설정 파일 및 Helm Chart Value 설정: conf.sh, cluster-api-aws/openstack, keycloak
1. 02_create_bootstrap_cluster.sh: Bootstrap 클러스터 구성
1. 03_initialize_capi_providers.sh: cluster-api 컴포넌트 (CRD, Controller) 설치
1. 04_create_tks-admin_cluster.sh: 관리 클러스터 생성
1. 05_install_decapod.sh: Decapod 실행을 위한 Argo Workflow/CD, PostgreSQL 설치 (Decapod-bootstrap)
1. 05_z1_install_keycloak.sh: Keycloak 설치 (추후 Decapod으로 변경)
1. 05_z2_install_nginx_ingress.sh: NGINX Ingress 컨트롤러 설치 (추후 Decapod으로 변경)
1. 06_make_tks-admin_self-managing.sh: cluster-api 자원을 관리 클러스터로 이관하여 self-managing 클러스터로 구성

다음의 두 절차는 Admin 클러스터 노드 접근이 필요한 부분이 있어 Bastion 호스트에서 수행한다.
1. 10_pre_install_lma.sh: LMA 구성에 필요한 사전 절차 수행
1. 11_pre_install_service_mesh.sh: Service Mesh 구성에 필요한 사전 절차 수행

## TODO
* Air gap 환경 설치를 위한 컨테이너 이미지 구성

