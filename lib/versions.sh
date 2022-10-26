ARGOWF_VERSION="v3.3.9"
ARGOCD_VERSION="v2.4.10"
ARGOCD_CHART_VERSION="4.10.7"

CAPI_RELEASE="v1beta1"
case $CAPI_RELEASE in
        "v1beta1")
                CAPI_VERSION="v1.2.1"
                CAPA_VERSION="v1.5.0"
                BYOH_VERSION="v0.3.0"
                ;;
esac

KIND_NODE_IMAGE_TAG="v1.24.6@sha256:97e8d00bc37a7598a0b32d1fabd155a96355c49fa0d4d4790aab0f161bf31be1"
