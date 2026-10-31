#!/usr/bin/env bash
# SessionStart hook: refresh the search index in the background, then tell the
# agent what to read. All logic is in bin/memory-3layer, shared by every harness.
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/memory-3layer"

# A hook runs without the shell's PATH additions, and qmd needs node.
for p in "$HOME/.npm-global/bin" /usr/local/bin /opt/homebrew/bin; do
  [[ -d "$p" ]] && PATH="$p:$PATH"
done
export PATH

# The hook's JSON has to reach `context`, and git or ssh below would swallow stdin.
input=""
[[ -t 0 ]] || input=$(timeout 1 cat 2>/dev/null || true)
exec </dev/null

( bash "$BIN" refresh --debounce >/dev/null 2>&1 & )
# Latest data first, with a short limit: a storage that is down must not delay the
# session. What this machine has not sent yet goes out in the background.
bash "$BIN" sync --pull --quiet >/dev/null 2>&1
( bash "$BIN" sync --quiet >/dev/null 2>&1 & )
exec bash "$BIN" context <<< "$input"
