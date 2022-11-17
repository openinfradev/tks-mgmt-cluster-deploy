if [ $# -ne 2 ]
then
  echo "usage: $0 <kubernetes cluster> <service account name>"
  exit 1
fi

# your server name goes here
server=$1 #https://localhost:6443
# the name of the service account
name=$2 #SERVICE_ACCOUNT_NAME
# the name of the namespace
namespace=default

kubectl create sa $name -n tks

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
# This role binding allows "dave" to read secrets in the "development" namespace.
# You need to already have a ClusterRole named "secret-reader".
kind: ClusterRoleBinding
metadata:
  name: cluster-${name}
subjects:
- kind: ServiceAccount
  name: ${name}
  namespace: tks
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

token_name=$(kubectl -n $namespace get serviceaccount $name -o jsonpath='{.secrets[].name}')
ca=$(kubectl -n $namespace get secret/$token_name -o jsonpath='{.data.ca\.crt}')
token=$(kubectl -n $namespace get secret/$token_name -o jsonpath='{.data.token}' | base64 --decode)
namespace=$(kubectl -n $namespace get secret/$token_name -o jsonpath='{.data.namespace}' | base64 --decode)

echo "
apiVersion: v1
kind: Config
clusters:
- name: default-cluster
  cluster:
    certificate-authority-data: ${ca}
    server: ${server}
contexts:
- name: default-context
  context:
    cluster: default-cluster
    namespace: ${namespace}
    user: ${name}
current-context: default-context
users:
- name: ${name}
  user:
    token: ${token}
" > kubeconfig