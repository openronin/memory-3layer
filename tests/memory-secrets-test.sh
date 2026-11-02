#!/usr/bin/env bash
# Tests for bin/memory-secrets.sh. Runs in a temp dir and touches no real memory.
# Fake tokens are assembled at runtime so this file never trips a scanner.
set -u
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/memory-secrets.sh"
T=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$T"' EXIT
export MEMORY_3LAYER_SECRETS="$T/store" MEMORY_3LAYER_HOME="$T/data" CLAUDE_HOME="$T/claude"
M="$CLAUDE_HOME/projects/-x/memory"; mkdir -p "$M" "$CLAUDE_HOME/memory"
fail=0; n=0
ok() { n=$((n+1)); if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }
ms() { bash "$SCRIPT" "$@"; }

GH="ghp""_$(printf 'a1B2%.0s' {1..10})"
ANT="sk-""ant-api03-$(printf 'Zz9%.0s' {1..10})"
PW="Pr0d-Pa55-Word"

# --- store ---
printf '%s\n' "$PW" | ms put db >/dev/null
ok "put strips the newline" "$(cat "$T/store/db")" "$PW"
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
ok "file mode is 600" "$(mode "$T/store/db")" 600
ok "store mode is 700" "$(mode "$T/store")" 700
ok "list shows the name" "$(ms list)" db
ms has db; ok "has: present" $? 0
ms has nope; ok "has: absent" $? 1
ok "run passes the value" "$(ms run X=db -- sh -c 'printf %s "$X"')" "$PW"
ms get db >/dev/null 2>&1; ok "get refused in a pipe" $? 2
ok "get prints no value in a pipe" "$(ms get db 2>/dev/null)" ""
ms put '../evil' </dev/null >/dev/null 2>&1; ok "path traversal refused" $? 2
ms run X=missing -- true 2>/dev/null; ok "run: missing secret fails" $? 2
ms rm db; ms has db; ok "rm removes" $? 1

# --- scan: true positives ---
cat > "$M/a.md" <<X
token $GH here
key: $ANT
password: $PW
пароль = $PW
mongodb://root:$PW@db.local/x
X
out=$(ms scan "$M"); rc=$?
ok "scan exits 1 on findings" $rc 1
ok "gh found" "$(grep -c ':1	github' <<<"$out")" 1
ok "anthropic found" "$(grep -c ':2	anthropic' <<<"$out")" 1
ok "kv found" "$(grep -c ':3	key-value' <<<"$out")" 1
ok "cyrillic kv found" "$(grep -c ':4	key-value' <<<"$out")" 1
ok "url password found" "$(grep -c ':5	url-password' <<<"$out")" 1
case "$out" in *"$PW"*|*"$GH"*|*"$ANT"*) ok "scan hides values" leak clean ;; *) ok "scan hides values" clean clean ;; esac

# --- scan: false positives seen in real memory ---
cat > "$M/b.md" <<'X'
prefix only: sk-ant-api03-
validateToken: decode->null->403
checkActionAccessByToken: missing->401
password: secret://db
token: required
password: <your password>
TOKEN=$GITLAB_TOKEN
api_key: xxxxxxxxxxxx
https://user:***@host
X
ok "no false positives" "$(ms scan "$M/b.md")" ""
printf 'password: %s secret-scan:ignore\n' "$PW" > "$M/c.md"
ok "ignore mark" "$(ms scan "$M/c.md")" ""

# --- adopt ---
printf 'line one %s and again %s\nsecond line\n' "$GH" "$GH" > "$M/d.md"
ms adopt "$M/d.md:1" gh-token >/dev/null
ok "adopt rewrites all occurrences" "$(sed -n 1p "$M/d.md")" "line one secret://gh-token and again secret://gh-token"
ok "adopt keeps other lines" "$(sed -n 2p "$M/d.md")" "second line"
ok "adopt stores the value" "$(cat "$T/store/gh-token")" "$GH"
ms scan "$M/d.md" >/dev/null; ok "clean after adopt" $? 0
printf 'x %s\n' "$ANT" > "$M/e.md"
ms adopt "$M/e.md:1" gh-token >/dev/null 2>&1; ok "adopt won't overwrite another value" $? 2
ok "file untouched on refusal" "$(cat "$M/e.md")" "x $ANT"
printf 'a\n-----BEGIN RSA PRIVATE KEY-----\n' > "$M/f.md"
ms adopt "$M/f.md:2" k >/dev/null 2>&1; ok "adopt refuses a private key" $? 2

