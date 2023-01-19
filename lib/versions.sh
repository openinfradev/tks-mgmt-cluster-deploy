ARGOWF_VERSION="v3.4.2"
ARGOCD_VERSION="v2.4.11"
ARGOCD_CHART_VERSION="4.10.9"

CAPI_RELEASE="v1beta1"
case $CAPI_RELEASE in
        "v1beta1")
                CAPI_VERSION="v1.3.2"
                CAPA_VERSION="v2.0.2"
                BYOH_VERSION="v0.3.1"
                ;;
esac

KIND_NODE_IMAGE_TAG="v1.24.6@sha256:97e8d00bc37a7598a0b32d1fabd155a96355c49fa0d4d4790aab0f161bf31be1"
