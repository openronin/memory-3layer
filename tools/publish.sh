#!/usr/bin/env bash
# Publishes one built package into its own repository: the working tree there becomes exactly
# what tools/package.sh produced, and the release tag is repeated on that commit.
# Authentication comes from the environment (a token in the URL, or an ssh key for git@).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
usage() { echo "usage: tools/publish.sh <claude-code> <version> [--dry-run]" >&2; exit 2; }

name="${1:-}"; version="${2:-}"; dry=0
[ -n "$name" ] && [ -n "$version" ] || usage
case "${3:-}" in "") ;; --dry-run) dry=1 ;; *) usage ;; esac

repo="${MEMORY_3LAYER_PACKAGE_REPO:-https://github.com/openronin/memory-3layer-$name.git}"
shown=$(printf '%s' "$repo" | sed -E 's#(://)[^/@]+@#\1#')   # a token in the URL is a password: never print it
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

built=$("$ROOT/tools/package.sh" "$name" "$work/package" | awk '{print $2}')
[ "$built" = "$version" ] || { echo "the package says version $built, the release says $version" >&2; exit 1; }

git clone -q -c core.autocrlf=false "$repo" "$work/repo" 2>/dev/null || { echo "cannot clone $shown (create it first, empty)" >&2; exit 1; }
# the package is the whole repository: whatever is no longer built is removed
(cd "$work/repo" && git ls-files -z | xargs -0 rm -f --)
(cd "$work/package" && find . -mindepth 1 -maxdepth 1 -exec cp -R {} "$work/repo/" \;)

cd "$work/repo"
git add -A
if git diff --cached --quiet && git rev-parse -q --verify "refs/tags/v$version" >/dev/null 2>&1; then
  echo "$name: v$version is already published, nothing to do"; exit 0
fi
git -c user.name="${GIT_AUTHOR_NAME:-memory-3layer release}" -c user.email="${GIT_AUTHOR_EMAIL:-noreply@github.com}" \
  commit -q -m "memory-3layer v$version" || true
git -c user.name="${GIT_AUTHOR_NAME:-memory-3layer release}" -c user.email="${GIT_AUTHOR_EMAIL:-noreply@github.com}" tag -f "v$version" -m "v$version" >/dev/null
if [ "$dry" = 1 ]; then echo "$name: dry run, nothing pushed (would push v$version to $shown)"; exit 0; fi
git push -q origin HEAD:refs/heads/main
git push -q -f origin "refs/tags/v$version"
echo "$name: v$version published to $shown"
