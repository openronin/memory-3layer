#!/usr/bin/env bash
# Tests for bin/memory-3layer. Runs in a temp HOME and touches no real data.
set -u
BIN="$(cd "$(dirname "$0")/.." && pwd)/bin/memory-3layer"
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset MEMORY_3LAYER_HOME MEMORY_3LAYER_SECRETS MEMORY_3LAYER_CONFIG XDG_DATA_HOME XDG_CONFIG_HOME
fail=0; n=0
ok() { n=$((n+1)); if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }
m() { bash "$BIN" "$@"; }

# --- locations ---
ok "default home" "$(m path home)" "$HOME/.local/share/memory-3layer"
ok "default secrets" "$(m path secrets)" "$HOME/.local/share/memory-3layer-secrets"
ok "env moves home" "$(MEMORY_3LAYER_HOME=/x m path home)" /x
mkdir -p "$HOME/.config/memory-3layer"; echo 'MEMORY_3LAYER_HOME=/from-config' > "$HOME/.config/memory-3layer/config"
ok "config moves home" "$(m path home)" /from-config
ok "env beats config" "$(MEMORY_3LAYER_HOME=/env m path home)" /env
rm "$HOME/.config/memory-3layer/config"

# --- keys from every remote form ---
R="$T/r"; git init -q "$R"
key_for() { git -C "$R" remote remove origin 2>/dev/null; git -C "$R" remote add origin "$1"; m key "$R"; }
for u in https://github.com/o/r.git https://u:tok@github.com/o/r git@github.com:o/r.git ssh://git@GitHub.com:22/o/r.git; do # secret-scan:ignore
  ok "key: $u" "$(key_for "$u")" github.com/o/r
done
ok "key: nested group" "$(key_for git@gitlab.example.com:tr/sub/r.git)" gitlab.example.com/tr/sub/r
ok "key: ssh with a port" "$(key_for ssh://git@git.example.org:2201/pronchev/xchg)" git.example.org/pronchev/xchg
key_for git@github.com:o/r.git >/dev/null
mkdir -p "$R/a/b"
ok "subdir shares the key" "$(m key "$R/a/b")" github.com/o/r
git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
git -C "$R" worktree add -q "$T/wt" 2>/dev/null
ok "worktree shares the key" "$(m key "$T/wt")" github.com/o/r
mkdir -p "$HOME/p/plain"
ok "no git: path under home" "$(m key "$HOME/p/plain")" local/p/plain
git init -q "$HOME/p/noremote"
ok "no remote: path under home" "$(m key "$HOME/p/noremote")" local/p/noremote
ln -s "$HOME" "$T/linked-home"
ok "no remote: home through a symlink" "$(HOME="$T/linked-home" bash "$BIN" key "$T/linked-home/p/noremote")" local/p/noremote
ok "project path" "$(MEMORY_3LAYER_HOME=/d m path project "$R")" /d/projects/github.com/o/r

# --- pinned key, with fallback ---
PB="$T/pinhome"; export MEMORY_3LAYER_HOME="$PB"
mkdir -p "$PB/projects/github.com/o/r"; printf 'state\n' > "$PB/projects/github.com/o/r/SESSION.md"
m pin my/pinned "$R" >/dev/null
ok "pin wins over the remote" "$(m key "$R")" my/pinned
ok "pin works from a subdir" "$(m key "$R/a/b")" my/pinned
ok "MEMORY_3LAYER_KEY wins anywhere" "$(MEMORY_3LAYER_KEY=x/set m key "$T")" x/set
MEMORY_3LAYER_KEY=../x m key "$T" >/dev/null 2>&1; ok "MEMORY_3LAYER_KEY must be a valid key" $? 2
ok "pin reaches a worktree" "$(m key "$T/wt")" my/pinned
ok "pin carries the memory" "$(cat "$PB/projects/my/pinned/SESSION.md")" state
ok "marker stays out of git" "$(git -C "$R" status --porcelain | grep -c memory-3layer-key)" 0
for bad in '../evil' '/abs' 'a//b' ''; do
  printf '%s\n' "$bad" > "$R/.memory-3layer-key"
  ok "bad pin [$bad] falls back to remote" "$(m key "$R" 2>/dev/null)" github.com/o/r
