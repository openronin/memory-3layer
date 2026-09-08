# Changelog

## v6.2.5 — BSD/macOS portability (the Unix paths v6.2.4 added, actually working on macOS)

v6.2.4 introduced non-Windows code paths but they were only exercised on Linux. Every one of them assumed GNU userland, so on stock macOS the staleness check was dead and `/memstat` was half-blank. All five fixes are additive — GNU/Windows behaviour is unchanged.

**Fixed**
- **Staleness detection never fired on macOS/Linux — the slug dropped its leading dash.** `hooks/session-start.sh` computed the Unix slug as `slug="${cwd_unix//\//-}"` then stripped the leading `-` with `slug="${slug#-}"`. But Claude Code names the directory by replacing *every* `/` including the root one, so `/Users/me/dev/foo` is `-Users-me-dev-foo`, not `Users-me-dev-foo`. The hook stat'd a path that never exists, found no `SESSION.md`, and silently emitted no warning — on **every** macOS and Linux session since the feature shipped. (Windows/Git-Bash was unaffected: that branch builds the slug separately.)
- **`date -d` is GNU-only, so the staleness timestamp parsed as 0.** Even with the slug fixed, `date -d "$last_updated"` fails on BSD `date` (`illegal option -- d`), yielding `last_epoch=0`, which the guard `[[ "$last_epoch" -gt 0 ]]` then skipped. Added a `to_epoch()` helper that tries `gdate -d` → `date -d` → BSD `date -j -u -f` (`-u` matters: the marker is UTC, and parsing it as local time skews the age by the offset). `coreutils` is no longer a requirement.
- **`/memstat` PROCESSES crashed on macOS: `syntax error: operand expected`.** `bin/memstat.sh` asked for `ps -eo pid,etimes,rss,command`, but `etimes` is a procps extension BSD `ps` doesn't have — and macOS `ps` drops an unknown keyword *silently* instead of erroring, shifting every column left so a command path (`/bin/zsh`) landed in `$rss` and `$(( rss / 1024 ))` aborted. Now probes for `etimes` support, falls back to `etime` with an `[[DD-]HH:]MM:SS` → seconds parser, and validates `pid`/`rss` are numeric before any arithmetic.
- **`/memstat` INDEX and HEALTH always read "unavailable" on macOS.** `get_qmd_status()` wrapped the call in GNU `timeout`, which macOS doesn't ship; the command simply wasn't found, so `qmd status` output was always empty and HEALTH reported "index status unknown" even on a healthy index. Added a `run_timeout()` shim: `timeout` → `gtimeout` → run bare.
- **`/memstat` ACTIVITY showed nonsense log ages.** `stat -c %Y` is GNU syntax; on BSD it errors and the `|| echo 0` fallback made every log look like it was last touched at the epoch. Added a `file_mtime()` shim (`stat -c %Y` → `stat -f %m`).

**Docs**
- `CLAUDE.md`, `INSTALL.md`, `README.ru.md`: the slug rule was documented Windows-only, which is what the buggy Unix branch was written against. Both platforms are now spelled out, with `ls ~/.claude/projects/` named as the authority.
- `INSTALL.md`: dropped the `brew install coreutils` requirement and rewrote the two stale troubleshooting entries.

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
