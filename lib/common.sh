#!/usr/bin/env bash

source conf.sh
source lib/versions.sh
source lib/log.sh

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export COLORTERM=true

TKS_BYOH_CONTOLLER_IMAGE="harbor.taco-cat.xyz/cluster_api_provider_bringyourownhost/cluster-api-byoh-controller"

check_if_supported_os() {
        source <(sed 's/^/OS_/g' /etc/os-release)

        case $OS_ID in
                "rocky" | "centos" | "rhel")
                        if [[ ${OS_REDHAT_SUPPORT_PRODUCT_VERSION:0:1} == "8" ]]; then
                                true
                        else
				log_error "Unsupported OS distributions"
                                false
                        fi
                        ;;
                "ubuntu")
                        if [[ $OS_VERSION_ID == "20.04" ]] || [[ $OS_VERSION_ID == "22.04" ]]; then
                                true
                        else
				log_error "Unsupported OS distributions"
                                false
                        fi
                        ;;
                *)
                        false
                        ;;
        esac
}
