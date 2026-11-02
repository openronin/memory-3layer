# memory-3layer

Memory for coding agents that lives in plain markdown files, outside any agent. Move to a new machine or another agent, connect your storage, and the work continues where it stopped.

[Русская версия](README.ru.md)

## Why

An agent loses its context on every compaction, new session and new machine. A harness's built-in memory stays with that harness on that machine. This tool keeps the memory in files you can read, diff and sync with git.

The agent writes the memory, not the hooks: actions aren't recorded mechanically. It keeps working memory (`SESSION.md`, one file per repository, shared by all its sessions) without being asked, so work continues after a compaction and in a new session. A fact reaches permanent memory (`IDENTITY.md`, `project.md`, the repo's docs) only when you say so.

## How it works

Each fact goes in the layer that matches how long it lives and who needs it:

| Layer | File | Loaded | Holds |
|---|---|---|---|
| L0 | `<data>/identity/IDENTITY.md` | every session | who you are, hard preferences; 25 lines at most |
| L1a | `<repo>/CLAUDE.md` | every session in the repo | commands, rules, an index of the docs |
| L1b | `<repo>/.claude-docs/*.md` | on demand | architecture, conventions, `gotchas.md` |
| L1 fallback | `<data>/projects/<key>/project.md` | every session | notes for a project with no suitable repo |
| L2 | `<data>/projects/<key>/SESSION.md` | every session, after every compaction | goal, state, decisions, recent turns |
| L2 archive | `<data>/projects/<key>/SESSION.archive*.md` | only through search | closed work moved out of L2 |

`<data>` is `~/.local/share/memory-3layer`. L1a and L1b are committed with the code, so teammates and server agents see them. The rule for choosing: *would a server agent at midnight, with no memory and no human, need this?* If yes, it goes in the repo.

`<key>` is the project's git remote, such as `github.com/owner/repo`, so a project has the same memory on every machine, worktree and branch. A project with no remote uses its path under `$HOME`, or a key you set with `memory-3layer pin`.

Hooks do the mechanical part:

| Event | What happens |
|---|---|
| Session start | Pull from storages, tell the agent what to read, warn if `SESSION.md` is stale or too large |
| Before a tool runs | Block a secret from being written to memory, allow writes to the memory directory |
| End of a turn, after a tool call | Sync in the background if memory changed, or every 5 minutes |
| Before compaction | Remind the agent to save its state, push in the background |
| Session end | Push in the background |

Secret values never enter memory. Memory holds `secret://<name>`, and the value stays in `~/.local/share/memory-3layer-secrets` on that machine, protected by file permissions, not encrypted.

The full rules the agent follows are in [CLAUDE.md](CLAUDE.md).

## Install

Claude Code:

```
/plugin marketplace add openronin/memory-3layer-claude-code
/plugin install memory-3layer@memory-3layer
```

Restart the session. Nothing leaves the machine until you set a storage.

Other routes and optional tools: [INSTALL.md](INSTALL.md). Codex CLI, not yet run on a real Codex: [docs/codex.md](docs/codex.md). Coming from an older version: [docs/migration.md](docs/migration.md).

## Use

In a session you mostly talk to the agent: "запомни" or "remember" promotes a fact to long-term memory.

| Command | What it does |
|---|---|
| `/recall <query>` | Search memory across projects |
| `/codemap def\|callers\|callees\|outline <symbol>` | Symbol map of the current repo |
| `/memory status\|auto on\|auto off\|refresh\|rotate` | Memory controls; `rotate` moves closed work to the archive |
| `/memstat` | Search processes and index progress |

In Claude Code, plugin skills are named `/memory-3layer:recall` and so on. The client:

```bash
memory-3layer sync init <git address>   # set the default storage
memory-3layer sync status               # state of each storage
memory-3layer secret put <name>         # store a secret, then write secret://<name> in memory
memory-3layer key                       # this project's key
memory-3layer                           # all commands
```

Syncing between machines, with separate storages for work and personal projects: [docs/sync.md](docs/sync.md).

## Development

```
bin/memory-3layer     client: paths, keys, session context, migrate, import, search
bin/memory-sync.sh    sync and routing
bin/memory-secrets.sh secret store, scanner, write guard
bin/codemap.sh        symbol map
bin/memstat.sh        search process monitor
hooks/                hook scripts, the same for every harness
commands/             slash commands; the package turns them into skills
CLAUDE.md             the protocol; the package turns it into the protocol skill
harness/<name>/       manifests, hook wiring and the memory importer of one harness
templates/, memory/   templates for L0, L1a, L1b and the L1 fallback
tools/package.sh      builds a package for one harness
tools/publish.sh      publishes a package to its repository
install.sh            manual install into ~/.claude
```

Tests, in bash, also run in CI:

```bash
for t in tests/*-test.sh; do bash "$t"; done
```

An annotated tag `vX.Y.Z` releases everything. The workflow runs the tests, publishes `memory-3layer-claude-code` and `memory-3layer-codex`, and creates a GitHub release from the tag's body. Package repositories are generated, so changes go here.

## License

[MIT](LICENSE). Search is built on [qmd](https://github.com/tobi/qmd), the symbol map on [universal-ctags](https://github.com/universal-ctags/ctags).
