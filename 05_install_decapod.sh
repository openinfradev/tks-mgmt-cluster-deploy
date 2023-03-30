#!/bin/bash

set -e

source lib/common.sh

if [ -z "$1" ] || [ -z "$2" ]
  then
    echo "usage: $0 <assets dir> <values.yaml for admin cluster>"
    exit 1
fi


ASSET_DIR=$1
HELM_VALUE_FILE=$2
export KUBECONFIG=~/.kube/config
CLUSTER_NAME=$(kubectl get cluster -o=jsonpath='{.items[0].metadata.name}')
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function github_create_repo() {
	echo $GIT_SVC_TOKEN | gh auth login --with-token
	echo "===== Current repo list ====="
	gh repo list openinfradev | grep decapod-site
	gh repo list ${GIT_SVC_USERNAME}

	echo "===== Create and initialize ${GIT_SVC_USERNAME}/${CLUSTER_NAME} site and manifests repositories ====="
	gh repo create ${GIT_SVC_USERNAME}/${CLUSTER_NAME} --public --confirm

	cd ${CLUSTER_NAME}
	echo -n ${GIT_SVC_TOKEN} | gh secret set API_GIT_SVC_TOKEN_GITHUB
}

function gitea_create_repo() {
	curl -X 'POST' $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/api/v1/orgs/${GIT_SVC_USERNAME}/repos?token=${GIT_SVC_TOKEN} -H 'accept: application/json' -H 'Content-Type: application/json' -d "{ \"name\": \"${CLUSTER_NAME}\"}"
	curl -X 'POST' $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/api/v1/orgs/${GIT_SVC_USERNAME}/repos?token=${GIT_SVC_TOKEN} -H 'accept: application/json' -H 'Content-Type: application/json' -d "{ \"name\": \"${CLUSTER_NAME}-manifests\"}"
	curl -X 'POST' $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/api/v1/orgs/${GIT_SVC_USERNAME}/repos?token=${GIT_SVC_TOKEN} -H 'accept: application/json' -H 'Content-Type: application/json' -d "{ \"name\": \"decapod-bootstrap\"}"

	export ARGO_GIT_SVC_TOKEN="Bearer $(kubectl -n argo get secret $SA_GIT_SVC_TOKEN -o=jsonpath='{.data.token}' | base64 --decode)"
	curl -X 'POST' \
		"${GIT_SVC_HTTP}://${GIT_SVC_BASE_URL}/api/v1/repos/${GIT_SVC_USERNAME}/${CLUSTER_NAME}/hooks?token=${GIT_SVC_TOKEN}" \
		-H 'accept: application/json' \
		-H 'Content-Type: application/json' \
		-d "{
			\"active\": true,
			\"branch_filter\": \"main\",
			\"config\": {
			\"content_type\": \"json\",
			\"url\": \"http://argo-workflows-operator-server.argo:2746/api/v1/events/argo/gitea-webhook\"
		},
		\"events\": [
		\"push\"
		],
		\"type\": \"gitea\",
		\"authorization_header\": \"${ARGO_GIT_SVC_TOKEN}\"
	}"
}

function create_admin_cluster_repo() {
	if [ "$GIT_SVC_TYPE" = "gitea" ];then
		gitea_create_repo
	else
		GIT_SVC_HTTP=${GIT_SVC_URL%://*}
		GIT_SVC_BASE_URL=${GIT_SVC_URL#*//}

		github_create_repo
	fi

	git clone -b ${TKS_RELEASE} $GIT_SVC_HTTP://$(echo -n $GIT_SVC_TOKEN)@${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/decapod-site.git
	cd decapod-site
	echo "Decapod Site Repo Revision: "${TKS_RELEASE} > META
	echo "Decapod Site Repo Commit: "$(git rev-parse HEAD) >> META

	rm -rf .github

	case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
		"aws")
			if grep -Fq "eksEnabled: true" $SCRIPT_DIR/$HELM_VALUE_FILE;then
				TEMPLATE_NAME="eks-reference"
			else
				TEMPLATE_NAME="aws-reference"
			fi
			;;

		"byoh")
			TEMPLATE_NAME="byoh-reference"
			;;
	esac
	echo "Decapod template: $TEMPLATE_NAME" >> META

	for dir in *-reference; do
		[ "$dir" = "$TEMPLATE_NAME" ] && mv $dir $CLUSTER_NAME && continue
		rm -rf $dir
	done
	rm -rf $CLUSTER_NAME/service-mesh

	export DATABASE_HOST
	export DATABASE_PORT
	export DATABASE_USER
	export DATABASE_PASSWORD
	envsubst < $CLUSTER_NAME/decapod-controller/site-values.yaml > site-values.yaml.tmp && mv site-values.yaml.tmp $CLUSTER_NAME/decapod-controller/site-values.yaml

	git config --global user.email "taco_support@sk.com"
	git config --global user.name "SKTelecom TACO"
	git add .
	git commit -m "new repo for${CLUSTER_NAME}"

	git remote add new_admin $GIT_SVC_HTTP://$(echo -n $GIT_SVC_TOKEN)@${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/${CLUSTER_NAME}
	git push new_admin ${TKS_RELEASE}:main
	cd ..
}