done
m unpin "$R" >/dev/null
ok "unpin falls back to remote" "$(m key "$R")" github.com/o/r
ok "remote still works from a worktree" "$(m key "$T/wt")" github.com/o/r
m pin bad//key "$R" >/dev/null 2>&1; ok "pin refuses a bad key" $? 2
ok "refused pin writes nothing" "$(test -e "$R/.memory-3layer-key"; echo $?)" 1
m pin my/plain "$HOME/p/plain" >/dev/null
ok "pin without git" "$(m key "$HOME/p/plain")" my/plain
mkdir -p "$HOME/p/plain/sub"
ok "pin without git, from a subdir" "$(m key "$HOME/p/plain/sub")" my/plain
rm "$HOME/p/plain/.memory-3layer-key"
ok "no git, no pin: falls back to path" "$(m key "$HOME/p/plain")" local/p/plain

# --- rekey ---
RK="$T/rekeyhome"; export MEMORY_3LAYER_HOME="$RK"
mkdir -p "$RK/projects/github.com/o/old/imported/x"; printf 's\n' > "$RK/projects/github.com/o/old/SESSION.md"; printf 'i\n' > "$RK/projects/github.com/o/old/imported/x/n.md"
mkdir -p "$RK/projects/github.com/o/r"; printf 'other\n' > "$RK/projects/github.com/o/r/SESSION.md"
m rekey github.com/o/old github.com/o/r >/dev/null
ok "rekey keeps the target's file" "$(cat "$RK/projects/github.com/o/r/SESSION.md")" other
ok "rekey keeps a conflicting file" "$(cat "$RK/projects/github.com/o/r/superseded/github.com_o_old/SESSION.md")" s
ok "rekey moves the rest" "$(cat "$RK/projects/github.com/o/r/imported/x/n.md")" i
ok "rekey removes the old dir" "$(test -e "$RK/projects/github.com/o/old"; echo $?)" 1
key_for git@github.com:o/old.git >/dev/null
ok "old remote redirects to the new key" "$(m key "$R")" github.com/o/r
key_for git@github.com:o/r.git >/dev/null
m rekey github.com/o/r github.com/o/old >/dev/null 2>&1; ok "rekey refuses a loop" $? 2
m rekey a/b a/b >/dev/null 2>&1; ok "rekey refuses the same key" $? 2
m rekey ../x a/b >/dev/null 2>&1; ok "rekey refuses an unsafe key" $? 2
ok "projects lists keys" "$(m projects)" github.com/o/r
unset MEMORY_3LAYER_HOME

# --- context ---
export MEMORY_3LAYER_HOME="$T/data"
P="$T/data/projects/github.com/o/r"; mkdir -p "$P"
ctx() { (cd "$R" && m context </dev/null); }
case "$(ctx)" in *"$P/SESSION.md"*) r=y ;; *) r=n ;; esac; ok "context names the session" $r y
case "$(ctx)" in *OVERRIDDEN*|*ignore\ them*) r=y ;; *) r=n ;; esac; ok "context doesn't override the harness" $r n
printf -- '---\nlast_updated: 2020-01-01T00:00:00Z\n---\n' > "$P/SESSION.md"
case "$(ctx)" in *STALE*) r=y ;; *) r=n ;; esac; ok "stale warning" $r y
case "$(ctx)" in *"does not depend on it without asking"*) r=y ;; *) r=n ;; esac; ok "stale: a question unrelated to it needs no asking" $r y
printf -- '---\nlast_updated: %s\n---\n' "$(date -u +%FT%TZ)" > "$P/SESSION.md"
case "$(ctx)" in *STALE*) r=y ;; *) r=n ;; esac; ok "fresh: no warning" $r n
head -c 41000 /dev/zero | tr '\0' x >> "$P/SESSION.md"
case "$(ctx)" in *"SOFT LIMIT"*) r=y ;; *) r=n ;; esac; ok "soft limit" $r y
head -c 41000 /dev/zero | tr '\0' x >> "$P/SESSION.md"
case "$(ctx)" in *"HARD LIMIT"*) r=y ;; *) r=n ;; esac; ok "hard limit" $r y
out=$(cd "$R" && echo '{"hook_event_name":"SessionStart"}' | m context)
ok "hook answer is valid JSON" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')" SessionStart

