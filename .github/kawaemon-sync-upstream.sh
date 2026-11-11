#!/usr/bin/env bash
# Merge upstream/main into the current branch, dropping every upstream
# GitHub Actions workflow so only .github/workflows/kawaemon-*.yml remain.
#
# Usage: .github/kawaemon-sync-upstream.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git fetch upstream

if ! git merge --no-ff --no-edit --no-commit upstream/main; then
  echo "merge reported conflicts; resolving workflow ones automatically"
fi

# Remove all non-fork workflows (conflicted, modified, or newly added).
for f in $(git ls-files -- .github/workflows | sort -u); do
  case "$(basename "$f")" in
    kawaemon-*) ;;
    *) git rm -q --force -- "$f" ;;
  esac
done

if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
  echo "Remaining conflicts (resolve manually, then 'git commit'):"
  git diff --name-only --diff-filter=U
  exit 1
fi

if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  git commit --no-edit
else
  echo "Already up to date."
fi
