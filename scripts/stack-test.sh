#!/usr/bin/env bash
# Stack test: install the WProofreader stack on a throwaway Kubernetes cluster and check it.
#
# Order: MySQL (mysql-server-helm), WProofreader Server with the db-manager provisioning Job
# (the chart of this repository), and optionally Admin-panel (admin-panel-helm). Release names,
# Secret names and keys are the same as in the Kubernetes installation guide.
# Each chart comes from a local directory (path:<dir>) or from a release tag (tag:<vX.Y.Z>).
# Defaults: the wproofreader chart of this repository, and the MySQL and Admin-panel chart
# tags in scripts/ci/versions.env.
#
# Without stage names the script runs all stages, writes diagnostics when a check fails,
# and deletes the cluster at the end. With stage names it runs only those stages, so that a
# CI system can show each stage as its own step. The stages share their state through
# a private file in STACK_STATE_DIR; run "preflight" first and "teardown" last.
#
# Exit codes: 0 all checks passed, 1 a check failed, 2 a precondition failed.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/stack-test.sh [options] [stage...]

Stages (default: all of them, in this order):
  preflight      check the tools, the license, the chart sources, and the images
  cluster        create the k3d cluster (or use the current context) and the namespace
  secrets        create the Secrets with random passwords
  mysql          install MySQL and check it
  wproofreader   install WProofreader Server with the db-manager Job and check it
  admin-panel    install Admin-panel and check it (skipped without --admin-panel)
  upgrade        upgrade each release with the same values
  diagnostics    write Pod logs, events, and release status to the diagnostics directory
  teardown       delete the cluster (or the namespace) and the state

Charts (path:<dir> | tag:<vX.Y.Z>):
  --mysql SOURCE            mysql-server-helm chart (default: MYSQL_CHART_TAG in scripts/ci/versions.env)
  --wproofreader SOURCE     wproofreader-helm chart (default: the wproofreader chart of this repository)
  --admin-panel SOURCE      admin-panel-helm chart, or "none" (default: none)

Images:
  --wproofreader-version V  WProofreader Server and db-manager image tag (N.N.N.N).
                            Default: the appVersion of the wproofreader chart.
  --admin-panel-version V   Admin-panel image tag. Default: the chart appVersion.

Cluster:
  --cluster k3d|existing    k3d (default) creates a cluster and deletes it at the end.
                            existing uses the current KUBECONFIG context; the namespace
                            must not exist, and the script deletes only that namespace.
  --namespace NAME          default: wsc
  --keep                    keep the cluster (or namespace) at teardown
  --diag-dir DIR            diagnostics output directory (default: diag)
  --preload-images          pull the images with the local Docker and import them into k3d
                            (local runs on a slow connection; the Docker cache stays between runs)

The chart, image, and cluster options apply to the preflight stage; later stages read them
from the state.

Environment:
  WPR_LICENSE_TICKET_ID     license ticket ID (required: without a license the server never gets ready)
  DOCKERHUB_USERNAME, DOCKERHUB_TOKEN   authenticated Docker Hub pulls (k3d only)
  GITHUB_TOKEN              token for tag: sources of private chart repositories
  STACK_STATE_DIR           state directory (default: .stack-test); it holds the passwords
  STACK_TOOLS_DIR           directory of scripts/ci/install-tools.sh, put first in PATH
EOF
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=ci/versions.env
. "$repo_root/scripts/ci/versions.env"
[ -z "${STACK_TOOLS_DIR:-}" ] || PATH="$STACK_TOOLS_DIR:$PATH"

all_stages="preflight cluster secrets mysql wproofreader admin-panel upgrade"

