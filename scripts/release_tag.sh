#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command git
ensure_clean_worktree
tag="$(version_tag)"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 && fail "Tag $tag already exists."
git tag -a "$tag" -m "Release $tag"
log "Created $tag. Push explicitly with make release-push."