# --- secrets through the main command ---
echo val | m secret put s >/dev/null
ok "secret goes to its own dir" "$(cat "$HOME/.local/share/memory-3layer-secrets/s")" val
ok "secret stays out of data" "$(find "$T/data" -name s | wc -l | tr -d ' ')" 0

# --- import ---
C="$T/cl"; export CLAUDE_HOME="$C"
GH="ghp""_$(printf 'a1B2%.0s' {1..10})"
slug() { printf '%s' "$1" | sed -E 's/[^a-zA-Z0-9]/-/g'; }
A="$C/projects/$(slug "$R")"; mkdir -p "$A/memory"
printf '{"cwd":"%s"}\n' "$R" > "$A/s.jsonl"
printf -- '---\ntype: feedback\n---\nnote\n' > "$A/memory/feedback_x.md"
printf -- 'real notes\n' > "$A/memory/MEMORY.md"
printf 'ours\n' > "$A/memory/SESSION.md"; printf 'ours\n' > "$A/memory/project.md"; printf 'ours\n' > "$A/memory/SESSION.archive.md"
printf 'token %s\n' "$GH" > "$A/memory/leaky.md"
B="$C/projects/$(slug "$HOME/p/noremote")"; mkdir -p "$B/memory"
printf -- '- [SESSION](SESSION.md)\n' > "$B/memory/MEMORY.md"
printf 'by walk\n' > "$B/memory/found.md"
G="$C/projects/-gone-project"; mkdir -p "$G/memory"; printf 'orphan\n' > "$G/memory/lost.md"
D="$T/data/projects/github.com/o/r/imported/claude-code"
before=$(cd "$C" && find . -type f -exec md5sum {} + | sort | md5sum)
plan=$(m import claude-code)
ok "plan copies nothing" "$(test -e "$D"; echo $?)" 1
case "$plan" in *"4 new"*"1 with secrets"*"1 without a known project"*) r=y ;; *) r="$plan" ;; esac
ok "plan counts" "${r:0:1}" y
case "$plan" in *"$GH"*) r=leak ;; *) r=clean ;; esac; ok "plan hides the secret" $r clean
m import claude-code --apply >/dev/null
ok "typed file copied" "$(cat "$D/feedback_x.md" | tail -1)" note
ok "index with content copied" "$(cat "$D/MEMORY.md")" "real notes"
ok "secret not copied" "$(test -e "$D/leaky.md"; echo $?)" 1
ok "older-version SESSION not copied" "$(test -e "$D/SESSION.md"; echo $?)" 1
ok "older-version project.md not copied" "$(test -e "$D/project.md"; echo $?)" 1
N="$T/data/projects/local/p/noremote/imported/claude-code"
ok "project found by walking the disk" "$(cat "$N/found.md")" "by walk"
ok "unknown project kept aside" "$(cat "$T/data/projects/_unassigned/-gone-project/imported/claude-code/lost.md")" orphan
ok "pointer-only index skipped" "$(test -e "$N/MEMORY.md"; echo $?)" 1
ok "source untouched" "$(cd "$C" && find . -type f -exec md5sum {} + | sort | md5sum)" "$before"
case "$(m import claude-code --apply)" in *"0 new, 0 updated, 4 already"*) r=y ;; *) r=n ;; esac; ok "second run changes nothing" $r y
printf 'newer\n' > "$A/memory/MEMORY.md"
case "$(m import claude-code --apply)" in *"1 updated"*) r=y ;; *) r=n ;; esac; ok "changed source updates the copy" $r y
ok "copy updated" "$(cat "$D/MEMORY.md")" newer
case "$(ctx)" in *"imported/"*) r=y ;; *) r=n ;; esac; ok "context mentions imported notes" $r y
# autoMemoryDirectory: for one project, and for the whole account
X="$T/custom-project"; mkdir -p "$X"; printf 'custom\n' > "$X/custom_note.md"
mkdir -p "$R/.claude"; printf '{"autoMemoryDirectory":"%s"}' "$X" > "$R/.claude/settings.local.json"
m import claude-code --apply >/dev/null
ok "project-level directory imported" "$(cat "$D/custom_note.md")" custom
rm "$R/.claude/settings.local.json"
Y="$T/custom-account"; mkdir -p "$Y"; printf 'shared\n' > "$Y/shared_note.md"
printf '{"autoMemoryDirectory":"%s"}' "$Y" > "$C/settings.json"
m import claude-code --apply >/dev/null
ok "account-level directory kept aside" "$(cat "$T/data/projects/_unassigned/autoMemoryDirectory/imported/claude-code/shared_note.md")" shared
rm "$C/settings.json"
printf '{"autoMemoryDirectory":"~/tilde-dir"}' > "$C/settings.json"; mkdir -p "$HOME/tilde-dir"; printf 't\n' > "$HOME/tilde-dir/t.md"
m import claude-code --apply >/dev/null
ok "tilde is expanded" "$(cat "$T/data/projects/_unassigned/autoMemoryDirectory/imported/claude-code/t.md")" t
rm "$C/settings.json"
m import nope >/dev/null 2>&1; ok "unknown harness fails" $? 2
m import ../x >/dev/null 2>&1; ok "bad harness name fails" $? 2

