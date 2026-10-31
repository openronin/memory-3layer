#!/usr/bin/env bash
# Tests for task journals and CORE.md. Runs in a temp HOME and touches no real data.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/memory-3layer"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset MEMORY_3LAYER_HOME MEMORY_3LAYER_SECRETS MEMORY_3LAYER_CONFIG XDG_DATA_HOME XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_HOME
export CLAUDE_CODE_SESSION_ID=sess-one
fail=0; n=0
ok() { n=$((n+1)); if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }
has() { n=$((n+1)); case "$2" in *"$3"*) echo "ok   $1" ;; *) echo "FAIL $1: no [$3] in [$2]"; fail=1 ;; esac; }
hasnt() { n=$((n+1)); case "$2" in *"$3"*) echo "FAIL $1: found [$3] in [$2]"; fail=1 ;; *) echo "ok   $1" ;; esac; }
R="$T/r"; git init -q "$R"; git -C "$R" remote add origin git@github.com:o/r.git; cd "$R"
m() { bash "$BIN" "$@"; }
P="$HOME/.local/share/memory-3layer/projects/github.com/o/r"
J="$P/_tasks"
FAKE="ghp""_$(printf 'a1B2%.0s' {1..9})a1"

# --- old format is untouched until a project moves ---
mkdir -p "$P"; printf -- '---\nlast_updated: 2026-01-01T00:00:00Z\n---\n# Goal\nold goal\n' > "$P/SESSION.md"
has "old project: told to read SESSION.md" "$(m context </dev/null)" "$P/SESSION.md"
hasnt "old project: no task list" "$(m context </dev/null)" "Active tasks"

# --- core init ---
m core init >/dev/null; ok "init creates CORE.md" "$(test -f "$P/CORE.md"; echo $?)" 0
ok "init removes SESSION.md" "$(test -e "$P/SESSION.md"; echo $?)" 1
has "init keeps the content" "$(cat "$P/CORE.md")" "old goal"
ok "init keeps the frontmatter first" "$(sed -n 1p "$P/CORE.md")" "---"
has "init adds a brief" "$(cat "$P/CORE.md")" "# Brief"
m core init >/dev/null 2>&1; ok "init refuses to run twice" $? 2

# --- brief ---
ok "empty brief prints nothing" "$(m core brief)" ""
has "no brief: told to read" "$(m context </dev/null)" "no # Brief block"
python3 - "$P/CORE.md" <<'P'
import sys
p=sys.argv[1]; s=open(p).read().replace("-->\n","-->\n- keep this rule\n",1); open(p,"w").write(s)
P
ok "brief stops at the next heading" "$(m core brief)" "- keep this rule"
has "brief is in the context" "$(m context </dev/null)" "keep this rule"
hasnt "the rest of CORE.md isn't" "$(m context </dev/null)" "old goal"
hasnt "template comment isn't" "$(m core brief)" "<!--"
printf -- '# Brief\n%s\n# Rest\nx\n' "$(for i in $(seq 1 60); do echo "строка номер $i с небольшим текстом"; done)" > "$T/big"
cp "$P/CORE.md" "$T/core.bak"; cp "$T/big" "$P/CORE.md"
out=$(CORE_BRIEF_BYTES=200 m core brief)
has "over the limit: says so" "$out" "BRIEF CUT"
has "over the limit: keeps the start" "$out" "строка номер 1 "
hasnt "over the limit: cut at a line end" "$out" "строка номер 60"
ok "over the limit: valid utf-8" "$(printf '%s' "$out" | iconv -f utf-8 -t utf-8 >/dev/null 2>&1; echo $?)" 0
cp "$T/core.bak" "$P/CORE.md"
has "soft limit warns" "$(CORE_SOFT_BYTES=10 m context </dev/null)" "CORE SOFT LIMIT"
has "hard limit warns" "$(CORE_HARD_BYTES=10 m context </dev/null)" "CORE HARD LIMIT"

