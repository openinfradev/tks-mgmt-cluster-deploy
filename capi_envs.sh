declare -A INFRA_PROVIDER_NS
INFRA_PROVIDER_NS=(
  [aws]="capa-system"
  [byoh]="byoh-system"
)

declare -A CAPI_CHART_DIR
CAPI_CHART_DIR=(
  [aws]="taco-helm/cluster-api-aws"
  [byoh]="taco-helm/cluster-api-byoh"
)
