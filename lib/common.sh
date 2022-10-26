#!/usr/bin/env bash

source conf.sh
source lib/versions.sh
source lib/log.sh

check_if_supported_os() {
        source <(sed 's/^/OS_/g' /etc/os-release)

        case $OS_ID in
                "rocky" | "centos" | "rhel")
                        if [[ $OS_REDHAT_SUPPORT_PRODUCT_VERSION == "8" ]]; then
                                true
                        else
                                false
                        fi
                        ;;
                "ubuntu")
                        if [[ $OS_VERSION_ID == "20.04" ]]; then
                                true
                        else
                                false
                        fi
                        ;;
                *)
                        false
                        ;;
        esac
}