# Options. The preflight stage saves them in the state; the other stages load them from it.
opt_mysql=""
opt_wpr=""
opt_ap=none
opt_wpr_version=""
opt_ap_version=""
opt_cluster=k3d
opt_namespace=wsc
opt_keep=""
opt_diag_dir=""
opt_preload=false
stages=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mysql) opt_mysql=$2; shift 2 ;;
    --wproofreader) opt_wpr=$2; shift 2 ;;
    --admin-panel) opt_ap=$2; shift 2 ;;
    --wproofreader-version) opt_wpr_version=$2; shift 2 ;;
    --admin-panel-version) opt_ap_version=$2; shift 2 ;;
    --cluster) opt_cluster=$2; shift 2 ;;
    --namespace) opt_namespace=$2; shift 2 ;;
    --keep) opt_keep=true; shift ;;
    --diag-dir) opt_diag_dir=$2; shift 2 ;;
    --preload-images) opt_preload=true; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) stages="$stages $1"; shift ;;
  esac
done

state_dir=${STACK_STATE_DIR:-.stack-test}
state_file="$state_dir/state.env"

# ---------------------------------------------------------------------------- helpers

in_teamcity() { [ -n "${TEAMCITY_VERSION:-}" ]; }

current_stage=""
begin() {
  current_stage=$1
  printf '\n==> %s\n' "$current_stage"
}

info() { printf '    %s\n' "$*"; }
ok() { printf '    ok: %s\n' "$*"; }

fail() {
  echo "FAIL [$current_stage]: $*" >&2
  if in_teamcity; then
    local text=${*//\'/|\'}
    echo "##teamcity[buildProblem description='$current_stage: $text']"
  fi
  exit 1
}

precondition() {
  echo "ERROR: $*" >&2
  exit 2
}

need() {
  command -v "$1" >/dev/null 2>&1 || precondition "$1 is required (scripts/ci/install-tools.sh installs it)"
}

random_password() { openssl rand -hex 16; }

# State: shell assignments in a file only the current user can read.
state_vars="cluster_mode namespace keep diag_dir preload mysql_chart wpr_chart ap_chart wpr_version ap_version
  expected_wpr_version expected_ap_version mysql_host wpr_url cluster_name cluster_created namespace_created
  kubeconfig_file mysql_root_password admin_panel_db_password appserver_db_password service_db_password"

save_state() {
  local var
  (
    umask 077
    for var in $state_vars; do
      printf '%s=%q\n' "$var" "${!var:-}"
    done >"$state_file"
  )
}

load_state() {
  [ -f "$state_file" ] || precondition "no state in $state_dir; run the preflight stage first"
  # shellcheck disable=SC1090
  . "$state_file"
  [ -z "$opt_keep" ] || keep=true
  [ -z "$opt_diag_dir" ] || diag_dir=$opt_diag_dir
  if [ -n "$kubeconfig_file" ]; then
    export KUBECONFIG=$kubeconfig_file
  fi
}

# resolve_chart <repository> <chart directory> <source>: prints the chart path
resolve_chart() {
  local repo=$1 dir=$2 src=$3 tag dest auth
  case "$src" in
    path:*)
      [ -f "${src#path:}/Chart.yaml" ] || precondition "no Chart.yaml in ${src#path:}"
      (cd -- "${src#path:}" && pwd)
      ;;
    tag:*)
      tag=${src#tag:}
      dest="$state_dir/charts/$repo"
      info "cloning $repo at $tag" >&2
      if [ -n "${GITHUB_TOKEN:-}" ]; then
        # The token goes in a header, so it is not stored in the clone or printed in errors.
        auth=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')
        git -c advice.detachedHead=false -c "http.https://github.com/.extraHeader=Authorization: Basic $auth" \
          clone --quiet --depth 1 --branch "$tag" "https://github.com/WebSpellChecker/$repo.git" "$dest" >&2 \
          || precondition "cannot clone $repo at $tag"
      else
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" \
          "https://github.com/WebSpellChecker/$repo.git" "$dest" >&2 \
          || precondition "cannot clone $repo at $tag (set GITHUB_TOKEN for a private repository)"
      fi
      (cd -- "$dest/$dir" && pwd)
      ;;
    *) precondition "chart source must be path:<dir> or tag:<vX.Y.Z>, not $src" ;;
  esac
}

app_version() { awk '/^appVersion:/ {gsub(/"/, "", $2); print $2; exit}' "$1/Chart.yaml"; }
chart_version() { awk '/^version:/ {print $2; exit}' "$1/Chart.yaml"; }

