K3S_VERSION="latest"
ARGOWF_VERSION="v3.2.6"
ARGOCD_VERSION="v2.2.5"
ARGOCD_CHART_VERSION="3.33.6"

CAPI_RELEASE="v1beta1"
case $CAPI_RELEASE in
        "v1alpha3")
                CAPI_VERSION="v0.3.22"
                CAPA_VERSION="v0.6.7"
                CAPO_VERSION="v0.3.4"
                ;;
        "v1alpha4")
                CAPI_VERSION="v0.4.0"
                CAPA_VERSION="v0.7.0"
                CAPO_VERSION="v0.4.0"
                ;;
        "v1beta1")
                CAPI_VERSION="v1.1.3"
                CAPA_VERSION="v1.3.0"
                BYOH_VERSION="v0.2.0"
                ;;
esac
