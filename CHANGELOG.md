# Changelog

## v7.1.2 — 2026-11-02 — Shorter SESSION.md, fewer needless questions

- Rotation keeps one line per archive file in `SESSION.md` instead of a stub per arc, and folds existing stubs at the next `/memory rotate`.
- The stale `SESSION.md` warning no longer makes the agent ask "continue or reset" before answering a question unrelated to it.

## v7.1.1 — 2026-11-02 — macOS support

- macOS: dates, timeouts and `/memstat` work without GNU tools. Sync and `migrate` need bash 4 (`brew install bash`), find it by themselves, and say so when it is missing. Based on a report and fixes by @gorlitsyn.
- Fixed: when the home directory went through a symlink, the guard missed a secret in an `apply_patch` to a data directory file with no standard memory name, and a project with no remote got a different key.

## v7.1.0 — 2026-10-31 — Codex package

- Codex CLI plugin, built from its documentation. Not yet run on a real Codex: see `docs/codex.md`.
- The guard reads `apply_patch` patches.
- Documentation rewritten for the current layout. Upgrade steps are in `docs/migration.md`.
- Fixed: the guard missed a secret appended with `>>` to a data directory file with no standard memory name.
- Fixed: a write to memory made while a sync was running could be overwritten.

## v7.0.0 — 2026-10-31 — Harness-independent memory, sync, plugin

- Data moves out of the harness to `~/.local/share/memory-3layer`, keyed by the git remote, not by the directory. `memory-3layer migrate` and `import` bring older data and native notes.
- Sync through git storages the user chooses, routed by layer and project, with per-storage access and `sync check`.
- Installs as a Claude Code plugin, built and published from a release tag.
- Removed: `migrate.sh`, `/migrate-legacy-memory`.

## v6.4.0 — 2026-10-31 — Local secret store

Memory may end up synced, so it must never hold secret values. It now holds `secret://<name>` references, and the values stay on the machine.

**Added**
- **`bin/memory-secrets.sh`.** One mode-600 file per secret in `${MEMORY_SECRETS_DIR:-${XDG_DATA_HOME:-~/.local/share}/agent-secrets}`, outside `~/.claude`. Commands: `put`, `list`, `has`, `rm`, `run`, `get`, `scan`, `adopt`, `guard`. Values come in through stdin only and are never printed to a pipe. They are protected by file permissions and are not encrypted at rest.
- **`scan`** reports `file:line` and kind without the value. **`adopt`** moves a found value into the store and leaves a reference.
- **`guard` PreToolUse hook** blocks Write, Edit, MultiEdit and redirecting Bash commands that would put a secret into a memory file. Detection is pattern-based, so a short or plain-word password can get through; the protocol rule still applies. Merge it from `settings.snippet.json`: `install.sh` warns if it is missing and never edits an existing `settings.json`.
- **Protocol rule 9:** secrets never enter memory, in any layer.
- **`tests/memory-secrets-test.sh`.**

## v6.3.0 — 2026-06-30 — L2 size guardrail + rotation (state-driven distillation)

The L2 distillation guarantee in the protocol was **event-driven**: it fired on a "task done" signal that, in real journaling use, never arrives — so `SESSION.md` grew without bound (observed: 280 KB / 1081 lines over a month), and since it's re-injected every session start and after every compact, that's a recurring ~70–90k-token tax. The only existing guardrail was time-based (`last_updated` staleness >24h), which a continuously-updated journal sidesteps by construction. This adds the missing **size axis** and makes distillation **state-driven** (triggered by a threshold checked mechanically every session) instead of event-driven.

