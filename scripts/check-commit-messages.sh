#!/usr/bin/env bash
# Check that every commit in a range has a Conventional Commits subject.
# The release workflow reads these subjects on main (with git-cliff) to select the next
# version and to write the changelog. Pull requests are merged with a merge commit, so every commit of the
# branch reaches main. Merge commits are skipped.
#
# Usage: scripts/check-commit-messages.sh [<base>] [<head>]
#   default: origin/main HEAD
set -euo pipefail

base=${1:-origin/main}
head=${2:-HEAD}

types='feat|fix|perf|refactor|revert|docs|style|test|build|ci|chore'
pattern="^(${types})(\([A-Za-z0-9._/-]+\))?!?: [^ .](.*[^.])?$"

failed=0
while IFS= read -r line; do
  sha=${line%% *}
  subject=${line#* }
  if [[ ! $subject =~ $pattern ]]; then
    echo "error: ${sha} does not follow Conventional Commits: ${subject}" >&2
    failed=1
  fi
done < <(git log --no-merges --format='%h %s' "${base}..${head}")

if [[ $failed -ne 0 ]]; then
  cat >&2 <<'EOF'

Use "<type>[(scope)][!]: <description>", for example "fix(gateway): keep the TLS hostname".
Types: feat, fix, perf, refactor, revert, docs, style, test, build, ci, chore.
No period at the end. See "Commit messages" in CONTRIBUTING.md.
To change commit messages, run "git rebase -i <base>" and force-push the branch.
EOF
  exit 1
fi
echo "All commit subjects follow Conventional Commits."