# --- migrate from the older layout ---
M2="$T/m2"; export MEMORY_3LAYER_HOME="$M2" MEMORY_3LAYER_CONFIG="$T/m2cfg/config"
mkdir -p "$C/memory"; printf 'me\n' > "$C/memory/IDENTITY.md"; printf 'L2_SOFT_BYTES=1\n' > "$C/.memory-config"
printf 'session a\n' > "$A/memory/SESSION.md"; touch -t 202601020000 "$A/memory/SESSION.md"
W="$T/wt-old"; git -C "$R" worktree add -q "$W" -b oldwt 2>/dev/null
W2="$C/projects/$(slug "$W")"; mkdir -p "$W2/memory"; printf '{"cwd":"%s"}\n' "$W" > "$W2/s.jsonl"
printf 'session older\n' > "$W2/memory/SESSION.md"; touch -t 202601010000 "$W2/memory/SESSION.md"
printf 'ours\n' > "$W2/memory/project.md"; touch -t 202501010000 "$W2/memory/project.md"
printf 'gone session\n' > "$G/memory/SESSION.md"
PD="$M2/projects/github.com/o/r"
srcsum=$(cd "$C" && find . -type f -exec md5sum {} + | sort | md5sum)
m migrate claude-code >/dev/null
ok "migrate plan writes nothing" "$(test -e "$M2"; echo $?)" 1
m migrate claude-code --apply >/dev/null
ok "identity moved" "$(cat "$M2/identity/IDENTITY.md")" me
ok "config moved" "$(cat "$T/m2cfg/config")" L2_SOFT_BYTES=1
ok "newest session takes the name" "$(cat "$PD/SESSION.md")" "session a"
ok "older different session kept" "$(cat "$PD/superseded/$(slug "$W")/SESSION.md")" "session older"
ok "identical older copy not duplicated" "$(test -e "$PD/superseded/$(slug "$W")/project.md"; echo $?)" 1
ok "archive moved" "$(cat "$PD/SESSION.archive.md")" ours
ok "mtime preserved" "$(date -r "$PD/SESSION.md" +%F)" 2026-01-02
ok "unknown project kept aside" "$(cat "$M2/projects/_unassigned/-gone-project/SESSION.md")" "gone session"
ok "native notes not migrated" "$(test -e "$PD/feedback_x.md"; echo $?)" 1
ok "migrate leaves the source" "$(cd "$C" && find . -type f -exec md5sum {} + | sort | md5sum)" "$srcsum"
case "$(m migrate claude-code --apply | tail -1)" in *" 0 to copy"*) r=y ;; *) r=n ;; esac; ok "second migrate copies nothing" $r y
printf 'session a, continued\n' > "$PD/SESSION.md"
printf 'old system wrote\n' > "$A/memory/SESSION.md"; touch -t 202601030000 "$A/memory/SESSION.md"
m migrate claude-code --apply >/dev/null
ok "newer destination is not overwritten" "$(cat "$PD/SESSION.md")" "session a, continued"
touch -t 202001010000 "$PD/SESSION.md"; m migrate claude-code --apply >/dev/null
ok "newer source updates a stale copy" "$(cat "$PD/SESSION.md")" "old system wrote"
# assign
U="$M2/projects/_unassigned/-gone-project"
ok "folder starts unassigned" "$(cat "$U/SESSION.md")" "gone session"
mkdir -p "$M2/projects/h/o/gone"; printf 'other\n' > "$M2/projects/h/o/gone/SESSION.md"; printf 'gone session\n' > "$M2/projects/h/o/gone/same.md"; cp "$M2/projects/h/o/gone/same.md" "$U/same.md"; printf 'solo\n' > "$U/solo.md"
m assign -- bad h/o/gone >/dev/null 2>&1; ok "assign checks arguments" $? 2
m assign -gone-project ../evil >/dev/null 2>&1; ok "assign refuses an unsafe key" $? 2
m assign -gone-project h/o/gone >/dev/null
ok "assign moves a new file" "$(cat "$M2/projects/h/o/gone/solo.md")" solo
ok "assign keeps a different file" "$(cat "$M2/projects/h/o/gone/superseded/-gone-project/SESSION.md")" "gone session"
ok "assign keeps the target's own file" "$(cat "$M2/projects/h/o/gone/SESSION.md")" other
ok "assign removes the old folder" "$(test -e "$U"; echo $?)" 1
m migrate claude-code --apply >/dev/null
ok "migrate follows the assignment" "$(test -e "$U"; echo $?)" 1
export MEMORY_3LAYER_HOME="$T/data"; unset MEMORY_3LAYER_CONFIG
unset CLAUDE_HOME

