#!/usr/bin/env bash
# Promote a WProofreader Server version: change appVersion in wproofreader/Chart.yaml and the
# version in the example files, commit the change on a new branch, and open a pull request.
# Run it after scripts/stack-test.sh passed with --wproofreader-version VERSION.
#
# Usage: scripts/update-app-version.sh VERSION [--open-pr]
#   Without --open-pr: show the change and the commit message, change nothing (dry run).
#   With --open-pr: commit on branch update/wproofreader-VERSION, push it, and open a pull
#   request to main. The checkout must not contain commits that are not on main.
#
# Environment for --open-pr:
#   GITHUB_TOKEN       token with Contents: write and Pull requests: write on the repository
#   GITHUB_REPOSITORY  default: WebSpellChecker/wproofreader-helm
#   BUILD_URL          optional link to the CI run that tested the version
#   GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL   commit author (default: the wsc-ci GitHub App bot)
#
# Exit codes: 0 done or nothing to do, 1 an error, 2 wrong input.
set -euo pipefail

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

version=""
open_pr=false
while [ $# -gt 0 ]; do
  case "$1" in
    --open-pr) open_pr=true; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "error: unknown option $1" >&2; exit 2 ;;
    *) version=$1; shift ;;
  esac
done

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
repository=${GITHUB_REPOSITORY:-WebSpellChecker/wproofreader-helm}
base_branch=main
branch="update/wproofreader-$version"
author_name=${GIT_AUTHOR_NAME:-wsc-ci[bot]}
author_email=${GIT_AUTHOR_EMAIL:-329032902+wsc-ci[bot]@users.noreply.github.com}

in_teamcity() { [ -n "${TEAMCITY_VERSION:-}" ]; }
status() {
  echo "$1"
  if in_teamcity; then echo "##teamcity[buildStatus text='{build.status.text}; ${1//\'/|\'}']"; fi
}
die() { echo "error: $*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: VERSION must look like 6.19.0.0" >&2; exit 2; }

current=$(awk '/^appVersion:/ {gsub(/"/, "", $2); print $2; exit}' wproofreader/Chart.yaml)
if [ "$version" = "$current" ]; then
  status "appVersion is already $version: nothing to promote"
  exit 0
fi
if [ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -n 1)" != "$version" ]; then
  echo "error: $version is lower than the current appVersion $current" >&2
  exit 2
fi

# Commit type from the changed version part: A -> feat! (major), B -> feat (minor), C or D -> fix (patch).
IFS=. read -r old_a old_b _ _ <<<"$current"
IFS=. read -r new_a new_b _ _ <<<"$version"
footer=""
if [ "$new_a" != "$old_a" ]; then
  subject="feat!: update WProofreader Server to $version"
  footer="BREAKING CHANGE: WProofreader Server $version is a new major version. Read its release notes before you upgrade."
elif [ "$new_b" != "$old_b" ]; then
  subject="feat: update WProofreader Server to $version"
else
  subject="fix: update WProofreader Server to $version"
fi

digest() {
  command -v crane >/dev/null 2>&1 || { echo "not checked"; return; }
  crane digest "docker.io/$1" 2>/dev/null || echo "not found"
}
wpr_digest=$(digest "webspellchecker/wproofreader:$version")
dbm_digest=$(digest "webspellchecker/db-manager:$version")

body="WProofreader Server $version replaces $current (appVersion).
The db-manager provisioning Job uses the same version.

Images:
- webspellchecker/wproofreader:$version ($wpr_digest)
- webspellchecker/db-manager:$version ($dbm_digest)"
if [ -n "${BUILD_URL:-}" ]; then
  body="$body

Tested by the stack test: $BUILD_URL"
fi
message="$subject

$body"
[ -z "$footer" ] || message="$message

$footer"

if [ "$open_pr" = true ] && [ -z "${GITHUB_TOKEN:-}" ]; then
  die "GITHUB_TOKEN is not set"
fi

# The files that the previous promotions changed: appVersion, the example values,
# and the rendered example manifests.
files="wproofreader/Chart.yaml examples/values-dev.yaml $(ls manifests/*.yaml)"
python3 - "$current" "$version" $files <<'EOF'
import re, sys
old, new, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
for path in paths:
    text = open(path).read()
    if path.endswith("Chart.yaml"):
        changed = re.sub(r'(?m)^appVersion:.*$', 'appVersion: "%s"' % new, text, count=1)
    else:
        changed = text.replace(old, new)
    if changed != text:
        open(path, "w").write(changed)
EOF
# shellcheck disable=SC2086 # one argument per file
git --no-pager diff --stat -- $files
# shellcheck disable=SC2086
git --no-pager diff -- $files
printf '\nCommit message:\n%s\n\n' "$message"

if [ "$open_pr" = false ]; then
  # shellcheck disable=SC2086
  git checkout -- $files
  status "Dry run: $subject (no commit, no pull request)"
  exit 0
fi

remote="https://github.com/$repository.git"
auth=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')
git_auth() { git -c "http.https://github.com/.extraHeader=Authorization: Basic $auth" "$@"; }
api() { # <method> <path> [json body]
  curl -fsS -X "$1" -H "Authorization: Bearer $GITHUB_TOKEN" -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' "https://api.github.com/repos/$repository$2" ${3:+--data "$3"}
}

# The pull request must contain only the version change, so the checkout must be on main.
git_auth fetch --quiet "$remote" "refs/heads/$base_branch" || die "cannot fetch $base_branch"
git merge-base --is-ancestor HEAD FETCH_HEAD \
  || die "the checkout has commits that are not on $base_branch; run the promotion from $base_branch"

if [ -n "$(git_auth ls-remote --heads "$remote" "refs/heads/$branch")" ]; then
  pr_url=$(api GET "/pulls?state=open&head=${repository%%/*}:$branch" \
    | python3 -c 'import json, sys; prs = json.load(sys.stdin); print(prs[0]["html_url"] if prs else "")')
  # shellcheck disable=SC2086
  git checkout -- $files
  status "Branch $branch already exists${pr_url:+: $pr_url}. Delete the branch to open a new pull request"
  exit 0
fi

git checkout --quiet -B "$branch"
# shellcheck disable=SC2086
git add -- $files
git -c user.name="$author_name" -c user.email="$author_email" commit --quiet -F - <<<"$message"
git_auth push --quiet "$remote" "HEAD:refs/heads/$branch" || die "cannot push $branch"
echo "Pushed branch $branch"

pr_body="$body

The stack test installed MySQL and WProofreader Server $version with the db-manager Job on k3d
and checked the version, the status, the license status, and the database users.
Merge this pull request to start the chart release pull request."
payload=$(python3 -c 'import json, sys; print(json.dumps({"title": sys.argv[1], "head": sys.argv[2], "base": sys.argv[3], "body": sys.argv[4]}))' \
  "$subject" "$branch" "$base_branch" "$pr_body")
pr_url=$(api POST /pulls "$payload" | python3 -c 'import json, sys; print(json.load(sys.stdin)["html_url"])') \
  || die "cannot open the pull request for $branch"
status "Pull request: $pr_url"
