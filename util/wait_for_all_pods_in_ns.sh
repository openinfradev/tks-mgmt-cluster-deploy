#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source $SCRIPT_DIR/../lib/log.sh

[ $# -eq 1 ] || log_error "$0 needs a namespace argument"

kubectl get ns $1 > /dev/null
[ $? -eq 0 ] || log_error "namespace $1 is not exist"

i=0
while true; do
	NUM_PODS=$(kubectl get po -n $1 --no-headers | wc -l)

	[[ $NUM_PODS -eq 0 ]] || break
	[[ $i -lt 10 ]] || log_error "there is no pods in the $1 namespace"

	((i++))
	sleep 2
done

kubectl get po -n $1 -o jsonpath='{.items[*].metadata.name}' | xargs kubectl wait --for=condition=Ready -n $1 --timeout=600s po $po > /dev/null
