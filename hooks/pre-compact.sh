#!/usr/bin/env bash
# PreCompact hook: remind the agent to flush SESSION.md before compaction.
# PreCompact takes a top-level systemMessage, not hookSpecificOutput.additionalContext.
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/memory-3layer"
( bash "$BIN" sync --quiet >/dev/null 2>&1 & )
dir=$(bash "$BIN" path project)
if [[ -f "$dir/CORE.md" || -d "$dir/_tasks" ]]; then
  # A session long enough to be compacted that has written to no task leaves nothing behind.
  input=""; [[ -t 0 ]] || IFS= read -r -d '' -t 1 input || true
  none=""
  if [[ "$input" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]+)\" && ! -f "$(bash "$BIN" path state)/bindings/${BASH_REMATCH[1]}" ]]; then
    none="THIS SESSION HAS WRITTEN TO NO TASK, and after compaction only the summary of it remains. Open one now, or log to the open task this work belongs to: what was done, what was decided, what changed outside the repository, and the next step. "
  fi
  printf '{"systemMessage":"%sPRE-COMPACT FLUSH REQUIRED. Before compaction, record where the work stands: memory-3layer task log <name> next, and decision or blocker if there is one. Open a task if this work has none, so the session is bound to it. If a checkpoint is due on the task, write it now, while the whole context is still here. Close a task whose work is done. Move anything that must outlive the task into %s/CORE.md."}\n' "$none" "$dir"
  exit 0
fi
session=$dir/SESSION.md
printf '{"systemMessage":"PRE-COMPACT FLUSH REQUIRED. Before compaction, update %s: Goal, State (branch/last/next), Decisions with rationale, File map, Open questions, Blockers, and Recent turns (last ~5 user turns verbatim plus one line on what you did). It is the only artifact that survives compaction with full fidelity. Read it first after compaction."}\n' "$session"
