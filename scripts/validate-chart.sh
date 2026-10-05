#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository_root"

for required_command in helm kubeconform; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "error: $required_command is required" >&2
    exit 1
  fi
done

chart=./wproofreader
namespace=wsc
kubernetes_version=${KUBERNETES_VERSION:-1.27.0}
# The CRDs catalog has the schemas of custom resources. Without it, kubeconform skips
# those kinds. -ignore-missing-schemas only covers kinds that neither location has.
crds_catalog='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
kubeconform_args=(
  -strict
  -summary
  -schema-location default
  -schema-location "$crds_catalog"
  -ignore-missing-schemas
  -kubernetes-version "$kubernetes_version"
)

# Each ci/*-values.yaml file is one scenario. CI copies them to wproofreader/ci/ for chart-testing.
for values_file in ci/*-values.yaml; do
  echo "Validating $(basename "$values_file" -values.yaml)"
  helm lint "$chart" -f "$values_file"
  helm template wproofreader-app "$chart" --namespace "$namespace" -f "$values_file" |
    kubeconform "${kubeconform_args[@]}"
done