# in_cluster_run <name> <image> <command...>: run a one-off Pod and print its output.
# The output is read with kubectl logs after the Pod ends: `kubectl run --attach` can miss
# the output of a container that ends in less than a second.
in_cluster_run() {
  local pod="$1-$RANDOM" image=$2 phase="" waited=0 output
  shift 2
  kubectl -n "$namespace" run "$pod" --restart=Never --image="$image" \
    --image-pull-policy=IfNotPresent --command -- "$@" >/dev/null
  while [ "$waited" -lt 300 ]; do
    phase=$(kubectl -n "$namespace" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case "$phase" in Succeeded | Failed) break ;; esac
    sleep 2
    waited=$((waited + 2))
  done
  output=$(kubectl -n "$namespace" logs "$pod" 2>&1 || true)
  kubectl -n "$namespace" delete pod "$pod" --wait=false >/dev/null 2>&1 || true
  if [ "$phase" != Succeeded ]; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  printf '%s\n' "$output"
}

mysql_query() { # <user> <password> <database> <sql>
  in_cluster_run mysql-check mysql:8.4 \
    sh -c 'MYSQL_PWD="$1" mysql -h "$2" -u "$3" -N -B -e "$5" "$4"' sh "$2" "$mysql_host" "$1" "$3" "$4"
}

# ---------------------------------------------------------------------------- stages

