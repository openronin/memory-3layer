#!/usr/bin/env bash
# Tests for packaging and publishing. Packages go to temp dirs, the package repository is a temp bare one.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; n=0
ok() { n=$((n+1)); if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }
P=$T/p
"$ROOT/tools/package.sh" claude-code "$P" >/dev/null; ok "builds" $? 0
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json bin/memory-3layer bin/memory-sync.sh bin/memory-secrets.sh scripts/session-start.sh scripts/session-end.sh scripts/pre-compact.sh harness/claude-code/import-memory skills/protocol/SKILL.md skills/recall/SKILL.md templates/IDENTITY.template.md LICENSE; do
  ok "has $f" "$(test -f "$P/$f"; echo $?)" 0
done
ok "manifest isn't overwritten by a stray importer at the root" "$(test -e "$P/import-memory"; echo $?)" 1
ok "no symlinks" "$(find "$P" -type l | wc -l | tr -d ' ')" 0
ok "client is executable" "$(test -x "$P/bin/memory-3layer"; echo $?)" 0
ok "importer is executable" "$(test -x "$P/harness/claude-code/import-memory"; echo $?)" 0
for f in "$P"/.claude-plugin/*.json "$P"/hooks/hooks.json; do python3 -m json.tool "$f" >/dev/null; ok "valid json: ${f##*/}" $? 0; done
for s in "$P"/skills/*/SKILL.md; do
  ok "skill frontmatter: $(basename "$(dirname "$s")")" "$(sed -n '1p' "$s")|$(sed -n '2p' "$s" | cut -d: -f1)|$(grep -c '^description: ' "$s" | sed 's/[1-9][0-9]*/y/')" "---|name|y"
done
ok "no harness home paths in skills" "$(grep -rl '~/.claude/bin' "$P/skills" | wc -l | tr -d ' ')" 0
ok "no hook names the user's home" "$(grep -c '~/' "$P/hooks/hooks.json")" 0
v=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$P/.claude-plugin/plugin.json")
ok "readme says the version" "$(grep -c "version $v" "$P/README.md")" 1
ok "lf pinned" "$(cat "$P/.gitattributes")" "* text=auto eol=lf"
# the package runs from where it lands, alone
mkdir -p "$T/h" "$T/r"; git -C "$T/r" init -q; git -C "$T/r" remote add origin git@github.com:o/r.git
out=$(cd "$T/r" && echo '{"hook_event_name":"SessionStart"}' | HOME="$T/h" bash "$P/scripts/session-start.sh")
ok "hook answers from the package" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')" SessionStart
case "$out" in *"$P/bin/memory-3layer"*) r=y ;; *) r=n ;; esac; ok "context names the client" $r y
ok "guard runs from the package" "$(echo '{"tool_name":"Read","tool_input":{"file_path":"/etc/hostname"}}' | HOME="$T/h" bash "$P/bin/memory-3layer" guard >/dev/null; echo $?)" 0
ok "importer is found" "$(HOME="$T/h" bash "$P/bin/memory-3layer" import claude-code >/dev/null 2>&1; echo $?)" 0
# publishing
B=$T/pkg.git; git init -q --bare -b main "$B"
export MEMORY_3LAYER_PACKAGE_REPO="$B" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
"$ROOT/tools/publish.sh" claude-code 0.0.0 >/dev/null 2>&1; ok "wrong version refused" $? 1
"$ROOT/tools/publish.sh" claude-code "$v" --dry-run >/dev/null; ok "dry run succeeds" $? 0
ok "dry run pushes nothing" "$(git -C "$B" for-each-ref | wc -l | tr -d ' ')" 0
"$ROOT/tools/publish.sh" claude-code "$v" >/dev/null; ok "publishes" $? 0
ok "tag is there" "$(git -C "$B" rev-parse -q --verify "refs/tags/v$v" >/dev/null; echo $?)" 0
ok "content is there" "$(git -C "$B" cat-file -e main:bin/memory-3layer; echo $?)" 0
ok "exec bit survives" "$(git -C "$B" ls-tree main bin/memory-3layer | cut -c1-6)" 100755
c=$(git -C "$B" rev-parse main); case "$("$ROOT/tools/publish.sh" claude-code "$v")" in *"nothing to do"*) r=y ;; *) r=n ;; esac; ok "repeat does nothing" $r y
ok "repeat adds no commit" "$(git -C "$B" rev-parse main)" "$c"
git clone -q "$B" "$T/c"; echo x > "$T/c/stale.txt"; git -C "$T/c" add -A; git -C "$T/c" commit -qm stale; git -C "$T/c" push -q origin HEAD:main
"$ROOT/tools/publish.sh" claude-code "$v" >/dev/null
ok "what isn't built is removed" "$(git -C "$B" cat-file -e main:stale.txt 2>/dev/null; echo $?)" 128
out=$(MEMORY_3LAYER_PACKAGE_REPO="https://x:s3cr3t-val@127.0.0.1:1/x.git" "$ROOT/tools/publish.sh" claude-code "$v" 2>&1); case "$out" in *s3cr3t-val*) r=leak ;; *) r=clean ;; esac; ok "token in the url isn't shown" $r clean
echo; [[ $fail -eq 0 ]] && echo "all $n passed" || echo "FAILED"
exit $fail