# --- hooks and refresh with a stand-in qmd ---
REPO="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$T/fake"; cat > "$T/fake/qmd" <<X
#!/bin/sh
echo "\$*" >> "$T/qmd.log"
case "\$*" in "collection show"*) [ -f "$T/qmd.path" ] && echo "  Path:     \$(cat "$T/qmd.path")" ;; esac
X
chmod +x "$T/fake/qmd"
PATH="$T/fake:$PATH" m refresh
ok "refresh registers the collection" "$(grep -c 'collection add' "$T/qmd.log")" 1
ok "refresh updates the index" "$(grep -c '^update' "$T/qmd.log")" 1
: > "$T/qmd.log"; printf '%s' "$MEMORY_3LAYER_HOME" > "$T/qmd.path"; PATH="$T/fake:$PATH" m refresh
ok "right path: collection kept" "$(grep -c 'collection add' "$T/qmd.log")" 0
: > "$T/qmd.log"; printf '/moved' > "$T/qmd.path"; PATH="$T/fake:$PATH" m refresh
ok "moved data: collection replaced" "$(grep -c 'collection remove' "$T/qmd.log")/$(grep -c 'collection add' "$T/qmd.log")" 1/1
: > "$T/qmd.log"; PATH="$T/fake:$PATH" m refresh --debounce
ok "debounce skips a fresh index" "$(wc -c < "$T/qmd.log" | tr -d ' ')" 0
out=$(cd "$R" && echo '{"hook_event_name":"SessionStart"}' | bash "$REPO/hooks/session-start.sh")
ok "session hook answers in JSON" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')" SessionStart
out=$(cd "$R" && bash "$REPO/hooks/pre-compact.sh")
case "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["systemMessage"])')" in *"$P/SESSION.md"*) r=y ;; *) r=n ;; esac
ok "pre-compact names the session" $r y

