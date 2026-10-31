#!/usr/bin/env bash
# install.sh — memory-3layer installer.
#
# Idempotent and upgrade-safe:
# - First install: lays out everything cleanly
# - Upgrade: backs up changed files with .bak-<timestamp>, NEVER overwrites
#   your IDENTITY.md (L0 user data) or projects/ tree (L1-fallback + L2)
# - Detects existing settings.json and prints merge instructions instead of
#   blindly overwriting hook config
#
# Usage:
#   ./install.sh            # installs to ~/.claude (or $CLAUDE_HOME if set)
#   ./install.sh --dry-run  # show what would change, write nothing

set -e

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
TS=$(date +%Y%m%d-%H%M%S)
SRC=$(cd "$(dirname "$0")" && pwd)
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# --- Helpers ---

say() { printf '%s\n' "$*"; }
do_or_dry() { if [[ $DRY_RUN -eq 1 ]]; then say "  [dry] $*"; else eval "$@"; fi; }

backup_and_install() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      say "  = $dst (unchanged)"
      return 0
    fi
    do_or_dry "cp '$dst' '$dst.bak-$TS'"
    say "  ~ $dst (backed up -> $dst.bak-$TS)"
  else
    say "  + $dst (new)"
  fi
  do_or_dry "mkdir -p '$(dirname "$dst")'"
  do_or_dry "cp '$src' '$dst'"
}

# --- Detect mode ---

mode="first-install"
[[ -f "$CLAUDE_HOME/CLAUDE.md" ]] && mode="upgrade"

say "=== memory-3layer installer ==="
say "Source:      $SRC"
say "Destination: $CLAUDE_HOME"
say "Mode:        $mode"
[[ $DRY_RUN -eq 1 ]] && say "[DRY RUN — no changes will be written]"
say ""

# --- Refuse to strand existing memory ---
# Hooks from this version read only the new location, so installing over a setup
# whose data has not moved would make all of that memory invisible to the agent.
DATA_HOME="${MEMORY_3LAYER_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/memory-3layer}"
if [[ ! -d "$DATA_HOME" ]] && { [[ -f "$CLAUDE_HOME/memory/IDENTITY.md" ]] || compgen -G "$CLAUDE_HOME/projects/*/memory/SESSION.md" >/dev/null; }; then
  say "STOP: memory from an older version is in $CLAUDE_HOME, and it has not moved to $DATA_HOME."
  say "This version would not see it. Nothing was changed."
  exit 1
fi

# --- Layout ---

CONFIG_FILE="${MEMORY_3LAYER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/memory-3layer/config}"

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/commands" "$CLAUDE_HOME/bin" \
           "$DATA_HOME/identity" "$DATA_HOME/projects" "$(dirname "$CONFIG_FILE")"
fi

# --- Protocol + tooling (safe to overwrite, backup if differs) ---

say "Protocol + tools:"
backup_and_install "$SRC/CLAUDE.md"                "$CLAUDE_HOME/CLAUDE.md"
for f in "$SRC/hooks/"*.sh;     do backup_and_install "$f" "$CLAUDE_HOME/hooks/$(basename "$f")";    done
for f in "$SRC/commands/"*.md;  do backup_and_install "$f" "$CLAUDE_HOME/commands/$(basename "$f")"; done
for f in "$SRC/bin/"*;          do backup_and_install "$f" "$CLAUDE_HOME/bin/$(basename "$f")";      done

for f in "$SRC/harness/"*/import-memory; do backup_and_install "$f" "$CLAUDE_HOME/harness/${f#"$SRC/harness/"}"; done

