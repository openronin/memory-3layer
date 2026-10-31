#!/usr/bin/env bash
# Builds an installable package for one harness: the harness files from harness/<name>/ plus real
# copies of what every package carries. The package repositories hold exactly this output.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
usage() { echo "usage: tools/package.sh <claude-code|codex> <output directory>" >&2; exit 2; }

name="${1:-}"; out="${2:-}"
[ -n "$name" ] && [ -n "$out" ] || usage
src="$ROOT/harness/$name"
[ -d "$src" ] || { echo "no harness $name in $ROOT/harness" >&2; exit 1; }

case "$name" in
  claude-code) title="Claude Code plugin"; manifest=".claude-plugin/plugin.json"
    install='```
/plugin marketplace add openronin/memory-3layer-claude-code
/plugin install memory-3layer@memory-3layer
```' ;;
  codex) title="Codex CLI plugin"; manifest=".codex-plugin/plugin.json"
    install='```bash
codex plugin marketplace add openronin/memory-3layer-codex
codex plugin add memory-3layer@memory-3layer
```

Then trust the hooks in `/hooks`, and allow writes to the memory directory: see
[docs/codex.md](https://github.com/openronin/memory-3layer/blob/main/docs/codex.md). This package has not yet been run on a real Codex.' ;;
  *) usage ;;
esac

# How a skill reaches the client: only Claude Code puts a plugin's bin/ on PATH.
case "$name" in
  claude-code)
    client='bash "$(command -v memory-3layer | xargs dirname)"/'
    naming='Slash commands named below are skills of this plugin: `/recall` is `/memory-3layer:recall`, and so on.' ;;
  codex)
    client='bash <directory of the Client path in the session context>/'
    naming='Slash commands named below are skills of this plugin: `/recall` is `$recall`, and so on. A `memory-3layer` command means the Client path in the session context.' ;;
esac

rm -rf "$out"; mkdir -p "$out"
# the harness files: manifests and hooks. The importer goes where the client looks for it.
(cd "$src" && find . -mindepth 1 -maxdepth 1 ! -name import-memory -exec cp -R {} "$out/" \;)
if [ -f "$src/import-memory" ]; then
  mkdir -p "$out/harness/$name"; cp "$src/import-memory" "$out/harness/$name/"; chmod +x "$out/harness/$name/import-memory"
fi
# the shared part, dereferenced: a package must stand on its own
for shared in bin templates LICENSE; do cp -RL "$ROOT/$shared" "$out/$shared"; done
cp "$ROOT/memory/IDENTITY.md" "$out/templates/IDENTITY.template.md"
chmod +x "$out"/bin/*
mkdir -p "$out/scripts"; cp "$ROOT"/hooks/*.sh "$out/scripts/"; chmod +x "$out"/scripts/*

# Skills are built from the commands and the protocol, so the two can't drift apart.
# An installed plugin has bin/ on PATH and calls its commands by name.
for c in "$ROOT"/commands/*.md; do
  n=$(basename "$c" .md); mkdir -p "$out/skills/$n"
  { printf -- '---\nname: %s\n' "$n"; sed '1d' "$c" | sed "s#bash ~/\.claude/bin/#$client#"; } > "$out/skills/$n/SKILL.md"
done
mkdir -p "$out/skills/protocol"
{
  cat <<H
---
name: protocol
description: The full memory-3layer protocol - which layer a fact belongs to, how to keep SESSION.md, rotation, promotion, secrets. Read it when deciding where to save something, when wrapping up a task, before compaction, or when a memory warning appears.
---

$naming Templates are in the \`templates/\` directory of this plugin.

H
  sed -E 's#~/\.claude/dist/memory-3layer/templates/#the plugin'"'"'s `templates/` directory, #g' "$ROOT/CLAUDE.md"
} > "$out/skills/protocol/SKILL.md"

# the package is installed by a plain git clone: with core.autocrlf=true the client would arrive
# with CRLF and fail on "bash\r", so the package repository pins LF itself
printf '* text=auto eol=lf\n' > "$out/.gitattributes"

version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$out/$manifest" | head -1)
[ -n "$version" ] || { echo "no version in $manifest" >&2; exit 1; }

cat > "$out/README.md" <<EOF
# memory-3layer — $title

Agent memory that belongs to no harness: identity, project notes and working state, keyed by
repository and synced through git storages you choose.

$install

Restart the session after installing. Secrets never enter memory, and nothing leaves the machine
until you configure a storage. See [the main repository](https://github.com/openronin/memory-3layer).

## This repository is generated

Every file here is built from [openronin/memory-3layer](https://github.com/openronin/memory-3layer)
and overwritten on each release, so changes made here are lost. Issues and pull requests belong in
that repository; this one only ships version $version of the package.

[MIT](LICENSE)
EOF

echo "$name $version -> $out"