stage_preflight() {
  begin "Preflight"
  local tool image
  for tool in kubectl helm git openssl awk; do need "$tool"; done
  case "$opt_cluster" in k3d | existing) ;; *) precondition "--cluster must be k3d or existing" ;; esac
  [ "$opt_cluster" = existing ] || need k3d
  [ -n "${WPR_LICENSE_TICKET_ID:-}" ] \
    || precondition "WPR_LICENSE_TICKET_ID is not set; WProofreader Server does not get ready without a license"
  if [ -n "$opt_wpr_version" ] && ! [[ "$opt_wpr_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    precondition "--wproofreader-version must look like 6.18.1.0, not $opt_wpr_version"
  fi
  helm version --short
  kubectl version --client | head -1
  [ "$opt_cluster" = existing ] || k3d version | head -1

  # A new run starts with a new state. Remove only a directory that this script made.
  if [ -d "$state_dir" ] && [ -n "$(ls -A "$state_dir")" ] && [ ! -f "$state_file" ]; then
    precondition "$state_dir is not empty and holds no stack test state; set STACK_STATE_DIR"
  fi
  rm -rf "$state_dir"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  state_dir=$(cd -- "$state_dir" && pwd)
  state_file="$state_dir/state.env"

  cluster_mode=$opt_cluster
  namespace=$opt_namespace
  keep=${opt_keep:-false}
  diag_dir=${opt_diag_dir:-diag}
  preload=$opt_preload
  wpr_version=$opt_wpr_version
  ap_version=$opt_ap_version
  cluster_name=""
  cluster_created=false
  namespace_created=false
  kubeconfig_file=""

  mysql_chart=$(resolve_chart mysql-server-helm mysql "${opt_mysql:-tag:$MYSQL_CHART_TAG}")
  wpr_chart=$(resolve_chart wproofreader-helm wproofreader "${opt_wpr:-path:$repo_root/wproofreader}")
  ap_chart=""
  [ "$opt_ap" = none ] || ap_chart=$(resolve_chart admin-panel-helm admin-panel "$opt_ap")

  expected_wpr_version=${wpr_version:-$(app_version "$wpr_chart")}
  expected_ap_version=""
  info "mysql chart $(chart_version "$mysql_chart") from $mysql_chart"
  info "wproofreader chart $(chart_version "$wpr_chart") from $wpr_chart, WProofreader Server $expected_wpr_version"
  if [ -n "$ap_chart" ]; then
    expected_ap_version=${ap_version:-$(app_version "$ap_chart")}
    info "admin-panel chart $(chart_version "$ap_chart") from $ap_chart, Admin-panel $expected_ap_version"
  else
    info "admin-panel: skipped"
  fi

  # The chart runs db-manager with the same tag as WProofreader Server, so both images must exist.
  if command -v crane >/dev/null 2>&1; then
    for image in "webspellchecker/wproofreader:$expected_wpr_version" "webspellchecker/db-manager:$expected_wpr_version"; do
      crane digest "docker.io/$image" >/dev/null 2>&1 || precondition "image $image is not on Docker Hub"
      ok "$image exists"
    done
    if [ -n "$ap_chart" ]; then
      crane digest "docker.io/webspellchecker/admin-panel:$expected_ap_version" >/dev/null 2>&1 \
        || precondition "image webspellchecker/admin-panel:$expected_ap_version is not on Docker Hub"
      ok "webspellchecker/admin-panel:$expected_ap_version exists"
    fi
  else
    info "crane not found: image existence is not checked before the install"
  fi

  mysql_host="mysql-primary.$namespace.svc.cluster.local"
  wpr_url="http://wproofreader-app.$namespace.svc.cluster.local/wscservice/api"
  save_state
  if in_teamcity; then
    local text="WProofreader $expected_wpr_version"
    [ -z "$ap_chart" ] || text="$text, Admin-panel $expected_ap_version"
    echo "##teamcity[buildStatus text='{build.status.text}; $text']"
  fi
}

stage_cluster() {
  begin "Cluster"
  local image images k3d_args
  if [ "$cluster_mode" = k3d ]; then
    cluster_name="stack-$(date +%H%M%S)-$RANDOM"
    k3d_args=(--image "$K3S_IMAGE" --no-lb --wait --timeout 180s
      --k3s-arg "--disable=traefik@server:*"
      --kubeconfig-update-default=false --kubeconfig-switch-context=false)
    if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
      (
        umask 077
        cat >"$state_dir/registries.yaml" <<EOF
configs:
  registry-1.docker.io:
    auth:
      username: "$DOCKERHUB_USERNAME"
      password: "$DOCKERHUB_TOKEN"
EOF
      )
      k3d_args+=(--registry-config "$state_dir/registries.yaml")
      info "Docker Hub pulls are authenticated as $DOCKERHUB_USERNAME"
    fi
    info "creating k3d cluster $cluster_name ($K3S_IMAGE)"
    cluster_created=true
    save_state
    k3d cluster create "$cluster_name" "${k3d_args[@]}" >"$state_dir/k3d.log" 2>&1 \
      || { cat "$state_dir/k3d.log" >&2; fail "k3d cluster create failed"; }
    kubeconfig_file="$state_dir/kubeconfig"
    (umask 077 && k3d kubeconfig get "$cluster_name" >"$kubeconfig_file")
    export KUBECONFIG=$kubeconfig_file
    save_state
  else
    info "using context $(kubectl config current-context)"
  fi
  kubectl wait --for=condition=Ready nodes --all --timeout=120s >/dev/null || fail "nodes are not Ready"
  kubectl -n kube-system rollout status deployment/coredns --timeout=180s >/dev/null || fail "CoreDNS is not ready"
  ok "Kubernetes $(kubectl version -o json | awk -F'"' '/"gitVersion"/ {v = $4} END {print v}') is ready"

  if [ "$preload" = true ] && [ "$cluster_mode" = k3d ]; then
    need docker
    images="webspellchecker/wproofreader:$expected_wpr_version webspellchecker/db-manager:$expected_wpr_version"
    images="$images mysql:8.4 busybox:1.36 curlimages/curl:8.22.0"
    [ -z "$ap_chart" ] || images="$images webspellchecker/admin-panel:$expected_ap_version"
    for image in $images; do
      docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null \
        || fail "docker pull $image failed"
      ok "$image is in the local Docker"
    done
    # shellcheck disable=SC2086 # one argument per image
    k3d image import --cluster "$cluster_name" $images >"$state_dir/import.log" 2>&1 \
      || { cat "$state_dir/import.log" >&2; fail "k3d image import failed"; }
    ok "images imported into the cluster"
  fi

  if kubectl get namespace "$namespace" >/dev/null 2>&1; then
    precondition "namespace $namespace already exists"
  fi
  kubectl create namespace "$namespace" >/dev/null
  namespace_created=true
  save_state
  ok "namespace $namespace created"
}

stage_secrets() {
  begin "Secrets"
  mysql_root_password=$(random_password)
  admin_panel_db_password=$(random_password)
  appserver_db_password=$(random_password)
  service_db_password=$(random_password)
  save_state
  [ -n "${WPR_LICENSE_TICKET_ID:-}" ] || precondition "WPR_LICENSE_TICKET_ID is not set"

  kubectl -n "$namespace" create secret generic mysql-credentials \
    --from-literal=mysql-root-password="$mysql_root_password" \
    --from-literal=mysql-password="$admin_panel_db_password" >/dev/null
  kubectl -n "$namespace" create secret generic wproofreader-db \
    --from-literal=root-password="$mysql_root_password" \
    --from-literal=appserver-password="$appserver_db_password" \
    --from-literal=admin-panel-password="$service_db_password" >/dev/null
  kubectl -n "$namespace" create secret generic wproofreader-license \
    --from-literal=license="$WPR_LICENSE_TICKET_ID" >/dev/null
  if [ -n "$ap_chart" ]; then
    kubectl -n "$namespace" create secret generic admin-panel-secrets \
      --from-literal=APP_KEY="base64:$(openssl rand -base64 32)" \
      --from-literal=DB_PASSWORD="$admin_panel_db_password" \
      --from-literal=SERVICE_DB_PASSWORD="$service_db_password" >/dev/null
  fi
  ok "Secrets created with random passwords"
}

stage_mysql() {
  begin "MySQL"
  local out
  helm upgrade --install mysql "$mysql_chart" -n "$namespace" \
    -f "$repo_root/ci/stack/mysql.yaml" --wait --timeout 10m >/dev/null \
    || fail "helm install mysql failed"
  ok "release mysql deployed"
  helm test mysql -n "$namespace" --timeout 5m >/dev/null || fail "helm test mysql failed"
  ok "helm test mysql passed"
  out=$(mysql_query admin_panel "$admin_panel_db_password" admin_panel_db \
    'SELECT DATABASE(), CURRENT_USER(), VERSION();') || fail "cannot log in to MySQL as admin_panel"
  info "$out"
  case "$out" in *admin_panel_db*admin_panel@%*8.4.*) ok "admin_panel can log in to admin_panel_db on MySQL 8.4" ;;
    *) fail "unexpected MySQL answer: $out" ;; esac
}

