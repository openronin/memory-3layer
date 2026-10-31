# Codex CLI

Status: built from the Codex documentation. Not yet run on a real Codex. The list below is what to check.

## Install

From a published package:

    codex plugin marketplace add openronin/memory-3layer-codex
    codex plugin add memory-3layer@memory-3layer

Or from this repository, before a release:

    tools/package.sh codex /tmp/memory-3layer-codex
    codex plugin marketplace add /tmp/memory-3layer-codex
    codex plugin add memory-3layer@memory-3layer

Then:

1. Open `/hooks` in a session and trust the hooks. Codex skips them until you do, and again after each update. Hooks also need `features.hooks` if your version has them off.
2. Allow writes to the memory directory in `~/.codex/config.toml`, with the absolute path. A plugin can't set this, and without it the agent can read memory but not update it. Don't add the `memory-3layer-secrets` directory.

       sandbox_mode = "workspace-write"

       [sandbox_workspace_write]
       writable_roots = ["/home/you/.local/share/memory-3layer"]

## What differs from Claude Code

- Writes aren't approved by the hook. Codex documents `allow` only with `updatedInput`, so the guard stays silent unless it blocks, and access comes from `writable_roots`.
- Files are edited through `apply_patch`. The guard reads the patch: its file paths and added lines.
- `bin/` isn't on `PATH`. The session context names the client, and skills use that path.
- Skills are called as `$recall`, `$memory`, and so on.
- There is no importer for Codex's own memory yet.

## Checklist for the first real run

Report the Codex version with the results.

1. **Install.** The plugin installs, `/hooks` lists SessionStart, PreToolUse, PreCompact, SessionEnd.
2. **Context.** In a new session in a git repository, ask what the session context says about memory. The agent names `IDENTITY.md`, `SESSION.md` and a `Client:` path, and the path exists.
3. **Writing.** Ask the agent to add a line to that `SESSION.md`. It works with `writable_roots`, and without them fails or asks. Confirm the TOML above is the right syntax: the docs don't give an example.
4. **Secret in a patch.** Ask it to add a line with a value shaped like a GitHub token (`ghp_` and 36 letters and digits, made up) to `SESSION.md`. The write is blocked, and the message doesn't repeat the value.
5. **Secret in the shell.** The same with `echo ... >> SESSION.md`.
6. **Ordinary files.** Editing a file in the project isn't blocked or slowed.
7. **Tool name.** Whether PreToolUse receives `apply_patch`, and the patch in `tool_input.command`. Check 4 depends on this.
8. **Skills.** `$protocol` and `$recall` are found, and `$memstat` runs its script.
9. **Sync in hooks.** With a storage set, run `memory-3layer sync status` by the `Client:` path after a session ends. The time moved, which means hooks aren't stopped by the sandbox from using the network and `~/.local/state`. The docs don't say whether hooks are sandboxed.
10. **Pre-compact.** Before compaction, whether the reminder reaches the agent. It is sent as `systemMessage`, which the Codex docs describe as a warning in the interface. If the agent doesn't see it, the hook needs another output.
11. **Line endings.** With `core.autocrlf=true`, the client still starts after install.
