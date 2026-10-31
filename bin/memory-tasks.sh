#!/usr/bin/env bash
# memory-tasks.sh — task journals and CORE.md. Design: docs/tasks.md.
# Run through `memory-3layer task|state|core`.
#
# A journal is append-only markdown: a strict header per record, free text below it.
# Only this script writes journals, so it owns the id, the time and the session, and
# the guard refuses every other writer.

set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
PD="${MEMORY_3LAYER_PROJECT:?}"
KEY="${MEMORY_3LAYER_KEY:?}"
STATE="${MEMORY_3LAYER_STATE:?}"
TASKS="$PD/_tasks"
ARCHIVE="$TASKS/archive"
CORE="$PD/CORE.md"
STALE_DAYS="${TASK_STALE_DAYS:-7}"
BRIEF_BYTES="${CORE_BRIEF_BYTES:-5000}"
CORE_SOFT="${CORE_SOFT_BYTES:-20000}"
CORE_HARD="${CORE_HARD_BYTES:-40000}"
RECENT=5
SESSION="${CLAUDE_CODE_SESSION_ID:-}"

# No {n} intervals: mawk doesn't take them everywhere.
HEADER='^## [0-9-]+T[0-9:]+Z-[0-9a-f]+ (open|note|decision|next|blocker|close) s:[^ ]+$'

die() { printf 'memory-3layer: %s\n' "$*" >&2; exit 2; }

valid_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ && "$1" != archive && "$1" != *.. && "$1" != *..* ]] || die "bad task name '$1' (lowercase letters, digits, . _ -)"
}

read_body() {
  # The body comes through stdin, so an agent can't trip over shell quoting.
  [[ ! -t 0 ]] || die "$1 comes from stdin"
  BODY=$(cat)
  [[ "$BODY" =~ [^[:space:]] ]] || die "$1 is empty"
  scan "$BODY"
  # A line shaped like a header would split the record when it is read back.
  BODY=$(printf '%s\n' "$BODY" | sed -E "/$HEADER/s/^/\\\\/")
}

scan() {
  # A whole record is refused on a finding. Only the kind is reported, never the value.
  local tmp out kinds
  tmp=$(mktemp); printf '%s\n' "$1" > "$tmp"
  out=$(bash "$SELF_DIR/memory-secrets.sh" scan "$tmp"); local rc=$?
  rm -f "$tmp"
  if [[ $rc -ne 0 ]]; then
    kinds=$(printf '%s\n' "$out" | cut -f2 | sort -u | paste -sd, -)
    die "refused: this contains a secret ($kinds). Store it with 'memory-3layer secret put <name>' and write secret://<name>."
  fi
}

with_lock() {
  # mkdir is atomic and needs no flock, which macOS doesn't have.
  local lock="$STATE/locks/$(printf '%s' "$1" | cksum | cut -d' ' -f1)" i rc
  shift
  mkdir -p "$STATE/locks"
  [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] && rmdir "$lock" 2>/dev/null
  for i in {1..100}; do mkdir "$lock" 2>/dev/null && break; sleep 0.05; done
  [[ -d "$lock" ]] || die "cannot lock the journal"
  "$@"; rc=$?
  rmdir "$lock" 2>/dev/null
  return $rc
}