function install_postgresql_on_admin_cluster() {
	export KUBECONFIG=$SCRIPT_DIR/output/kubeconfig_$CLUSTER_NAME

	kubectl create ns tks-db || true

	export DATABASE_PASSWORD
	cat templates/helm-postgresql.vo.template | envsubst > helm-values/postgresql.vo

	helm upgrade -i postgresql $ASSET_DIR/postgresql-helm/postgresql -f $SCRIPT_DIR/helm-values/postgresql.vo -n tks-db

	./util/wait_for_all_pods_in_ns.sh tks-db

	export KUBECONFIG=~/.kube/config
}

function install_gitea_on_admin_cluster() {
	export KUBECONFIG=$SCRIPT_DIR/output/kubeconfig_$CLUSTER_NAME

	kubectl create ns gitea || true

	if [ -z "$DATABASE_HOST" ]; then
		DATABASE_HOST=postgresql.tks-db.svc
	fi
	export DATABASE_HOST
	export DATABASE_PORT
	export DATABASE_USER
	export DATABASE_PASSWORD
	export GITEA_ADMIN_USER
	export GITEA_ADMIN_PASSWORD
	cat templates/helm-gitea.vo.template | envsubst > helm-values/gitea.vo

	helm upgrade -i gitea $ASSET_DIR/gitea-helm/gitea -f $SCRIPT_DIR/helm-values/gitea.vo -n gitea
	./util/wait_for_all_pods_in_ns.sh gitea

	JQ_ASSETS_DIR="$ASSET_DIR/jq/$(ls $ASSET_DIR/jq | grep jq)"
	chmod +x $JQ_ASSETS_DIR/jq-linux64

	kubectl port-forward -n gitea svc/gitea-http 3000:3000 2>&1 > /dev/null &
	GITEA_KUBECTL_PID=$!
	sleep 3

	GIT_SVC_HTTP="http"
	GIT_SVC_BASE_URL="localhost:3000"
	export GIT_SVC_TOKEN=$(curl -sH "Content-Type: application/json" -d '{"name":"tks-admin", "scopes":["repo","admin:org","admin:repo_hook","admin:org_hook","delete_repo","package","admin:application"]}' -u $GITEA_ADMIN_USER:$GITEA_ADMIN_PASSWORD http://localhost:3000/api/v1/users/$GITEA_ADMIN_USER/tokens | $JQ_ASSETS_DIR/jq-linux64 -r .sha1)
	sed -i '/GIT_SVC_TOKEN/d' $SCRIPT_DIR/conf.sh
	echo GIT_SVC_TOKEN=$GIT_SVC_TOKEN >> $SCRIPT_DIR/conf.sh

	curl -X 'POST' $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/api/v1/orgs?token=${GIT_SVC_TOKEN} -H 'accept: application/json' -H 'Content-Type: application/json' -d "{ \"username\": \"$GIT_SVC_USERNAME\" }"
	export KUBECONFIG=~/.kube/config
}

function clone_or_create_decapod_repos() {
	curl -X 'POST' $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/api/v1/repos/migrate?token=${GIT_SVC_TOKEN} -H 'accept: application/json' -H 'Content-Type: application/json' \
		-d "{
			\"clone_addr\": \"https://github.com/openinfradev/decapod-base-yaml.git\",
			\"mirror\": true,
			\"mirror_interval\": \"10m0s\",
			\"repo_name\": \"decapod-base-yaml\",
			\"repo_owner\": \"$GIT_SVC_USERNAME\",
			\"service\": \"github\",
			\"uid\": 0,
			\"wiki\": false
		}"

	curl -X 'POST' $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/api/v1/repos/migrate?token=${GIT_SVC_TOKEN} -H 'accept: application/json' -H 'Content-Type: application/json' \
		-d "{
			\"clone_addr\": \"https://github.com/openinfradev/decapod-site.git\",
			\"mirror\": true,
			\"mirror_interval\": \"10m0s\",
			\"repo_name\": \"decapod-site\",
			\"repo_owner\": \"$GIT_SVC_USERNAME\",
			\"service\": \"github\",
			\"uid\": 0,
			\"wiki\": false
		}"
}

