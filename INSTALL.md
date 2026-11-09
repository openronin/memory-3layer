# Install

## Requirements

- bash 4 or newer, and git. macOS ships bash 3.2, so run `brew install bash` there. The client finds Homebrew's bash by itself. Without it, sync and `migrate` refuse to run and the session context says so.
- python3, for the secret guard and for `migrate` and `import`. Without it the guard lets writes through.

Tests run on Linux and macOS. Daily use is on Linux and WSL2.

## Claude Code plugin

```
/plugin marketplace add openronin/memory-3layer-claude-code
/plugin install memory-3layer@memory-3layer
```

Restart the session. Inside Claude Code `memory-3layer` is on `PATH`. For your own terminal, ask the agent to run `memory-3layer install-cli`: it links `~/.local/bin/memory-3layer` to a shim that runs whichever memory-3layer plugin is enabled, and keeps working after updates. The same shim serves other plugins' commands: `ln -s claude-plugin-shim ~/.local/bin/<command>`.

Update:

```bash
claude plugin marketplace update memory-3layer
claude plugin update memory-3layer@memory-3layer
```

## Codex CLI

See [docs/codex.md](docs/codex.md).

## Manual install

For a machine without the plugin system. It copies files into `~/.claude` (or `$CLAUDE_HOME`) and links the client into `~/.local/bin`.

```bash
./install.sh --dry-run
./install.sh
```

Changed files are saved as `.bak-<timestamp>`. Your identity, project memory and config are never overwritten. An existing `settings.json` is never edited: merge the hooks from `settings.snippet.json` by hand. The installer stops if an older version's data hasn't been moved: see [docs/migration.md](docs/migration.md).

## First steps

1. **Fill in who you are.** Create `IDENTITY.md` at the path from `memory-3layer path identity`, or ask the agent to. Template: `memory/IDENTITY.md`, or `templates/IDENTITY.template.md` in a package.
2. **Set a storage**, if you want memory on other machines. It must be a private git repository:

   ```bash
   memory-3layer sync init <git address>
   memory-3layer sync check
   ```

   Separate storages for work and personal projects: [docs/sync.md](docs/sync.md).
3. **Set up a project.** Ask the agent: "set up in-repo L1 for this project". It creates `CLAUDE.md` and `.claude-docs/` from the templates, and you commit them.

## New machine

Install, run `memory-3layer install-cli`, then `sync init` with the same address and `memory-3layer sync`. Three things stay behind and have to be set up again:

- secrets: `memory-3layer secret put <name>`;
- rules in the local `storage.conf`, such as corporate projects. It holds no secret values, so copy it from the old machine before the first sync. A project whose rule is missing is not laid out, and the session on it says so;
- ssh keys.

## Optional tools

**Search** (`/recall`) needs [qmd](https://github.com/tobi/qmd) and Node 18 or newer:

```bash
npm install -g @tobilu/qmd
memory-3layer refresh                 # creates the collection, builds the text index
QMD_LLAMA_GPU=none qmd embed          # optional, for /recall --hybrid: downloads about 2 GB, runs for minutes
```

The session-start hook refreshes the text index at most every 6 hours. Vectors are only rebuilt by `/memory refresh`.

**Symbol map** (`/codemap`) needs universal-ctags and ripgrep. It builds `<repo>/.codemap.tags` on demand, so add that file to `.gitignore`.

## Settings

`~/.config/memory-3layer/config` is a shell file, optional:

| Variable | Default | Meaning |
|---|---|---|
| `MEMORY_3LAYER_HOME` | `~/.local/share/memory-3layer` | data directory |
| `L2_SOFT_BYTES` | 40000 | suggest rotating `SESSION.md`; 0 turns it off |
| `L2_HARD_BYTES` | 80000 | ask to rotate before continuing; 0 turns it off |
| `L2_KEEP_ARCS` | 2 | closed arcs that `/memory rotate` leaves in place |
| `L2_ARCHIVE_BY_MONTH` | 1 | one archive per month; 0 means a single file |

`memory-3layer path` prints where each thing lives. The data directory also opens as an [Obsidian](https://obsidian.md/) vault: files use YAML frontmatter and tags such as `memory/l2`.

## Troubleshooting

- **`node: not found` from qmd with nvm.** Agent shells don't read `~/.bashrc`. Link the binaries somewhere on `PATH`: `ln -sf "$NVM_BIN/node" ~/.local/bin/node`, and the same for `npm`.
- **Sync does nothing.** `memory-3layer sync status` shows each storage and `memory-3layer sync check` says what to fix. A new project isn't synced if the global rule is `none`: `memory-3layer sync route <key>` shows where it goes.
- **Hooks run twice.** Files from a manual install are still wired up alongside the plugin: see [docs/migration.md](docs/migration.md).
- **Memory is empty after a remote changed.** The key changed with it: `memory-3layer rekey <old> <new>`.