# --- guard ---
gj() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' "$1" "$2"; }
g() { gj "$1" "$2" | ms guard 2>"$T/err"; echo $?; }
J() { python3 -c 'import json,sys; print(json.dumps(dict(zip(sys.argv[1::2],sys.argv[2::2]))))' "$@"; }
ok "guard blocks Write to SESSION" "$(g Write "$(J file_path "$M/SESSION.md" content "a $GH")")" 2
if grep -qF "$GH" "$T/err"; then ok "guard message hides the value" leak clean; else ok "guard message hides the value" clean clean; fi
ok "guard blocks Edit to .claude-docs" "$(g Edit "$(J file_path /r/.claude-docs/g.md new_string "$ANT")")" 2
ok "guard allows removing a secret" "$(g Edit "$(J file_path "$M/SESSION.md" old_string "$GH" new_string secret://x)")" 0
ok "guard allows a reference" "$(g Write "$(J file_path "$M/SESSION.md" content 'use secret://db')")" 0
ok "guard covers the memory home" "$(g Write "$(J file_path "$T/data/projects/a/notes.md" content "$GH")")" 2
ok "guard ignores non-memory paths" "$(g Write "$(J file_path /r/src/app.env content "$GH")")" 0
ok "guard blocks Bash redirect to memory" "$(g Bash "$(J command "echo $GH >> $M/SESSION.md")")" 2
ok "guard allows reading memory" "$(g Bash "$(J command "grep $GH $M/SESSION.md")")" 0
ok "guard allows Bash elsewhere" "$(g Bash "$(J command "echo $GH > /tmp/x")")" 0
ok "guard ignores a mention in a heredoc" "$(g Bash "$(J command "cat > /tmp/test.sh <<X
url $GH in $M/SESSION.md
X")")" 0
ok "guard blocks sed -i on memory" "$(g Bash "$(J command "sed -i s/a/$GH/ $M/SESSION.md")")" 2
ok "guard blocks tee on memory" "$(g Bash "$(J command "echo $GH | tee -a $M/SESSION.md")")" 2
ok "guard blocks an append to any file in the data dir" "$(g Bash "$(J command "echo $GH >> $T/data/projects/a/notes.md")")" 2
# Approval of the data dir
dec() { gj "$1" "$2" | ms guard 2>/dev/null | python3 -c 'import json,sys; s=sys.stdin.read(); print(json.loads(s)["hookSpecificOutput"]["permissionDecision"] if s.strip() else "none")'; }
mkdir -p "$T/data/p" "$T/outside"; ln -s "$T/outside" "$T/data/link"
ok "allow: Write in data" "$(dec Write "$(J file_path "$T/data/p/SESSION.md" content ok)")" allow
ok "allow: Read in data" "$(dec Read "$(J file_path "$T/data/p/SESSION.md")")" allow
ok "allow: Edit in data" "$(dec Edit "$(J file_path "$T/data/p/SESSION.md" new_string ok)")" allow
ok "no allow: outside" "$(dec Write "$(J file_path "$T/other/x.md" content ok)")" none
ok "no allow: dot-dot escape" "$(dec Write "$(J file_path "$T/data/../outside/x.md" content ok)")" none
ok "no allow: symlink escape" "$(dec Write "$(J file_path "$T/data/link/x.md" content ok)")" none
ok "no allow: prefix sibling" "$(dec Write "$(J file_path "$T/data-evil/x.md" content ok)")" none
ok "no allow: secret store" "$(dec Read "$(J file_path "$T/store/gh-token")")" none
ok "no allow: Bash" "$(dec Bash "$(J command 'echo ok')")" none
ok "guard fails open on bad JSON" "$(echo 'not json' | ms guard 2>/dev/null; echo $?)" 0

echo; [[ $fail -eq 0 ]] && echo "all $n passed" || echo "FAILED"
exit $fail