chmod +x $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64
sudo cp $ASSET_DIR/argo-workflows/$ARGOWF_VERSION/argo-linux-amd64 /usr/local/bin/argo
chmod +x $ASSET_DIR/argo-cd/$ARGOCD_VERSION/argocd-linux-amd64
sudo cp $ASSET_DIR/argo-cd/$ARGOCD_VERSION/argocd-linux-amd64 /usr/local/bin/argocd

if [ -z "$DATABASE_HOST" ]; then
	log_info "Installing Postgresql on the admin cluster..."
	install_postgresql_on_admin_cluster
fi

if [ "$GIT_SVC_TYPE" = "gitea" ];then
	log_info "Installing Gitea on the admin cluster..."
	install_gitea_on_admin_cluster
fi

log_info "Cloning/Creating Decapod Base and Site git repos..."
clone_or_create_decapod_repos
log_info "Creating Admin cluster git repos..."
rm -rf git_tmps; mkdir git_tmps
cd git_tmps
create_admin_cluster_repo
cd ..
rm -rf git_tmps

gum spin --spinner dot --title "Rendering decapod-manifests for $CLUSTER_NAME..." -- ./util/decapod-render-manifests.sh $CLUSTER_NAME

log_info "Installing Decapod-bootstrap..."
export KUBECONFIG=$SCRIPT_DIR/output/kubeconfig_$CLUSTER_NAME
kubectl create ns argo || true

