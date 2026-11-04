#!/usr/bin/env bash
# PreCompact hook: remind the agent to flush SESSION.md before compaction.
# PreCompact takes a top-level systemMessage, not hookSpecificOutput.additionalContext.
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/memory-3layer"
( bash "$BIN" sync --quiet >/dev/null 2>&1 & )
dir=$(bash "$BIN" path project)
if [[ -f "$dir/CORE.md" || -d "$dir/_tasks" ]]; then
  printf '{"systemMessage":"PRE-COMPACT FLUSH REQUIRED. Before compaction, record where the work stands: memory-3layer task log <name> next, and decision or blocker if there is one. Open a task if this work has none, so the session is bound to it. Close a task whose work is done. Move anything that must outlive the task into %s/CORE.md."}\n' "$dir"
  exit 0
fi
session=$dir/SESSION.md
printf '{"systemMessage":"PRE-COMPACT FLUSH REQUIRED. Before compaction, update %s: Goal, State (branch/last/next), Decisions with rationale, File map, Open questions, Blockers, and Recent turns (last ~5 user turns verbatim plus one line on what you did). It is the only artifact that survives compaction with full fidelity. Read it first after compaction."}\n' "$session"