stage_wproofreader() {
  begin "WProofreader Server"
  local wpr_args succeeded server_pod api ver status license_status out
  wpr_args=(-f "$repo_root/ci/stack/wproofreader-app.yaml" --set "database.host=$mysql_host")
  if [ -n "$wpr_version" ]; then
    wpr_args+=(--set "image.tag=$wpr_version" --set "databaseProvisioning.image.tag=$wpr_version")
  fi
  helm upgrade --install wproofreader-app "$wpr_chart" -n "$namespace" "${wpr_args[@]}" \
    --wait --timeout 15m >/dev/null || {
    # The db-manager Job Pod has the same labels as the server Pod, so select the running Pod.
    server_pod=$(kubectl -n "$namespace" get pods -l app.kubernetes.io/instance=wproofreader-app \
      --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
    if [ -n "$server_pod" ] && kubectl -n "$namespace" logs "$server_pod" --tail=50 2>/dev/null | grep -q 'License is absent'; then
      fail "helm install wproofreader-app failed: the server reports 'License is absent'; check WPR_LICENSE_TICKET_ID"
    fi
    fail "helm install wproofreader-app failed"
  }
  ok "release wproofreader-app deployed"
  succeeded=$(kubectl -n "$namespace" get job wproofreader-app-db-provision -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
  [ "$succeeded" = 1 ] || fail "db-manager Job wproofreader-app-db-provision did not succeed"
  ok "db-manager Job wproofreader-app-db-provision completed"

  api=$(in_cluster_run wpr-check curlimages/curl:8.22.0 sh -c '
    for cmd in ver status license_status; do
      printf "%s=" "$cmd"
      curl -fsS --max-time 20 "$1?cmd=$cmd" || printf "ERROR"
      printf "\n"
    done' sh "$wpr_url") || fail "cannot reach WProofreader Server at $wpr_url"
  ver=$(printf '%s\n' "$api" | sed -n 's/^ver=//p')
  status=$(printf '%s\n' "$api" | sed -n 's/^status=//p')
  license_status=$(printf '%s\n' "$api" | sed -n 's/^license_status=//p')
  info "ver: $ver"
  info "status: $status"
  info "license_status: $license_status"
  case "$ver" in *"$expected_wpr_version"*) ok "version is $expected_wpr_version" ;;
    *) fail "cmd=ver does not report $expected_wpr_version" ;; esac
  case "$status" in ERROR | "") fail "cmd=status failed" ;; *) ok "cmd=status answered" ;; esac
  case "$license_status" in *'"valid":true'*) ok "license is valid" ;;
    *) fail "license is not valid" ;; esac

  out=$(mysql_query app_service "$service_db_password" cloud_service 'SELECT CURRENT_USER();') \
    || fail "app_service cannot log in to cloud_service"
  case "$out" in app_service@*) ok "db-manager created app_service with access to cloud_service" ;;
    *) fail "unexpected MySQL answer: $out" ;; esac

  if helm get hooks wproofreader-app -n "$namespace" | grep -q '"helm.sh/hook": test'; then
    helm test wproofreader-app -n "$namespace" --timeout 5m >/dev/null || fail "helm test wproofreader-app failed"
    ok "helm test wproofreader-app passed"
  else
    info "the wproofreader chart has no helm test hook"
  fi
}

