#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command git
ensure_clean_worktree
branch="$(current_branch)"
tag="$(version_tag)"
git remote get-url origin >/dev/null 2>&1 || fail "Git remote origin is not configured."
git push origin "$branch"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
  git push origin "$tag"
fi
log "Pushed $branch and ${tag:-no release tag}."
