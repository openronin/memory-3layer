#!/usr/bin/env bash
# Writes a memory hub with the real client, for the tests of a service that hosts hubs.
# Two members, two projects, open and closed tasks, a rename. No real data, no network.
#   tools/hub-fixture.sh <output directory>     -> <output directory>/hub.git, a bare repository
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/bin/memory-3layer"
out=${1:-}; [ -n "$out" ] || { echo "usage: tools/hub-fixture.sh <output directory>" >&2; exit 2; }
[ ! -e "$out/hub.git" ] || { echo "$out/hub.git exists" >&2; exit 1; }
mkdir -p "$out"; out=$(cd "$out" && pwd -P)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
unset MEMORY_3LAYER_HOME MEMORY_3LAYER_SECRETS MEMORY_3LAYER_CONFIG MEMORY_3LAYER_KEY XDG_DATA_HOME XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_HOME

git init -q --bare -b main "$out/hub.git"
git clone -q "$out/hub.git" "$W/clone" 2>/dev/null
HOME="$W/bot" bash "$BIN" hub init "$W/clone" --search https://hub.example.com/api/memory/team/search >/dev/null
git -C "$W/clone" push -q origin main

# as <login> <repo dir> <session> <args...>: the client as that member, inside a project's repository
as() { local who=$1 dir=$2 s=$3; shift 3; (cd "$dir" && HOME="$W/$who" CLAUDE_CODE_SESSION_ID="$s" bash "$BIN" "$@"); }
repo() { # repo <login> <name> <remote>: a repository with one commit
  local d="$W/$1/src/$2"
  mkdir -p "$d"; git init -q -b main "$d"; git -C "$d" remote add origin "$3"
  git -C "$d" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  printf '%s' "$d"
}

for who in alice bob; do
  mkdir -p "$W/$who"
  HOME="$W/$who" bash "$BIN" hub add team "$out/hub.git" --login "$who" >/dev/null
done

A=$(repo alice api git@github.com:acme/api.git)
G=$(repo alice tools https://gitlab.example.com/group/sub/tools.git)
B=$(repo bob api https://github.com/acme/api.git)

as alice "$A" a1 core init >/dev/null
cat >> "$W/alice/.local/share/memory-3layer/projects/github.com/acme/api/CORE.md" <<'MD'

# Deploy
- The staging database is restored from the nightly dump, never from production. [user 2026-11-18]
- Migrations run before the service restarts.

# Mongo
- The legacy index on `events.ts` is a TTL index: dropping it stops the cleanup.
MD
# A hook's tick takes the snapshot; the next change of CORE.md becomes a CORE.log record.
tick() { (cd "$A" && printf '{"hook_event_name":"PostToolUse","session_id":"a1"}' | HOME="$W/alice" CLAUDE_CODE_SESSION_ID=a1 MEMORY_3LAYER_TICK_SECONDS=999999 bash "$BIN" sync tick >/dev/null); }
tick; sleep 1.1
printf -- '- The new cluster needs the index before the data.\n' >> "$W/alice/.local/share/memory-3layer/projects/github.com/acme/api/CORE.md"
tick
as alice "$A" a1 core stash 'Old deploy notes' <<< 'Deploys used to go through the jump host. Not since October.' >/dev/null
as alice "$A" a1 task open mongo-move <<< 'Move the events collection to the new cluster without losing the TTL cleanup.' >/dev/null
as alice "$A" a1 task log mongo-move decision <<< 'Copy with mongodump, not a live sync: the collection is small and a short stop is fine.' >/dev/null
as alice "$A" a1 task log mongo-move note <<< 'The legacy index is a TTL index. It has to be created on the new cluster before the data arrives.' >/dev/null
as alice "$A" a1 task log mongo-move next <<< 'Create the index on the new cluster and run the dump.' >/dev/null
printf 'mongodump --db app --collection events\n' > "$(as alice "$A" a1 task files mongo-move)/dump.sh"
as alice "$A" a2 task open api-docs <<< 'Bring the API reference in line with version 3.' >/dev/null
as alice "$A" a2 task log api-docs blocker <<< 'Waiting for the list of removed endpoints.' >/dev/null
as alice "$A" a3 task open rate-limit <<< 'Add a rate limit to the public search endpoint.' >/dev/null
as alice "$A" a3 task close rate-limit <<< 'Done: 60 requests a minute per token, 429 with Retry-After.' >/dev/null
as alice "$G" a4 core init >/dev/null
as alice "$G" a4 task open lint <<< 'Turn on the linter in CI.' >/dev/null
mkdir -p "$W/alice/.local/share/memory-3layer/identity"
printf -- '---\ntags: [memory/l0, identity]\n---\n\n# Identity (L0)\n\n- **User**: Alice. Replies in English, short.\n' > "$W/alice/.local/share/memory-3layer/identity/IDENTITY.md"
printf 'github.com/acme/api-old\tgithub.com/acme/api\n' > "$W/alice/.local/share/memory-3layer/aliases.tsv"

as bob "$B" b1 core init >/dev/null
as bob "$B" b1 task open search-index <<< 'Rebuild the search index after the mongo move.' >/dev/null
as bob "$B" b1 task log search-index note <<< 'The index reads events by the TTL field, so it depends on the legacy index.' >/dev/null

HOME="$W/alice" bash "$BIN" sync --quiet
HOME="$W/bob" bash "$BIN" sync --quiet
HOME="$W/alice" bash "$BIN" sync --quiet

echo "$out/hub.git"
git -C "$out/hub.git" ls-tree -r --name-only main
