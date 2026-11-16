# Qwen Code

Status: run on Qwen Code 1.0.0-preview.1 (Linux, WSL2). The hook contract is Claude Code's: the same events, the same JSON on stdin, the same `hookSpecificOutput` on stdout, exit 2 blocks a tool call.

## Install

From a published package:

    qwen plugins marketplace add openronin/memory-3layer-qwen-code
    qwen plugins install memory-3layer@memory-3layer

Or from this repository, before a release:

    tools/package.sh qwen-code /tmp/memory-3layer-qwen
    qwen plugins install /tmp/memory-3layer-qwen

Restart the session. The install goes to user scope by default; `--scope project` and `--scope local` exist too. `qwen plugins list` shows the plugin enabled. Hooks need no separate trust step, and the guard approves clean writes inside the data directory, so no sandbox setting is needed.

A local install is updated by building again and running the same install command: it overwrites the cached copy under `~/.qwen/plugins/cache/`.

## What differs from Claude Code

- The repo entry file (L1a) is `AGENTS.md`, which Qwen Code auto-loads. The protocol skill and the repo templates are retargeted at build time: `CLAUDE.md` becomes `AGENTS.md`. `.claude-docs/` keeps its name, so a repo used by both harnesses shares one L1b. A repo that already has a `CLAUDE.md` can keep it and let `AGENTS.md` import it with `@CLAUDE.md` instead of duplicating the content.
- Tool names are the same (`Read`, `Write`, `Edit`, `Bash`), so the guard works unchanged. It also covers Qwen Code's own memory directories, `~/.qwen/memory/` and `~/.qwen/projects/*/memory/`.
- `bin/` is on `PATH` inside the session, as in Claude Code; skills reach the client through `command -v memory-3layer`.
- Skills are named `/memory-3layer:recall`, `/memory-3layer:protocol`, and so on.
- Hook commands use `${QWEN_PLUGIN_ROOT}` instead of `${CLAUDE_PLUGIN_ROOT}`.
- There is no importer for Qwen Code's own memory yet.

## Checked on the first real run

1. **Context.** A new session gets the MEMORY-3LAYER block from the SessionStart hook, with the `Client:` path inside the installed plugin.
2. **PATH.** `command -v memory-3layer` in a session resolves to the plugin's `bin/`.
3. **Guard.** A `Write` of a GitHub-token-shaped value into `SESSION.md` is blocked; the message names the kind, not the value, and the file isn't created.
4. **Skills.** `qwen skills list` shows the five plugin skills enabled.
5. **Sync in hooks.** With storages set, `last-sync` moves during a session: the hooks reach the network and `~/.local/state`.

Not yet exercised: the PreCompact reminder (`systemMessage`), task arrivals from another machine (`additionalContext` on PostToolUse), and the SessionEnd flush. The contracts are the Claude Code ones, which Qwen Code documents and parses; report anything that doesn't reach the agent.