**Added**
- **L2 size guardrail in `hooks/session-start.sh`.** Reads soft/hard byte limits from the new `~/.claude/.memory-config` and injects an escalating recommendation when `SESSION.md` crosses them: soft → "rotate at the next pause", hard → "rotate before continuing". The trigger is deterministic (in the hook); the action stays model-driven. Both tiers are nudges, not gates — neither evicts active state.
- **`~/.claude/.memory-config`** (template `.memory-config.template`). Shell-sourced runtime config: `L2_SOFT_BYTES` (default 40000), `L2_HARD_BYTES` (default 80000), `L2_KEEP_ARCS` (default 2), `L2_ARCHIVE_BY_MONTH` (default 1). `0` disables a limit. Installed by `install.sh` and **preserved on upgrade** like `IDENTITY.md` (user data).
- **`/memory rotate [--dry-run]`.** Lossless relocation of CLOSED dated arcs out of `SESSION.md` into a recallable archive (`SESSION.archive.YYYY-MM.md`, alongside `SESSION.md` so qmd indexes it), leaving a one-line stub + pointer. Structural sections (Goal/State/Open questions/Blockers) and active arcs are never moved; the most recent `L2_KEEP_ARCS` closed arcs stay inline. Model-driven (no brittle shell regex over the user's arc/status convention); refuses to truncate live state when nothing is eligible.

**Fixed**
- **Project-slug derivation was wrong on native Unix paths**, so the staleness check (and now the size guardrail) never found `SESSION.md` on Linux/macOS/WSL2. `hooks/session-start.sh` stripped the leading dash and left `.` unreplaced, computing `home-u-src-github.com-x` where Claude Code's real dir is `-home-u-src-github-com-x`. Now keeps the leading dash and replaces both `/` and `.` with `-` (matching the observed `~/.claude/projects/` naming); the Git-Bash drive-letter branch also replaces `.` now.

## v6.2.4 — 2026-05-28 — Cross-platform portability (installer ships what's actually in the tree)

**Fixed**
- **`install.sh` was silently dropping files.** The script enumerated `hooks/`, `commands/` and `bin/` members by hardcoded name (`backup_and_install "$SRC/hooks/session-start.sh" ...` × N). Anything added to the tree later was never copied on a fresh install or upgrade — at v6.2.3 three files were affected. Replaced the per-file lists with directory-walk loops over `"$SRC/hooks/"*.sh`, `"$SRC/commands/"*.md`, `"$SRC/bin/"*.sh`, so `install.sh` now ships whatever is actually in the source tree, no list to forget to update.
- **`bin/memstat.sh` PROCESSES and HEALTH were Windows-only.** `get_procs()` and `get_cpu_time()` shelled out to `powershell.exe` unconditionally; on Linux/macOS the section always reported "idle" even while qmd was running, and HEALTH could never sample a CPU-time delta to detect stall. Added `uname -s` platform detection with a `ps`-based fallback for non-Windows. Affects `bin/memstat.sh`.
- **Hardcoded maintainer paths.** `hooks/session-start.sh` had two `/c/Users/greev/.claude/...` literals, and `commands/{codemap,memory,memstat,recall}.md` had `bash /c/Users/greev/.claude/bin/...` examples — copy-paste landmines for anyone who isn't the maintainer. Hook switched to the portable `$CLAUDE_HOME` (already defined as `${CLAUDE_HOME:-$HOME/.claude}`); docs switched to `bash ~/.claude/bin/...`.
- **CRLF on shell scripts under Windows Git defaults.** Added `.gitattributes` enforcing LF for `*.sh`, `hooks/*`, `bin/*`, `install.sh`, `migrate.sh`. Without it, any Windows Git client with `core.autocrlf=true` (the default on Git for Windows) silently converts shell scripts to CRLF on checkout, which breaks the `#!/usr/bin/env bash` shebang on WSL/Linux (`/usr/bin/env: 'bash\r': No such file or directory`). Existing checkouts with CRLF need a re-checkout (`git rm --cached -r . && git reset --hard HEAD`) for the rule to take effect.

**Added**
- **`README.ru.md`** — Russian-language overview of the 3-layer protocol: why it exists, layer-by-layer walkthrough (L0/L1a/L1b/L1-fallback/L2), install + upgrade flow, retrieval tools (`/recall`, `/codemap`, `/memstat`, `/memory`), Obsidian-vault use, and what does NOT go into memory.
- **INSTALL.md: nvm gotcha callout.** Claude Code's `Bash` tool runs a **non-interactive** shell that does not source `~/.bashrc`, so nvm's PATH injection is invisible — `node --version` works in your terminal but `qmd` (shebanged `#!/usr/bin/env node`) fails with `node: not found` inside Claude Code sessions. Documented in the qmd install section and in Troubleshooting, with the recommended fix: drop stable symlinks for `node`/`npm`/`npx` into `~/.local/bin` (on PATH unconditionally on Ubuntu 17.10+, Fedora, Arch), or install Node system-wide via NodeSource.

## v6.2.3 — 2026-05-21 — memstat process detection actually works

**Fixed**
- **`/memstat` couldn't see running processes** (always showed "idle" even while `node`/qmd was pegging CPU). Root cause: the PowerShell command was passed inside a bash single-quoted string containing `''node.exe''` — the embedded `''` silently terminates bash quoting, so PowerShell received a mangled command and returned nothing. Rewrote the process query using bash double-quotes with `\"`/`\$` escaping.
- **`running -1s`** — `Get-CimInstance` returns `CreationDate` already as a `[DateTime]`; the code called `ToDateTime()` (a WMI/`Get-WmiObject` idiom) which threw, yielding age -1. Now uses `CreationDate` directly.
- **False "possible stall" warning during model load.** The stall heuristic (>2min running, 0 vector delta) fired during the normal ~30-60s model-load / batch-compute phase when vectors haven't committed yet. Added a CPU-time delta as a second signal: if vectors aren't moving but the process is burning CPU → "working (vectors commit per-batch), not hung"; only flags a real stall when vectors are static AND CPU is idle.

## v6.2.2 — 2026-05-21 — Portable PATH fix (Git Bash) + memstat hardening

**Fixed**
- **PATH normalization on Git Bash.** The portable `_add_path` helper now converts Windows-style paths (`C:\Users\...\npm` with backslashes from `$APPDATA`/`$USERPROFILE`) to unix form before prepending to PATH. Previously these poisoned PATH and `qmd` resolved to a mangled, non-executable path — meaning the SessionStart hook's background `qmd update` and `/memstat`'s status query silently did nothing on a fresh install. Switched from empty `$USER` to `$USERPROFILE`. Affects `hooks/session-start.sh` and `bin/memstat.sh`.
- **`/memstat` honesty when qmd status is unavailable.** Retries once (transient SQLite lock during concurrent `qmd update`), and if still no data, HEALTH reports "index status unknown" instead of falsely claiming "fully embedded".

## v6.2.1 — 2026-05-21 — Hook does FTS-only refresh (no surprise CPU)

**Changed**
- SessionStart hook now runs **only** the lightweight `qmd update` (BM25/FTS rebuild, seconds) in its 6h-debounced background refresh. The heavy `qmd embed` (CPU-bound GGUF vector generation, minutes-long) is **no longer auto-run** — it's manual via `/memory refresh`.
- Rationale: on machines without working GPU acceleration, the background embed pegged CPU for ~30min and surprised users. BM25 (the `/recall` default) doesn't need vectors, so FTS-only auto-refresh keeps search fresh without the CPU cost. Run `/memory refresh` (or `/recall --hybrid` workflows) when you actually want fresh vectors.
- Removed `QMD_LLAMA_GPU` export from the hook (no longer loads models in background).

## v6.2.0 — 2026-05-21 — Memory dispatcher

**Added**
- `bin/memstat.sh` + `/memstat` slash command — a "task manager" for the memory subsystem. Shows:
  - **Processes** — running qmd/ctags processes with PID, RAM, runtime (yellow flag if >30min)
  - **Index** — vectors embedded vs pending, % coverage, per-collection file counts
  - **Refresh** — when the SessionStart hook last refreshed, whether next auto-refresh is due (6h debounce)
  - **Activity** — last line + age of each qmd log
  - **Health** — if an embed is running, samples vector delta over 3s to confirm forward progress; flags possible stall (>2min running, 0 delta) with the PID to kill
  - `--watch [seconds]` for a live auto-refreshing view
- Answers the recurring "why is node.exe eating my CPU and is it stuck?" question. The CPU spikes are the background `qmd embed` launched by the SessionStart hook (6h debounce); on machines without working GPU acceleration it runs CPU-only (~1-3s/chunk, ~30min full re-embed).

## v6.1.0 — 2026-05-19 — Migration tools

**Added**
- `migrate.sh` — mechanical migration of HTML-comment `<!-- last_updated: ISO -->` markers to YAML frontmatter (with `tags:` derived from filename). Auto-detects pre-2026-04-30 legacy directories (`MEMORY.md`, `feedback_*.md`, `project_*.md`, `reference_*.md`) and prints guidance for the AI-synthesis step. `--dry-run` flag for safe preview. Writes `.bak-<timestamp>` for every touched file.
- `commands/migrate-legacy-memory.md` — Claude Code slash command. Spawns an Agent that reads each legacy project directory, synthesizes a single new-format `project.md` per project preserving verbatim technical specificity (reviewer quotes, exact paths, error messages, port/version numbers), and moves originals into `<slug>/memory/legacy/`. Skips projects that already have new-format `project.md`. Non-destructive: only `mv`, never `rm`.
- INSTALL.md: new "Migrating older data" section explaining the two-step path (mechanical → AI synthesis) and when to use each.

## v6.0.1 — 2026-05-19 — Upgrade-safe installer

**Added**
- `install.sh` — idempotent installer. Detects first-install vs upgrade, backs up changed files with `.bak-<timestamp>`, **never overwrites** your `IDENTITY.md` (L0 user data) or `projects/` tree (L1-fallback + L2 sessions). `--dry-run` flag previews changes without writing.
- INSTALL.md: new "Install (or upgrade)" section explaining behaviour per file/dir, rollback recipe, format-compat notes for older installs (HTML-comment `last_updated` markers still work).

**Fixed**
- Manual install path in INSTALL.md guards `cp memory/IDENTITY.md` with a `[ ! -f ... ]` check to prevent silent L0 data loss on upgrade.

**Changed**
- `/recall` default mode flipped to BM25 (`qmd search`), with `--hybrid` flag opt-in for full BM25+vector+rerank. Hybrid requires the full GGUF model bundle loaded and a complete embed index — BM25 covers ~80% of recall queries with zero loading cost.

## v6.0.0 — 2026-05-19 — Initial public release

First public release. Hand-curated, in-repo memory protocol with hybrid retrieval and on-demand symbol map. 100% local. MIT.

## v6 — 2026-05-19 — Retrieval tools (pre-release development log)

**Added**
- `/recall <query>` slash command — hybrid search (BM25 + GGUF embeddings + LLM rerank) over all memory files, backed by [qmd](https://github.com/tobi/qmd)
- `/codemap def|callers|callees|outline <symbol>` — on-demand symbol map for the current repo via universal-ctags + ripgrep; cache in `<repo>/.codemap.tags`
- `/memory status | auto on|off | refresh` — protocol controls and optional auto-capture toggle (off by default)
- `bin/codemap.sh` — portable ctags+rg wrapper, self-locates binaries on Windows (winget paths) / macOS (brew) / Linux (apt)
- SessionStart hook now auto-refreshes the qmd retrieval index in background, debounced 6h

**Changed**
- Knowledge store organization: flat-only rule softened to allow shallow (1-level) folder grouping when a category has 5+ peer files — `protocols/`, `formats/`, `handoffs/` OK; deeper nesting still forbidden. Obsidian tags continue to do the primary categorization.
- Karpathy "LLM-OS" framing added to CLAUDE.md (context = RAM, file system = disk, tools = peripherals)

## v5 — 2026-05-13 — Knowledge store conventions

**Added**
- "Knowledge store organization" section in CLAUDE.md codifying flat + tags + filename-prefix conventions (`protocol_<name>.md`, `format_<name>.md`, `handoff_<topic>.md`)
- `index.md` as the routing source for multi-file knowledge stores
- `raw/` subdirectory convention for non-markdown data dumps
- Rule for when to split single `project.md` into multi-file (>200 lines, ≥3 distinct categories, or cross-file refs needed)

## v4 — 2026-05-07 — In-repo L1 pivot

**Changed**
- L1 split into **L1a** (`<repo>/CLAUDE.md`, thin entry, git-tracked, auto-loaded) + **L1b** (`<repo>/.claude-docs/*.md`, thick lazy-loaded, git-tracked)
- Old account-local `project.md` renamed to **L1-fallback** for repos where in-repo isn't appropriate
- Adopted "midnight server agent test" as the explicit decision rule for layer placement
- Added templates: `templates/repo/CLAUDE.md`, `templates/repo/.claude-docs/{index,gotchas,architecture,conventions}.md`

## v3 — 2026-05-07 — Obsidian compatibility

**Changed**
- HTML-comment `<!-- last_updated: ... -->` migrated to YAML frontmatter with `tags: [memory/l0|l1|l2|repo, ...]`
- StalenessHook regex stays compatible with both formats — no migration needed for existing files

## v2 — 2026-05-05 — Workflow patterns + L1 templates

**Added**
- Workflow patterns: pre-compact checkpoint, post-compact recovery, multi-session handoff, distillation on task wrap-up, bootstrapping in-repo L1
- L1-fallback template with structured sections (Repository, Layout, Stack, Endpoints, Conventions, Known gotchas, Roadmap)
- Rule: "L1 is where grabli live" — non-obvious footguns are the highest-leverage memory

## v1 — 2026-05-05 — Staleness detection + portability

**Added**
- `bin/session-start.sh` staleness check: if `SESSION.md` is >24h old, the hook injects a STALENESS WARNING so the model surfaces it to the user before silently continuing
- Portable hooks (use `$HOME`/`$CLAUDE_HOME` instead of hardcoded paths)
- `templates/` directory with separate `IDENTITY.md`, `project.md` templates for new installs
- Friend-shareable zip packaging