record_id() { printf '%s-%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"; }

append() {
  # append <file> <type> <body>
  local s=${SESSION:0:8}
  printf '## %s %s s:%s\n%s\n\n' "$(record_id)" "$2" "${s:--}" "$3" >> "$1"
}

active_file() { printf '%s/%s.md' "$TASKS" "$1"; }

find_task() {
  # The active journal, or the newest archived one with this name.
  local f; f=$(active_file "$1")
  [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
  f=$(find "$ARCHIVE" -type f -name "$1*.md" 2>/dev/null | grep -E "/$1(\.[0-9T:Z-]+)?\.md$" | sort | tail -n1)
  [[ -n "$f" ]] && { printf '%s' "$f"; return 0; }
  return 1
}

need_active() {
  local f; f=$(active_file "$1")
  [[ -f "$f" ]] || die "no active task '$1'. Active: $(ls "$TASKS" 2>/dev/null | sed -n 's/\.md$//p' | paste -sd' ' -)"
  printf '%s' "$f"
}

# --- reading ------------------------------------------------------------------

summary() {
  # status <TAB> last time <TAB> goal <TAB> next <TAB> blocker: first lines only.
  awk -v h="$HEADER" '
    $0 ~ h { t = $3; last = $2; want = 1; if (t == "next" || t == "blocker") kind = t; if (t == "close") closed = 1; next }
    want && NF {
      if (t == "open") goal = $0; else if (t == "next") nx = $0; else if (t == "blocker") bl = $0
      want = 0
    }
    END {
      s = closed ? "done" : (kind == "blocker" ? "blocked" : "active")
      printf "%s\t%s\t%s\t%s\t%s\n", s, last, goal, nx, bl
    }' "$1"
}

age_days() {
  local e; e=$(date -d "${1%-*}" +%s 2>/dev/null) || { echo 0; return; }
  echo $(( ($(date +%s) - e) / 86400 ))
}

index() {
  # The list a session starts with: one line per active task, then the recent closed ones.
  local f slug status last goal nx bl days text closed
  if compgen -G "$TASKS/*.md" >/dev/null; then
    echo "Active tasks:"
    for f in "$TASKS"/*.md; do
      slug=${f##*/}; slug=${slug%.md}
      IFS=$'\x1f' read -r status last goal nx bl < <(summary "$f" | tr '\t' '\037')
      text=$nx; [[ "$status" == blocked ]] && text=$bl; [[ -n "$text" ]] || text=$goal
      days=$(age_days "$last")
      [[ "$days" -ge "$STALE_DAYS" ]] && status="stale, ${days}d"
      printf '  %s [%s] %s\n' "$slug" "$status" "$text"
    done
  else
    echo "Active tasks: none"
  fi
  closed=$(find "$ARCHIVE" -type f -name '*.md' 2>/dev/null | while IFS= read -r f; do
      slug=${f##*/}; printf '%s\t%s\n' "$(grep -E "$HEADER" "$f" | tail -n1 | cut -d' ' -f2)" "${slug%.md}"
    done | sort -r | head -n "$RECENT" | cut -f2 | paste -sd, - | sed 's/,/, /g')
  [[ -z "$closed" ]] || printf 'Recently closed: %s\n' "$closed"
}

show() {
  # The state of a task: everything an agent needs to continue, and no history.
  local slug=$1 f status; f=$2
  status=$(summary "$f" | cut -f1)
  printf 'Task %s [%s]\n' "$slug" "$status"
  awk -v h="$HEADER" '
    $0 ~ h {
      t = $3; n++
      if (t == "next") nx = ""; else if (t == "blocker") bl = ""
      else if (t == "decision" && dec != "") dec = dec "\n"
      if (t == "decision") dec = dec "- " substr($2, 1, 10) ": "
      if (t == "blocker") kind = t; else if (t == "next") kind = t
      fresh = 1; next
    }
    {
      if (fresh && $0 == "") next
      line = fresh ? $0 : "\n" $0; fresh = 0
      if (t == "open") goal = goal line
      else if (t == "next") nx = nx line
      else if (t == "blocker") bl = bl line
      else if (t == "decision") dec = dec line
      else if (t == "close") res = res line
    }
    END {
      sub(/\n+$/, "", goal); sub(/\n+$/, "", nx); sub(/\n+$/, "", bl); sub(/\n+$/, "", res); gsub(/\n\n+/, "\n", dec)
      if (goal != "") print "Goal: " goal
      if (kind == "blocker" && bl != "") print "Blocker: " bl
      if (nx != "") print "Next: " nx
      if (dec != "") print "Decisions:\n" dec
      if (res != "") print "Result: " res
      print "(" n " records; --log shows them all)"
    }' "$f"
}

# --- task commands ------------------------------------------------------------

bind() {
  # Which task a session works on, so a compaction can bring it back. Belongs to this
  # machine, like the session itself, so it stays out of the data directory.
  [[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  mkdir -p "$STATE/bindings"
  printf '%s\t%s\n' "$KEY" "$1" > "$STATE/bindings/$SESSION"
}

bound_slug() {
  [[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ && -f "$STATE/bindings/$SESSION" ]] || return 1
  local k s
  IFS=$'\t' read -r k s < "$STATE/bindings/$SESSION"
  [[ "$k" == "$KEY" && -f "$(active_file "$s")" ]] || return 1
  printf '%s' "$s"
}

cmd_open() {
  [[ $# -eq 1 ]] || die "usage: task open <name>, the goal on stdin"
  valid_slug "$1"
  local f; f=$(active_file "$1")
  [[ ! -e "$f" ]] || die "task '$1' is already open"
  read_body "the goal"
  mkdir -p "$TASKS"
  with_lock "$f" append "$f" open "$BODY" || die "cannot write $f"
  bind "$1"
  echo "opened $1"
}

cmd_log() {
  [[ $# -eq 2 ]] || die "usage: task log <name> <note|decision|next|blocker>, the text on stdin"
  case "$2" in note|decision|next|blocker) ;; *) die "bad record type '$2': note, decision, next or blocker" ;; esac
  valid_slug "$1"
  local f; f=$(need_active "$1") || exit 2
  read_body "the record"
  with_lock "$f" append "$f" "$2" "$BODY" || die "cannot write $f"
  bind "$1"
  return 0
}

cmd_resume() {
  [[ $# -eq 1 ]] || die "usage: task resume <name>"
  valid_slug "$1"
  local f; f=$(need_active "$1") || exit 2
  bind "$1" || echo "(no session id, so this session stays unbound: pass --session)"
  show "$1" "$f"
}

cmd_show() {
  [[ $# -ge 1 ]] || die "usage: task show <name> [--log]"
  valid_slug "$1"
  local f; f=$(find_task "$1") || die "no task '$1'"
  if [[ "${2:-}" == --log ]]; then cat "$f"; else show "$1" "$f"; fi
}

close_locked() {
  local f=$1 dest=$2
  append "$f" close "$BODY" && mkdir -p "${dest%/*}" && mv "$f" "$dest"
}

cmd_close() {
  [[ $# -eq 1 ]] || die "usage: task close <name>, the result on stdin"
  valid_slug "$1"
  local f dest; f=$(need_active "$1") || exit 2
  read_body "the result"
  dest="$ARCHIVE/$(date -u +%Y-%m)/$1.md"
  # A name can be used again: the older journal keeps its place.
  [[ -e "$dest" ]] && dest="${dest%.md}.$(date -u +%Y-%m-%dT%H-%M-%SZ).md"
  with_lock "$f" close_locked "$f" "$dest" || die "cannot archive $f"
  printf 'closed %s -> %s\n' "$1" "${dest#"$PD"/}"
}

redact_locked() {
  local f=$1 id=$2 tmp
  tmp=$(mktemp) || return 1
  awk -v h="$HEADER" -v id="$id" '
    $0 ~ h { skip = 0; print; if ($2 == id) { print "[redacted]"; print ""; skip = 1; hit = 1 } ; next }
    !skip { print }
    END { exit hit ? 0 : 3 }' "$f" > "$tmp"
  local rc=$?
  if [[ $rc -eq 0 ]]; then cat "$tmp" > "$f"; fi
  rm -f "$tmp"
  return $rc
}

cmd_redact() {
  # The one way to change a record: for a secret the scanner missed.
  [[ $# -eq 2 ]] || die "usage: task redact <name> <record id>"
  valid_slug "$1"
  local f; f=$(find_task "$1") || die "no task '$1'"
  with_lock "$f" redact_locked "$f" "$2" || die "no record '$2' in '$1'"
  echo "redacted. If this was synced, the value stays in the storage's git history: replace it."
}

# --- CORE.md ------------------------------------------------------------------

brief() {
  # The # Brief block, without template comments, cut to the limit at a line end.
  # Prints nothing if there is none. The notice is part of the output, so a cut can't
  # go unnoticed.
  local text cut
  [[ -f "$CORE" ]] || return 0
  text=$(awk '
    /^# Brief[[:space:]]*$/ { on = 1; next }
    on && /^# / { exit }
    on && /^[[:space:]]*<!--.*-->[[:space:]]*$/ { next }
    on { print }' "$CORE")
  [[ "$text" =~ [^[:space:]] ]] || return 0
  if [[ $(printf '%s' "$text" | wc -c) -le $BRIEF_BYTES ]]; then
    printf '%s\n' "$text"
  else
    cut=$(printf '%s' "$text" | head -c "$BRIEF_BYTES" | sed '$d')
    printf '%s\n\nBRIEF CUT: the # Brief block of %s is over %d bytes, so the rest is missing above. Shorten it now.\n' "$cut" "$CORE" "$BRIEF_BYTES"
  fi
}

core_notes() {
  [[ -f "$CORE" ]] || return 0
  local bytes; bytes=$(wc -c < "$CORE" | tr -d ' ')
  if [[ "$CORE_HARD" -gt 0 && "$bytes" -ge "$CORE_HARD" ]]; then
    printf '\nCORE HARD LIMIT: CORE.md is %d KB. Before other work, shrink it: rewrite what is stale and move the rest out with `memory-3layer core stash`.\n' $((bytes / 1000))
  elif [[ "$CORE_SOFT" -gt 0 && "$bytes" -ge "$CORE_SOFT" ]]; then
    printf '\nCORE SOFT LIMIT: CORE.md is %d KB. At the next pause, shrink it: rewrite what is stale and move the rest out with `memory-3layer core stash`.\n' $((bytes / 1000))
  fi
}

cmd_context() {
  # What a session starts with for a project on this format.
  local b s
  index
  b=$(brief)
  if [[ -n "$b" ]]; then
    printf '\nBrief from %s:\n%s\n' "$CORE" "$b"
  elif [[ -f "$CORE" ]]; then
    printf '\n%s has no # Brief block: read the file before your first response, and add one.\n' "$CORE"
  fi
  core_notes
  if s=$(bound_slug); then
    printf '\nThis session works on:\n'
    show "$s" "$(active_file "$s")"
  fi
}

cmd_core() {
  local sub=${1:-}; [[ $# -gt 0 ]] && shift
  case "$sub" in
    init) core_init "$@" ;;
    stash) core_stash "$@" ;;
    brief) brief ;;
    *) die "usage: core init | stash <title> | brief" ;;
  esac
}

core_init() {
  # Put this project on the new format: SESSION.md becomes CORE.md, with an empty brief.
  local session="$PD/SESSION.md" tmp
  [[ ! -e "$CORE" ]] || die "$CORE already exists"
  mkdir -p "$PD"
  tmp=$(mktemp) || die "cannot write"
  local block='# Brief
<!-- Goes into the context of every session. Only what would make an agent go wrong without it. Save tokens. -->
'
  if [[ -f "$session" ]]; then
    awk -v b="$block" '
      NR == 1 && $0 == "---" { fm = 1; print; next }
      fm { print; if ($0 == "---") { fm = 0; print ""; print b } ; next }
      !done_ && !fm && NR == 1 { print b; done_ = 1 }
      { print }' "$session" > "$tmp"
    cat "$tmp" > "$CORE" && rm -f "$session"
    printf 'moved %s to %s. Fill in # Brief and move active work into tasks.\n' "$session" "$CORE"
  else
    { printf -- '---\ntags: [memory/l2, core]\n---\n\n%s\n' "$block"; } > "$CORE"
    printf 'created %s\n' "$CORE"
  fi
  rm -f "$tmp"
}

core_stash() {
  # Move text to the recall-only archive and print the link to leave behind.
  [[ $# -ge 1 ]] || die "usage: core stash <title>, the text on stdin"
  local title="$*" file
  [[ "$title" != *$'\n'* ]] || die "the title is one line"
  read_body "the text"
  scan "$title"
  file="CORE.archive.$(date -u +%Y-%m).md"
  mkdir -p "$PD"
  printf '# [%s] %s\n\n%s\n\n' "$(date -u +%Y-%m-%d)" "$title" "$BODY" >> "$PD/$file" || die "cannot write $file"
  printf 'Stashed. Remove the text from CORE.md and leave this line:\n- %s: see %s\n' "$title" "$file"
}

# --- dispatch -----------------------------------------------------------------

args=()
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --session ]]; then
    [[ $# -ge 2 ]] || die "--session needs an id"
    SESSION=$2; shift 2
  else
    args+=("$1"); shift
  fi
done
set -- ${args[@]+"${args[@]}"}

cmd=${1:-}; [[ $# -gt 0 ]] && shift
case "$cmd" in
  state) index ;;
  context) cmd_context ;;
  core) cmd_core "$@" ;;
  task)
    sub=${1:-}; [[ $# -gt 0 ]] && shift
    case "$sub" in
      open) cmd_open "$@" ;;
      log) cmd_log "$@" ;;
      resume) cmd_resume "$@" ;;
      show) cmd_show "$@" ;;
      close) cmd_close "$@" ;;
      redact) cmd_redact "$@" ;;
      *) die "usage: task open|log|resume|show|close|redact" ;;
    esac ;;
  *) die "usage: task ... | state | core ..." ;;
esac