if [[ $DRY_RUN -eq 0 ]]; then
  chmod +x "$CLAUDE_HOME/harness/"*/* 2>/dev/null || true
  chmod +x "$CLAUDE_HOME/hooks/"*.sh "$CLAUDE_HOME/bin/"* 2>/dev/null || true
  mkdir -p "$HOME/.local/bin"
  ln -sf "$CLAUDE_HOME/bin/memory-3layer" "$HOME/.local/bin/memory-3layer"
fi
say ""

# --- IDENTITY.md (L0 — USER DATA, NEVER overwrite) ---

say "L0 identity:"
if [[ ! -f "$DATA_HOME/identity/IDENTITY.md" ]]; then
  do_or_dry "cp '$SRC/memory/IDENTITY.md' '$DATA_HOME/identity/IDENTITY.md'"
  say "  + $DATA_HOME/identity/IDENTITY.md (template, please edit)"
  say "  ★ EDIT THIS FILE (hard cap 25 lines: who you are, OS, prefs, env creds)"
else
  do_or_dry "cp '$SRC/memory/IDENTITY.md' '$DATA_HOME/identity/IDENTITY.template.md'"
  say "  = $DATA_HOME/identity/IDENTITY.md (preserved — your data)"
  say "    reference template available at: $DATA_HOME/identity/IDENTITY.template.md"
fi
say ""

# --- .memory-config (optional runtime config — USER DATA, never overwrite) ---

say "Runtime config:"
if [[ ! -f "$CONFIG_FILE" ]]; then
  do_or_dry "cp '$SRC/.memory-config.template' '$CONFIG_FILE'"
  say "  + $CONFIG_FILE (defaults — edit to tune L2 size limits)"
else
  do_or_dry "cp '$SRC/.memory-config.template' '$CONFIG_FILE.template'"
  say "  = $CONFIG_FILE (preserved — your settings)"
  say "    reference template available at: $CONFIG_FILE.template"
fi
say ""

# --- settings.json (NEVER auto-merge, just guide) ---

say "settings.json:"
if [[ ! -f "$CLAUDE_HOME/settings.json" ]]; then
  do_or_dry "cp '$SRC/settings.snippet.json' '$CLAUDE_HOME/settings.json'"
  say "  + $CLAUDE_HOME/settings.json (fresh, with hooks)"
else
  if grep -q '"SessionStart"' "$CLAUDE_HOME/settings.json" 2>/dev/null && \
     grep -q '"PreCompact"'   "$CLAUDE_HOME/settings.json" 2>/dev/null; then
    say "  = $CLAUDE_HOME/settings.json (already has SessionStart + PreCompact hooks)"
  else
    say "  ⚠ $CLAUDE_HOME/settings.json exists but is missing one or both hooks"
    say "    Merge the 'hooks' block from $SRC/settings.snippet.json manually."
    say "    Do NOT duplicate the top-level 'hooks' key — merge into existing one."
  fi
fi
if [[ -f "$CLAUDE_HOME/settings.json" ]] && ! grep -q 'memory-3layer guard' "$CLAUDE_HOME/settings.json" 2>/dev/null; then
  say "  ⚠ the secret guard is not enabled: without it, nothing blocks secrets from being written to memory"
  say "    Merge the 'PreToolUse' entry from $SRC/settings.snippet.json into the existing 'hooks' key."
fi
say ""

# --- L1-fallback + L2 (NEVER touch) ---

say "L1-fallback + L2 sessions:"
say "  = $DATA_HOME/projects/ (untouched — your project + session memory)"
say ""

# --- Backup summary ---

backups=$(find "$CLAUDE_HOME" -name "*.bak-$TS" 2>/dev/null | sort)
if [[ -n "$backups" ]]; then
  say "Backups created (timestamp $TS):"
  while IFS= read -r b; do say "  - $b"; done <<< "$backups"
  say ""
fi

# --- Next steps ---

say "=== Done ($mode) ==="
say ""
say "Next steps:"
if [[ ! -f "$DATA_HOME/identity/IDENTITY.md" ]] || \
   grep -q "<your name" "$DATA_HOME/identity/IDENTITY.md" 2>/dev/null; then
  say "  1. Edit $DATA_HOME/identity/IDENTITY.md (≤25 lines)"
fi
say "  2. Optional: install retrieval tools (qmd, ctags, ripgrep) — see INSTALL.md"
say "  3. Start a new Claude Code session — hooks fire automatically"
say ""
say "To rollback to backed-up versions:"
say "  for f in $CLAUDE_HOME/**/*.bak-$TS; do mv \"\$f\" \"\${f%.bak-$TS}\"; done"
