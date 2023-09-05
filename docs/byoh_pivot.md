# BYOH 인프라 프로바이더 Pivot 과정

BYOH 인프라 프로바이더는 hostagent가 직접적으로 특정 클러스터를 바라보도록 실행되는 구조 때문에 [Pivot](https://cluster-api.sigs.k8s.io/clusterctl/commands/move#pivot)[^1]을 직접 지원하기 어렵습니다.
이를 보완하여 Self-managed 클러스터를 만들기 위해 다음의 과정을 거칩니다.
각 단계들은,
- 호스트에서 실행되는 byoh-hostagent가 어느 클러스터를 바라보고 있는 지
- Cluster API(CAPI) 자원이 어느  클러스터에서 관리되고 있는지
에 따라 구분된다고 볼 수 있습니다.

[^1]: BYOH 인프라 프로바이더 일부 자원(byoh, k8sinstallerconfigtemplates)을 제외하고 다른 Cluster API 자원(Cluster, MachineDeployment 등) 및 BYOH 인프라 프로바이더 자원 (byocluster, byom 등)은 정상적으로 이동합니다.

## 1. Interim 호스트 등록 -> 부트스트랩 클러스터 (kind)
```
===  K8S  Cluster  ===                        ===     Host     ===
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+
|  bootstrap (kind)  |                        |  Interim host    |
| ------------------ | --bootstrap-kubeconfig | ---------------- |
|                    |<------------------------*byoh-hostagent   |
|                    |                        |                  |
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+
```
Interim 호스트를 등록합니다. Interim 호스트는 byoh-hostagent가 부트스트랩 클러스터를 바라보고 있습니다.

## 2. Interim 호스트를 사용하여 어드민 클러스터 생성
```
===  K8S  Cluster  ===                        ===     Host     ===
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+
|  bootstrap (kind)  |                        |  Interim host    |
| ------------------ | --bootstrap-kubeconfig | ---------------- |
| CAPI resources     |<------------------------*byoh-hostagent   |
|  - kcp: x1         |                        |                  |
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+

+~~~~~~~~~~~~~~~~~~~~+
|    admin (CAPI)    |
| ------------------ |
|                    |
+~~~~~~~~~~~~~~~~~~~~+
| Nodes              |
|  - interim x 1     |
+~~~~~~~~~~~~~~~~~~~~+
 
```
등록된 Interim 호스트를 가지고 어드민 클러스터를 생성합니다.
이 시점에서 어드민 클러스터는 단일 노드로 구성되며 interim 호스트는 컨트롤 플레인 노드(CAPI의 KubeadmContrlPlane 자원, shortname: kcp)이지만 taint가 제거되었기 때문에 일반 POD 역시 실행될 수 있습니다.

## 3. Cluster API pivot 작업 수행
```
===  K8S  Cluster  ===                        ===     Host     ===
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+
|  bootstrap (kind)  |                        |  Interim host    |
| ------------------ | --bootstrap-kubeconfig | ---------------- |
| CAPI resources     |<------------------------*byoh-hostagent   |
|                    |                        |                  |
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+

+~~~~~~~~~~~~~~~~~~~~+
|    admin (CAPI)    |
| ------------------ |
| CAPI resources     |
|  - kcp: x1         |
+~~~~~~~~~~~~~~~~~~~~+
| Nodes              |
|  - interim x 1     |
+~~~~~~~~~~~~~~~~~~~~+
```
어드민 클러스터에 CAPI 컨트롤러들을 배포하고 Cluster API Pivot 작업을 수행합니다.

## 4. 최종 어드민 호스트 등록 --> 어드민 클러스터 (CAPI로 생성됨)
```
===  K8S  Cluster  ===                        ===     Host     ===
+--------------------+                        +------------------+
|  bootstrap (kind)  |                        |  Interim host    |
| ------------------ | --bootstrap-kubeconfig | ---------------- |
|                    |<------------------------*byoh-hostagent   |
+--------------------+                        +------------------+

+--------------------+                        +------------------+
|    admin (CAPI)    |                        |  admin host      |-+
| ------------------ | --bootstrap-kubeconfig | ---------------- | |-+
| CAPI resources     |<------------------------*byoh-hostagent   | | |
|  - kcp: x1         |                        |                  | | |
|                    |                        |                  | | |
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+ | |
| Nodes              |                         +-------------------+ |
|  - interim x 1     |                          +--------------------+
+~~~~~~~~~~~~~~~~~~~~+                            ...

```
최종 어드민 호스트들(2단계에서 생성된 어드민 클러스터를 바라보는 byoh-hostagent가 실행되는)을 등록합니다
등록하는 admin 호스트의 숫자는 Interim 호스트를 재활용하는 경우 '최종 형상(kcp 개수 + md 개수) - 1'개가 필요하며 그렇지 않은 경우 '최종 형상' 개수만큼 필요합니다.

## 5. 어드민 클러스터 계획 형상에 맞게 스펙 변경 및 클러스터 확장
```
===  K8S  Cluster  ===                        ===     Host     ===
+--------------------+                        +------------------+
|  bootstrap (kind)  |                        |  Interim host    |
| ------------------ | --bootstrap-kubeconfig | ---------------- |
|                    |<------------------------*byoh-hostagent   |
+--------------------+                        +------------------+

+--------------------+                        +------------------+
|    admin (CAPI)    |                        |  admin host      |-+
| ------------------ | --bootstrap-kubeconfig | ---------------- | |-+
| CAPI resources     |<------------------------*byoh-hostagent   | | |
|  - kcp: x3         |                        |                  | | |
|  - md for tks: x3  |                        |                  | | |
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+ | |
| Nodes              |                         +-------------------+ |
|  - interim x 1     |                          +--------------------+
|  - admin host x ?  |                            ...
+~~~~~~~~~~~~~~~~~~~~+
```
계획했던 어드민 클러스터 형상에 맞춰 컨트롤플레인(CAPI의 KubeadmContrlPlane 자원, shortname: kcp), TKS 서비스를 위한 워커 노드(CAPI의 MachineDeployment, shortname: md) 개수를 변경합니다.

## 6. Interim 노드 제거
```
===  K8S  Cluster  ===                        ===     Host     ===
+--------------------+
|  bootstrap (kind)  |
| ------------------ |
|                    |
+--------------------+

+--------------------+                        +------------------+
|    admin (CAPI)    |                        |  admin host      |-+
| ------------------ | --bootstrap-kubeconfig | ---------------- | |-|
| CAPI resources     |<------------------------*byoh-hostagent   | | |
|  - kcp: x3         |                        |                  | | |
|  - md for tks: x3  |                        |                  | | |
+~~~~~~~~~~~~~~~~~~~~+                        +------------------+ | |
| Nodes              |                         +-------------------+ |
|  - admin host x 6  |                          +--------------------+
|                    |                            ...
+~~~~~~~~~~~~~~~~~~~~+

```
Interim 호스트를 제거합니다. 필요에 따라 Interim 호스트를 최종 어드민 호스트로 등록하여 재사용 할 수 있습니다.