stage_admin_panel() {
  begin "Admin-panel"
  if [ -z "$ap_chart" ]; then
    info "skipped (no --admin-panel chart)"
    return 0
  fi
  local ap_args component
  ap_args=(-f "$repo_root/ci/stack/admin-panel.yaml"
    --set "config.appUrl=http://admin-panel-web.$namespace.svc.cluster.local"
    --set "config.appServerUrl=$wpr_url"
    --set "config.appServerInternalUrl=$wpr_url"
    --set "config.db.host=$mysql_host"
    --set "config.serviceDb.host=$mysql_host")
  [ -z "$ap_version" ] || ap_args+=(--set "image.tag=$ap_version")
  helm lint "$ap_chart" "${ap_args[@]}" >/dev/null || fail "helm lint admin-panel failed"
  helm upgrade --install admin-panel "$ap_chart" -n "$namespace" "${ap_args[@]}" \
    --wait --timeout 10m >/dev/null || fail "helm install admin-panel failed"
  ok "release admin-panel deployed"
  for component in web worker scheduler; do
    kubectl -n "$namespace" rollout status "deployment/admin-panel-$component" --timeout=5m >/dev/null \
      || fail "deployment admin-panel-$component is not ready"
  done
  ok "web, worker and scheduler are ready"
  helm test admin-panel -n "$namespace" --timeout 5m >/dev/null || fail "helm test admin-panel failed"
  ok "helm test admin-panel passed"
  # The setup URL holds a secret token, so only its shape is checked and nothing is printed.
  kubectl -n "$namespace" exec deployment/admin-panel-web -- \
    php artisan app:setup-token --regenerate --no-ansi 2>/dev/null | grep -q 'setup?token=' \
    || fail "php artisan app:setup-token did not print a setup URL"
  ok "the first-administrator setup link can be issued"
}

stage_upgrade() {
  begin "Upgrade with the same values"
  local entry release releases
  releases="mysql:$mysql_chart wproofreader-app:$wpr_chart"
  [ -z "$ap_chart" ] || releases="$releases admin-panel:$ap_chart"
  for entry in $releases; do
    release=${entry%%:*}
    helm upgrade "$release" "${entry#*:}" -n "$namespace" --reuse-values --wait --timeout 10m >/dev/null \
      || fail "helm upgrade $release with the same values failed"
    ok "$release upgraded"
  done
}

