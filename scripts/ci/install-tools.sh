#!/usr/bin/env bash
# Download the tools that scripts/stack-test.sh needs (k3d, kubectl, helm, crane) into one
# directory and verify their checksums. Versions come from scripts/ci/versions.env.
#
# Usage: scripts/ci/install-tools.sh [directory]   (default: $STACK_TOOLS_DIR, else .tools/bin)
# Then: export PATH="<directory>:$PATH"
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=versions.env
. "$repo_root/scripts/ci/versions.env"

bin_dir=${1:-${STACK_TOOLS_DIR:-.tools/bin}}
mkdir -p "$bin_dir"
bin_dir=$(cd -- "$bin_dir" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) echo "error: unsupported OS $(uname -s)" >&2; exit 2 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "error: unsupported architecture $(uname -m)" >&2; exit 2 ;;
esac

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# verify <file> <expected sha256>
verify() {
  local actual
  actual=$(sha256 "$1")
  if [ "$actual" != "$2" ]; then
    echo "error: checksum mismatch for $(basename "$1"): expected $2, got $actual" >&2
    exit 1
  fi
}

fetch() {
  curl -fsSL --retry 3 -o "$2" "$1"
}

# k3d: one binary per platform, sha256 sums in checksums.txt
if [ ! -x "$bin_dir/k3d" ]; then
  asset="k3d-$os-$arch"
  base="https://github.com/k3d-io/k3d/releases/download/$K3D_VERSION"
  fetch "$base/$asset" "$tmp/$asset"
  fetch "$base/checksums.txt" "$tmp/k3d.sums"
  verify "$tmp/$asset" "$(awk -v a="$asset" '$2 == a || $2 == "_dist/" a {print $1}' "$tmp/k3d.sums")"
  install -m 0755 "$tmp/$asset" "$bin_dir/k3d"
fi

# kubectl: binary plus a .sha256 file
if [ ! -x "$bin_dir/kubectl" ]; then
  base="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$os/$arch/kubectl"
  fetch "$base" "$tmp/kubectl"
  verify "$tmp/kubectl" "$(curl -fsSL --retry 3 "$base.sha256" | awk '{print $1}')"
  install -m 0755 "$tmp/kubectl" "$bin_dir/kubectl"
fi

# helm: tarball plus a .sha256sum file
if [ ! -x "$bin_dir/helm" ]; then
  asset="helm-$HELM_VERSION-$os-$arch.tar.gz"
  fetch "https://get.helm.sh/$asset" "$tmp/$asset"
  verify "$tmp/$asset" "$(curl -fsSL --retry 3 "https://get.helm.sh/$asset.sha256sum" | awk '{print $1}')"
  tar -xzf "$tmp/$asset" -C "$tmp" "$os-$arch/helm"
  install -m 0755 "$tmp/$os-$arch/helm" "$bin_dir/helm"
fi

# crane: tarball, sha256 sums in checksums.txt
if [ ! -x "$bin_dir/crane" ]; then
  case "$os-$arch" in
    linux-amd64) asset=go-containerregistry_Linux_x86_64.tar.gz ;;
    linux-arm64) asset=go-containerregistry_Linux_arm64.tar.gz ;;
    darwin-amd64) asset=go-containerregistry_Darwin_x86_64.tar.gz ;;
    darwin-arm64) asset=go-containerregistry_Darwin_arm64.tar.gz ;;
  esac
  base="https://github.com/google/go-containerregistry/releases/download/$CRANE_VERSION"
  fetch "$base/$asset" "$tmp/$asset"
  fetch "$base/checksums.txt" "$tmp/crane.sums"
  verify "$tmp/$asset" "$(awk -v a="$asset" '$2 == a {print $1}' "$tmp/crane.sums")"
  tar -xzf "$tmp/$asset" -C "$tmp" crane
  install -m 0755 "$tmp/crane" "$bin_dir/crane"
fi

for tool in k3d kubectl helm crane; do
  printf '%-8s ' "$tool"
  case "$tool" in
    k3d) "$bin_dir/k3d" version | head -1 ;;
    kubectl) "$bin_dir/kubectl" version --client | head -1 ;;
    helm) "$bin_dir/helm" version --short ;;
    crane) "$bin_dir/crane" version ;;
  esac
done
echo "Tools are in $bin_dir"