cat > "$T/fake/qmd" <<X
#!/bin/sh
printf '#a,0.9,qmd://memory-3layer/projects/github-com/o/r/SESSION.md\\n#b,0.8,qmd://memory-3layer/projects/github-com/o/r2/SESSION.md\\n'
X
out=$(cd "$R" && PATH="$T/fake:$PATH" m search --here x)
ok "search --here keeps this project" "$out" "#a,0.9,qmd://memory-3layer/projects/github-com/o/r/SESSION.md"

# --- installer ---
H2="$T/h2"; mkdir -p "$H2/.claude/memory"; echo me > "$H2/.claude/memory/IDENTITY.md"
env -u MEMORY_3LAYER_HOME HOME="$H2" bash "$REPO/install.sh" >/dev/null 2>&1; ok "install refuses to strand old memory" $? 1
ok "refusal changes nothing" "$(ls "$H2/.claude")" memory
H3="$T/h3"; mkdir -p "$H3"
env -u MEMORY_3LAYER_HOME HOME="$H3" bash "$REPO/install.sh" >/dev/null 2>&1; ok "fresh install works" $? 0
ok "identity in the data dir" "$(test -f "$H3/.local/share/memory-3layer/identity/IDENTITY.md"; echo $?)" 0
ok "config in its own dir" "$(test -f "$H3/.config/memory-3layer/config"; echo $?)" 0
ok "command linked" "$(env -u MEMORY_3LAYER_HOME HOME="$H3" "$H3/.local/bin/memory-3layer" path home)" "$H3/.local/share/memory-3layer"
ok "importer installed" "$(test -x "$H3/.claude/harness/claude-code/import-memory"; echo $?)" 0
ok "no memory under .claude" "$(test -e "$H3/.claude/memory"; echo $?)" 1

# --- install-cli: the shim follows the enabled plugin, a local folder over its stale copy ---
CC="$T/cc"; mkdir -p "$CC/plugins/cache/mk/memory-3layer/1.0/bin" "$T/devmk/.claude-plugin" "$T/devmk/bin"
printf '#!/bin/sh\necho cache\n' > "$CC/plugins/cache/mk/memory-3layer/1.0/bin/memory-3layer"
printf '#!/bin/sh\necho folder\n' > "$T/devmk/bin/memory-3layer"; chmod +x "$CC/plugins/cache/mk/memory-3layer/1.0/bin/memory-3layer" "$T/devmk/bin/memory-3layer"
printf '{"plugins":[{"name":"memory-3layer","source":"./"}]}' > "$T/devmk/.claude-plugin/marketplace.json"
printf '{"version":"2.0-dev"}' > "$T/devmk/.claude-plugin/plugin.json"
printf '{"enabledPlugins":{"memory-3layer@mk":true,"memory-3layer@dev":false}}' > "$CC/settings.json"
printf '{"plugins":{"memory-3layer@mk":[{"version":"1.0","installPath":"%s"}],"memory-3layer@dev":[{"version":"2.0-dev","installPath":"/nowhere"}]}}' "$CC/plugins/cache/mk/memory-3layer/1.0" > "$CC/plugins/installed_plugins.json"
printf '{"mk":{"source":{"source":"github","repo":"x/y"}},"dev":{"source":{"source":"directory","path":"%s"}}}' "$T/devmk" > "$CC/plugins/known_marketplaces.json"
CLAUDE_CONFIG_DIR="$CC" m install-cli "$T/lbin" >/dev/null
ok "install-cli: the enabled plugin runs" "$(CLAUDE_CONFIG_DIR="$CC" "$T/lbin/memory-3layer")" cache
printf '{"enabledPlugins":{"memory-3layer@mk":false,"memory-3layer@dev":true}}' > "$CC/settings.json"
ok "install-cli: a local marketplace runs from its folder" "$(CLAUDE_CONFIG_DIR="$CC" "$T/lbin/memory-3layer")" folder

# --- isolation from harness memory ---
ok "nothing written under .claude" "$(find "$HOME/.claude" 2>/dev/null | wc -l | tr -d ' ')" 0

echo; [[ $fail -eq 0 ]] && echo "all $n passed" || echo "FAILED"
exit $fail