stage_diagnostics() {
  begin "Diagnostics"
  if [ -z "${KUBECONFIG:-}" ] || ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    info "no cluster to inspect"
    return 0
  fi
  mkdir -p "$diag_dir"
  local d pod release
  d=$(cd -- "$diag_dir" && pwd)
  {
    kubectl get nodes -o wide
    kubectl get all,jobs,pvc,events -n "$namespace" -o wide
  } >"$d/resources.txt" 2>&1 || true
  kubectl describe pods -n "$namespace" >"$d/pods-describe.txt" 2>&1 || true
  kubectl get events -A --sort-by=.lastTimestamp >"$d/events.txt" 2>&1 || true
  for pod in $(kubectl get pods -n "$namespace" -o name 2>/dev/null); do
    kubectl logs -n "$namespace" "$pod" --all-containers --timestamps >"$d/logs-${pod#pod/}.txt" 2>&1 || true
    kubectl logs -n "$namespace" "$pod" --all-containers --previous >"$d/logs-${pod#pod/}-previous.txt" 2>/dev/null \
      || rm -f "$d/logs-${pod#pod/}-previous.txt"
  done
  for release in mysql wproofreader-app admin-panel; do
    helm status "$release" -n "$namespace" >"$d/helm-$release.txt" 2>&1 || { rm -f "$d/helm-$release.txt"; continue; }
    helm history "$release" -n "$namespace" >>"$d/helm-$release.txt" 2>&1 || true
  done
  ok "diagnostics written to $d"
}

stage_teardown() {
  begin "Teardown"
  if [ "$keep" = true ]; then
    info "kept: cluster ${cluster_name:-none}, namespace $namespace (KUBECONFIG=${KUBECONFIG:-})"
    return 0
  fi
  if [ "$cluster_created" = true ] && [ -n "$cluster_name" ]; then
    k3d cluster delete "$cluster_name" >/dev/null 2>&1 || info "k3d cluster delete $cluster_name failed"
    ok "cluster $cluster_name deleted"
  elif [ "$namespace_created" = true ]; then
    helm uninstall admin-panel wproofreader-app mysql -n "$namespace" >/dev/null 2>&1 || true
    kubectl delete namespace "$namespace" --wait=false >/dev/null 2>&1 || true
    ok "namespace $namespace deleted"
  else
    info "nothing to delete"
  fi
  rm -rf "$state_dir"
}

run_stage() {
  case "$1" in
    preflight) stage_preflight ;;
    cluster) stage_cluster ;;
    secrets) stage_secrets ;;
    mysql) stage_mysql ;;
    wproofreader) stage_wproofreader ;;
    admin-panel) stage_admin_panel ;;
    upgrade) stage_upgrade ;;
    diagnostics) stage_diagnostics ;;
    teardown) stage_teardown ;;
    *) precondition "unknown stage $1 (see --help)" ;;
  esac
}

# ---------------------------------------------------------------------------- main

if [ -n "$stages" ]; then
  # Separate stages, for example one CI step each. The CI system runs "diagnostics" after
  # a failure and "teardown" always.
  for s in $stages; do
    if [ "$s" != preflight ]; then
      if [ ! -f "$state_file" ] && { [ "$s" = diagnostics ] || [ "$s" = teardown ]; }; then
        echo "No stack test state in $state_dir: nothing for the $s stage to do"
        continue
      fi
      load_state
    fi
    run_stage "$s"
  done
  exit 0
fi

# All stages in one run: diagnostics after a failure, teardown always, PASS only at the end.
completed=false
finish() {
  local rc=$?
  set +e
  if [ -f "$state_file" ]; then
    load_state
    [ "$rc" -eq 0 ] || stage_diagnostics
    stage_teardown
  fi
  [ "$rc" -ne 0 ] || [ "$completed" = true ] || rc=1
  [ "$rc" -ne 0 ] || echo "PASS: all checks passed"
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for s in $all_stages; do
  [ "$s" = preflight ] || load_state
  run_stage "$s"
done
completed=true