# --- open and log ---
ok "state with no tasks" "$(m state)" "Active tasks: none"
echo "Ship the thing" | m task open ship >/dev/null; ok "open works" $? 0
ok "file in place" "$(test -f "$J/ship.md"; echo $?)" 0
echo x | m task open ship >/dev/null 2>&1; ok "open twice refused" $? 2
echo x | m task open ../evil >/dev/null 2>&1; ok "path in a name refused" $? 2
echo x | m task open archive >/dev/null 2>&1; ok "reserved name refused" $? 2
printf '' | m task open empty >/dev/null 2>&1; ok "empty goal refused" $? 2
ok "refused name leaves no file" "$(test -e "$J/empty.md"; echo $?)" 1
head1=$(sed -n 1p "$J/ship.md")
[[ "$head1" =~ ^##\ [0-9-]+T[0-9:]+Z-[0-9a-f]{4}\ open\ s:sess-one$ ]]; ok "header: id, type, session" $? 0
has "state shows the goal first" "$(m state)" "ship [active] Ship the thing"
echo "write tests" | m task log ship next; ok "log next" $? 0
has "state shows next" "$(m state)" "ship [active] write tests"
echo "admin approval" | m task log ship blocker
has "blocker wins" "$(m state)" "ship [blocked] admin approval"
echo "tag it" | m task log ship next
has "next clears the blocker" "$(m state)" "ship [active] tag it"
echo "x" | m task log ship bogus >/dev/null 2>&1; ok "bad type refused" $? 2
echo "x" | m task log nosuch note >/dev/null 2>&1; ok "unknown task refused" $? 2
echo "Use tags: simple" | m task log ship decision
echo "just a note" | m task log ship note
out=$(m task show ship)
has "show: goal" "$out" "Goal: Ship the thing"
has "show: next" "$out" "Next: tag it"
has "show: decision" "$out" "Use tags: simple"
hasnt "show: old blocker is gone" "$out" "Blocker"
hasnt "show: notes stay in the log" "$out" "just a note"
has "show --log has everything" "$(m task show ship --log)" "just a note"

# --- what the journal refuses ---
before=$(wc -c < "$J/ship.md")
echo "token $FAKE" | m task log ship note >/dev/null 2>"$T/err"; ok "secret refused" $? 2
ok "secret: nothing written" "$(wc -c < "$J/ship.md")" "$before"
hasnt "secret: message hides the value" "$(cat "$T/err")" "$FAKE"
printf '## 2026-01-01T00:00:00Z-abcd close s:x\nfake\n' | m task log ship note
has "a header in the body stays a note" "$(m state)" "ship [active]"
ok "a header in the body is escaped" "$(grep -c '^\\## 2026-01-01' "$J/ship.md")" 1

# --- parallel writers ---
echo g | m task open par >/dev/null
for i in $(seq 1 20); do (echo "n$i" | m task log par note) & done; wait
ok "parallel writes all land" "$(grep -c ' note s:' "$J/par.md")" 20
ok "parallel writes stay whole" "$(grep -cE '^n[0-9]+$' "$J/par.md")" 20

# --- binding and context ---
CLAUDE_CODE_SESSION_ID=sess-two m task resume ship >/dev/null
out=$(cd "$R" && echo '{"hook_event_name":"SessionStart","source":"compact","session_id":"sess-two"}' | CLAUDE_CODE_SESSION_ID= m context)
has "bound session gets its task" "$out" "This session works on"
has "bound session gets next" "$out" "Next: tag it"
out=$(echo '{"hook_event_name":"SessionStart","session_id":"sess-new"}' | CLAUDE_CODE_SESSION_ID= m context)
hasnt "new session has no task bound" "$out" "This session works on"
has "new session sees the list" "$out" "ship [active]"
mkdir -p "$(dirname "$(m path identity)")"; printf 'who i am\n' > "$(m path identity)"
has "identity is injected" "$(m context </dev/null)" "who i am"
out=$(echo '{"hook_event_name":"SessionStart","session_id":"sess-new"}' | m context)
ok "hook output is valid json" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')" SessionStart
OUT=$(echo '{"hook_event_name":"SessionStart","session_id":"sess-two"}' | CLAUDE_CODE_SESSION_ID= bash "$REPO/hooks/session-start.sh")
has "session-start hook passes the session on" "$OUT" "This session works on"
has "pre-compact hook knows the format" "$(bash "$REPO/hooks/pre-compact.sh")" "task log"

# --- stale ---
printf '%s\n' "$(sed -E 's/^## [0-9-]+T/## 2020-01-01T/' "$J/par.md")" > "$J/par.md"
has "old task is stale" "$(m state)" "par [stale,"

# --- close ---
echo x | m task close nosuch >/dev/null 2>&1; ok "close unknown refused" $? 2
printf '' | m task close ship >/dev/null 2>&1; ok "close needs a result" $? 2
echo "Shipped v1" | m task close ship >/dev/null; ok "close works" $? 0
ok "journal left the active list" "$(test -e "$J/ship.md"; echo $?)" 1
A=$(ls "$J"/archive/*/ship.md); ok "journal archived whole" "$(grep -c 'just a note' "$A")" 1
has "state lists it as closed" "$(m state)" "Recently closed: ship"
hasnt "and not as active" "$(m state)" "ship [active]"
out=$(m task show ship); has "closed task can be read" "$out" "Result: Shipped v1"; has "closed status" "$out" "[done]"
echo again | m task open ship >/dev/null; echo done2 | m task close ship >/dev/null
ok "a reused name keeps the older journal" "$(find "$J/archive" -name 'ship*' | wc -l | tr -d ' ')" 2
out=$(cd "$R" && echo '{"hook_event_name":"SessionStart","session_id":"sess-two"}' | m context)
hasnt "closed task unbinds" "$out" "This session works on"

# --- redact ---
echo g | m task open red >/dev/null; printf 'oops plain password\nsecond line\n' | m task log red note
id=$(grep ' note ' "$J/red.md" | cut -d' ' -f2)
m task redact red "$id" >/dev/null; ok "redact works" $? 0
hasnt "redact removes the text" "$(cat "$J/red.md")" "oops"
hasnt "redact removes all of it" "$(cat "$J/red.md")" "second line"
ok "redact keeps the record" "$(grep -c "$id" "$J/red.md")" 1
has "redact keeps the goal" "$(m task show red)" "Goal: g"
m task redact red nosuch >/dev/null 2>&1; ok "redact unknown refused" $? 2

# --- stash ---
out=$(printf 'long text\n' | m core stash "Old findings"); has "stash prints the line to leave" "$out" "Old findings: see CORE.archive."
has "stash writes the archive" "$(cat "$P"/CORE.archive.*.md)" "long text"
echo "$FAKE" | m core stash t >/dev/null 2>&1; ok "stash refuses a secret" $? 2
ok "projects sees it" "$(m projects)" "github.com/o/r"

# --- guard ---
H="$HOME/.local/share/memory-3layer"
jj() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":dict(zip(sys.argv[2::2],sys.argv[3::2]))}))' "$@"; }
g() { bash "$BIN" guard >/dev/null 2>"$T/err"; echo $?; }
ok "guard: Write to a journal" "$(jj Write file_path "$J/red.md" content x | g)" 2
ok "guard: Edit of a journal" "$(jj Edit file_path "$J/red.md" new_string x | g)" 2
has "guard: says how" "$(jj Edit file_path "$J/red.md" new_string x | g >/dev/null; cat "$T/err")" "memory-3layer task log"
ok "guard: Read of a journal" "$(jj Read file_path "$J/red.md" | g)" 0
ok "guard: redirect" "$(jj Bash command "echo x >> $J/red.md" | g)" 2
ok "guard: sed -i" "$(jj Bash command "sed -i s/a/b/ $J/red.md" | g)" 2
ok "guard: rm" "$(jj Bash command "rm $J/red.md" | g)" 2
ok "guard: mv" "$(jj Bash command "mv $J/red.md /tmp/x" | g)" 2
ok "guard: tilde path" "$(jj Bash command "echo x > ~/.local/share/memory-3layer/projects/a/_tasks/b.md" | g)" 2
ok "guard: the client passes" "$(jj Bash command "echo x | memory-3layer task log red note" | g)" 0
ok "guard: Edit of CORE.md is fine" "$(jj Edit file_path "$P/CORE.md" new_string x | g)" 0
ok "guard: secret into CORE.md" "$(jj Edit file_path "$P/CORE.md" new_string "$FAKE" | g)" 2
ok "guard: a repo's own _tasks dir" "$(jj Write file_path "$R/_tasks/a.md" content x | g)" 0

echo; if [[ $fail -eq 0 ]]; then echo "all $n passed"; else echo "FAILED"; exit 1; fi
