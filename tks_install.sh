#!/bin/bash

set -e

if [ -z "$1" ]; then
	▏ echo "usage: $0 <values.yaml for admin cluster>"
	▏ exit 1
fi

ASSETS_DIR="assets-$(date "+%Y-%m-%d")"
ADMIN_CLUSTER_VO="${1}"

./01_prepare_assets.sh
./02_create_bootstrap_cluster.sh "${ASSETS_DIR}"
./03_initialize_capi_providers.sh "${ASSETS_DIR}"

echo "============================="
echo "Run the node registration command"
echo "============================="
echo "Run the following commands using the hostname of each node."
echo 'HOST={HOSTNAME}; ./byoh_generate_script_for_host.sh ~/.kube/config $HOST; scp output/byoh-hostagent output/install_byoh_hostagent-$HOST.sh $HOST:'
echo "----------"
echo "Run the following command on each node: enter a different role depending on the type of node you want to use"
echo './install_byoh_hostagent-{HOSTNAME}.sh --role [ admin-control-plane | admin-tks ] --skip-download'
echo "----------"
echo "=========="

gum confirm "Once you're done registering nodes, do you want to proceed with the next step?" || exit 1

./04_create_tks-admin_cluster.sh "${ASSETS_DIR}" "${ADMIN_CLUSTER_VO}"
./05_install_decapod.sh assets-2023-11-01 tks-admin-values.yaml
./z2_ install_admin_tools.sh