if [ "$GIT_SVC_TYPE" = "gitea" ];then
	cd $ASSET_DIR/decapod-bootstrap
	GIT_SVC_HTTP=${GIT_SVC_URL%://*}
	GIT_SVC_BASE_URL=${GIT_SVC_URL#*//}
	./generate_yamls.sh --site $CLUSTER_NAME --bootstrap-git $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/decapod-bootstrap --manifests-git $GIT_SVC_HTTP://${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/${CLUSTER_NAME}-manifests
	git config --global user.email "taco_support@sk.com"
	git config --global user.name "SKTelecom TKS"
	git add .
	git commit -m "${CLUSTER_NAME}"
	GIT_SVC_HTTP="http"
	GIT_SVC_BASE_URL="localhost:3000"
	git remote add gitea $GIT_SVC_HTTP://$(echo -n $GIT_SVC_TOKEN)@${GIT_SVC_BASE_URL}/${GIT_SVC_USERNAME}/decapod-bootstrap
	git push gitea main:main
	cd -
fi

kill $GITEA_KUBECTL_PID

helm upgrade -i argo-cd $ASSET_DIR/argo-cd-helm/argo-cd -f $ASSET_DIR/decapod-bootstrap/argocd-install/values-override.yaml -n argo
gum spin --spinner dot --title "Wait for argo CD ready..." -- util/wait_for_all_pods_in_ns.sh argo

helm upgrade -i argo-cd-apps $ASSET_DIR/argocd-apps-helm/argocd-apps -f $ASSET_DIR/decapod-bootstrap/argocd-apps-install/values-override.yaml -n argo
log_info "Wait for decapod bootstrap to finish..."
set +e
while (true); do
	kubectl get deploy -n argo argo-workflows-operator-server >/dev/null 2>&1
	status=$?

	if test $status -eq 0; then
		break
	fi
	echo -n .
	sleep 10
done
set -e
log_info "All applications for bootstrap have been installed successfully"

log_info "Creating workflow templates from decapod and tks-flow..."
kubectl apply -R -f $ASSET_DIR/decapod-flow/templates -n argo
for dir in $(ls -l $ASSET_DIR/tks-flow/ |grep "^d" | grep -v dockerfiles |awk '{print $9}'); do
	kubectl apply -R -f $ASSET_DIR/tks-flow/$dir -n argo
done

log_info "Creating configmap from tks-proto..."
kubectl create cm tks-proto -n argo --from-file=$ASSET_DIR/tks-proto/tks_pb_python -o yaml --dry-run=client | kubectl apply -f -
log_info "... done"

log_info "Creating aws secret..."
if [[ " ${CAPI_INFRA_PROVIDERS[*]} " =~ " aws " ]]; then
	argo submit --from wftmpl/tks-create-aws-conf-secret -n argo -p aws_access_key_id=$AWS_ACCESS_KEY_ID -p aws_secret_access_key=$AWS_SECRET_ACCESS_KEY -p aws_account_id=$AWS_ACCOUNT_ID -p aws_user=$AWS_USER --watch
fi

log_info "Create a Git service token secret..."
argo submit --from wftmpl/tks-create-git-svc-token-secret -n argo -p user=$GIT_SVC_GIT_SVC_USERNAME -p token=$GIT_SVC_TOKEN -p git_svc_type=$GIT_SVC_TYPE -p git_svc_url=$GIT_SVC_URL --watch

ARGOCD_PASSWD=$(kubectl -n argo get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

log_info "Run prepare-argocd workflow..."
argo submit --from wftmpl/prepare-argocd -n argo -p argo_server=argo-cd-argocd-server.argo.svc:80 -p argo_password=$ARGOCD_PASSWD --watch

log_info "Add tks-admin cluster to argocd..."

CURRENT_CONTEXT=$(kubectl config current-context)

function argocd_add_admin_cluster() {
	argocd login --plaintext $ARGOCD_SERVER:$ARGOCD_PORT --username admin --password $ARGOCD_PASSWD
	argocd cluster add $CURRENT_CONTEXT --name tks-admin -y
	argocd cluster list
}

case $TKS_ADMIN_CLUSTER_INFRA_PROVIDER in
	"aws")
		if grep -Fq "eksEnabled: true" $SCRIPT_DIR/$HELM_VALUE_FILE;then
			kubectl patch svc -n argo argo-cd-argocd-server -p  '{"spec":{"type":"LoadBalancer"}}'
			sleep 5
			ARGOCD_SERVER=$(kubectl get svc -n argo argo-cd-argocd-server -ojsonpath='{.status.loadBalancer.ingress[0].hostname}')
			set +e
			while (true); do
				nslookup $ARGOCD_SERVER >/dev/null 2>&1
				status=$?

				if test $status -eq 0; then
					break
				fi
				sleep 5
			done
			set -e

			ARGOCD_PORT=80
			argocd_add_admin_cluster
			kubectl patch svc -n argo argo-cd-argocd-server -p  '{"spec":{"type":"NodePort"}}'
		else
			ARGOCD_SERVER=localhost
			ARGOCD_PORT=30080

			kubectl port-forward -n argo svc/argo-cd-argocd-server 30080:80 2>&1 > /dev/null &
			ARGOCD_KUBECTL_PID=$!
			sleep 3
			argocd_add_admin_cluster
			kill $ARGOCD_KUBECTL_PID
		fi
		;;

	"byoh")
			ARGOCD_SERVER=$(kubectl get no -ojsonpath='{.items[0].status.addresses[?(@.type == "InternalIP")].address}')
			ARGOCD_PORT=30080
			argocd_add_admin_cluster
		;;
esac

log_info "Copying TKS admin cluster kubeconfig secret to argo namespace"
# Create TKS Kubeconfig for admin cluster
TKS_KUBECONFIG_ADMIN="$SCRIPT_DIR/output/tks-kubeconfig_$CLUSTER_NAME"
cat $KUBECONFIG | sed '/exec:/,+15d' > $TKS_KUBECONFIG_ADMIN
API_SERVER=$(grep server $TKS_KUBECONFIG_ADMIN | awk '{print tolower($2)}')
ARGOCD_CLUSTER_SECRET=$(kubectl get secret -n argo | grep ${API_SERVER#*\/\/} | awk '{print $1}')
CLIENT_TOKEN=$(kubectl get secret -n argo $ARGOCD_CLUSTER_SECRET -ojsonpath='{.data.config}' | base64 -d | $JQ_ASSETS_DIR/jq-linux64 -r .bearerToken)
echo "    token: ${CLIENT_TOKEN}" >> $TKS_KUBECONFIG_ADMIN

kubectl delete secret tks-admin-kubeconfig-secret -n argo || true
kubectl create secret generic tks-admin-kubeconfig-secret -n argo --from-file=value=$TKS_KUBECONFIG_ADMIN

log_info "...Done"
