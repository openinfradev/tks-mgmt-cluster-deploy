ARGOWF_VERSION="v3.4.8"
ARGOCD_VERSION="v2.7.8"
ARGOCD_CHART_VERSION="5.41.1"
ARGOCD_APPS_CHART_VERSION="1.3.0"

CAPI_RELEASE="v1beta1"
case $CAPI_RELEASE in
        "v1beta1")
                CAPI_VERSION="v1.5.0"
                CAPA_VERSION="v2.2.1"
                BYOH_VERSION="v0.5.0"
                BYOH_TKS_VERSION="v0.4.0-tks-20231017"
                ;;
esac

KIND_NODE_IMAGE_TAG="v1.25.11@sha256:227fa11ce74ea76a0474eeefb84cb75d8dad1b08638371ecf0e86259b35be0c8"
