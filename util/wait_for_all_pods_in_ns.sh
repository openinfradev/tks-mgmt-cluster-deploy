#!/usr/bin/env bash

set -x

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source $SCRIPT_DIR/../lib/log.sh

[ $# -eq 1 ] || log_error "$0 needs a namespace argument"

kubectl get ns $1 > /dev/null
[ $? -eq 0 ] || log_error "namespace $1 is not exist"

kubectl get po -n $1 -o jsonpath='{.items[*].metadata.name}' | xargs kubectl wait --for=condition=Ready -n $1 --timeout=600s po $po > /dev/null
