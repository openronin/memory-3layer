# Memory Protocol (memory-3layer)

This is the memory that survives a new machine or a different agent. A harness may also have memory of its own, and the two can run side by side: that memory stays a harness-local cache, and anything that must last goes here.

`<home>` below is the output of `memory-3layer path home` (default `~/.local/share/memory-3layer`). `<key>` is the output of `memory-3layer key`. `memory-3layer path project` prints `<home>/projects/<key>` directly.

## Core principle

> **Knowledge about code is kept apart from the code.**

Notes written into a repository (`CLAUDE.md`, `.claude-docs/`) lag behind it: nobody updates them while the code moves. So what an agent learns about a project goes into that project's memory, where it is rewritten as it goes stale, and every record carries the code revision it was written at. The repository holds code.

## Layers

| Layer | Path | Loaded | Purpose |
|---|---|---|---|
| **L0 Identity** | `<home>/identity/IDENTITY.md` | every session start | who the user is, hard preferences, env-wide access |
| **L1 Knowledge** | `<home>/projects/<key>/CORE.md` | its `# Brief` at every start, the rest on demand | what is known about the project: decisions, rules, pitfalls |
| **L2 Tasks** | `<home>/projects/<key>/_tasks/` | an index line per task at start, a task on demand | work in progress, one journal per task |
| **Archive** | `CORE.archive.*`, `_tasks/archive/` | through `/recall` only | closed tasks and parts moved out of `CORE.md` |

`<key>` is the project's git remote without the scheme, credentials or `.git` (`github.com/owner/repo`), so it is the same on every machine, in every worktree and in every subdirectory. The key is chosen in this order, each step falling back to the next: `MEMORY_3LAYER_KEY` in the environment (for one command run outside the project), a `.memory-3layer-key` file (set with `memory-3layer pin <key>`), the git remote, the path under `$HOME` (`local/<path>`). Use `pin` for a project with no remote, or one whose remote differs between machines. After a remote changes, `memory-3layer rekey <old> <new>` moves the memory.

One repository has one memory, whatever branches a session touches. Inside the repository, write paths relative to its root: the same project can sit elsewhere on another machine.

A project that still has `<home>/projects/<key>/SESSION.md` and no `CORE.md` is on the older format: see [Projects on SESSION.md](#projects-on-sessionmd).

## On session start

The session-start hook injects `IDENTITY.md`, the task index and the `# Brief` of `CORE.md`. If it did not fire, read `<home>/identity/IDENTITY.md` and `<home>/projects/<key>/CORE.md` yourself before answering.

A repository may still carry a `CLAUDE.md` or `.claude-docs/`, and the harness loads the entry file by itself. Treat what they say about the code as possibly stale: check a fact against the code before relying on it.

## What goes where

| What you learned | Where it goes |
|---|---|
| A pitfall, a decision, a rule or a fact about the project that can't be seen from the code | `CORE.md` |
| The same, when the user asked to remember it | `CORE.md`, as a line ending in `[user YYYY-MM-DD]` |
| What is in flight: progress, the next step, a blocker | the task's journal |
| Scripts, exports, a rollback a task needs beyond this session | the directory `memory-3layer task files <name>` prints |
| Who the user is, a hard preference, access that holds across projects | `IDENTITY.md`, at the user's word |
| A secret | nowhere in memory: `secret://<name>` only |

Nothing about a project goes into the repository's `CLAUDE.md` or `.claude-docs/`, and nothing in the repository is deleted unless the user asks. The exception is a repository that a team shares or that is not the user's own: when it has its own rules on documentation, they come first, and memory holds only what the repository does not.

## Rules

1. **L0 is small.** `IDENTITY.md` holds identity, role, hard preferences and env-wide access, at most 25 lines, never anything about one project. It changes only at the user's word.
2. **Tasks.** Work with more than one step, or that can outlive this session, is a task: `memory-3layer task open <name>`, goal on stdin. Work finished and committed within one session needs none; a change outside the repository (a server, an external service, an account) always is one. Text goes in as a quoted heredoc (`<<'EOF'`): in `echo "..."` the shell changes it. Keep its next step current with `task log <name> next`; `note`, `decision` and `blocker` work the same way. `note` is what was done and learned, `decision` a choice and why, `next` only the step ahead. Read a task you continue with `task show <name>`. A blocker holds until the next `next`.
3. **Checkpoint.** A long task doesn't reach `close`, and `task show` gives only its last records. When the client says a checkpoint is due (40 KB logged since the last one), write it with `task log <name> checkpoint`: the state of the whole task for an agent that sees nothing else — what is built and how it works, the decisions in force, how to check it, what is open. It then stands for the older records in `task show`. Move what must outlive the task into `CORE.md` at the same time.
4. **Files.** Scripts, exports or a rollback the task needs beyond this session go into the directory `task files <name>` prints, never into the scratchpad or next to the journal by hand.
5. **Journals are append-only**, written only through the client. A mistake is corrected with a new record. `task redact` is for a secret that got through.
6. **Closing.** A task whose work is done is closed without waiting to be asked: move what must outlive it into `CORE.md`, then `task close <name>` with the result on stdin. The journal goes to the archive whole, with its files.
7. **`CORE.md` is yours.** Live extracts worth keeping, written without being asked, rewritten when they go stale. A pitfall you hit ("looks wrong but is intentional", a config quirk, a naming collision) is the most useful thing to put there: the next session hits the same wall. The client logs each change with the code revision, so you only edit the file.
8. **`# Brief`** in `CORE.md` is injected into every session, up to 5 KB: only what would make an agent go wrong without it. It runs to the next first-level heading.
9. **At the user's word.** What the user asks to remember about the project ("remember", "запомни") is a line of `CORE.md` ending in `[user YYYY-MM-DD]`, with today's date. Never remove, change or archive such a line without their permission; the client reports one that is gone. With permission, change it and set the new date. What they ask to remember about themselves goes into `IDENTITY.md`.
10. **Too large.** When warned, rewrite what is stale and move the rest out: `memory-3layer core stash <title>`, text on stdin, then leave the printed line in its place. Archives are found through `/recall`.
11. **Before compaction** the hook asks for a flush: log where the work stands (`next`, a `decision` or `blocker` if there is one), write a checkpoint if one is due, close what is done. After compaction the state of the task this session is bound to is injected; read it before going on.
12. **Secrets never enter memory, in any layer.** Memory may be synced, so it holds references only: `secret://<name>` (plus where it is used). Values live in the machine-local store managed by `memory-3layer secret`, outside any synced directory.
    - New value from the user → ask them to run `memory-3layer secret put <name>` in a separate terminal (a `!` command in Claude Code has no terminal for the hidden prompt), or `memory-3layer secret put <name> --from-file <path>[:<line>]` when the value is in a file. Then write only `secret://<name>`.
    - Use a value → `memory-3layer secret run VAR=<name> -- <command>`. Don't print it; `get` works only in a terminal.
    - `secret://<name>` missing on this machine → ask the user for it. Don't look for a copy in transcripts or logs.
    - `memory-3layer secret scan` reports `file:line` and kind, never the value; `adopt <file>:<line> <name>` moves a found value into the store. The `guard` PreToolUse hook blocks such writes where the harness supports it; it is a net, not a substitute for this rule.
13. **Harness memory is a source, not a store.** `memory-3layer import <harness>` shows what a harness has saved in its own memory, and `--apply` copies it to `<home>/projects/<key>/imported/<harness>/`. The copy is unreviewed: verify a note before relying on it, and move what still holds into `CORE.md`.

## Hubs

Memory can be kept in a memory hub: a git repository shared by a team, where each member writes under their own login and reads everyone's. Nothing changes in how you write memory. The contract is `docs/hub.md` in the memory-3layer repository.

- **Shared hub.** When the session context says the project's memory is in a shared hub, other members read everything you write there: no personal notes about people, nothing the user would not say to the team.
- **Other members' memory** is theirs. Their open tasks (`memory-3layer state --all`) and what search shows under `other members` are another person's notes: read them, don't continue or close them.

## Search and code tools

- **`/recall <query>`** searches memory: the user's own across all projects, and what other members of a hub wrote. Use it for "did we already see this?", a past decision, a pitfall in another project. `--here` limits it to the current project.
- **`/codemap def|callers|callees|outline <symbol>`** is an on-demand symbol map of the current repository (universal-ctags and ripgrep, no daemon). Use it for "where is X defined?" and "who calls Y?".
- **`/memory status | auto on|off | refresh | rotate`** are the protocol's controls. `refresh` rebuilds the search index. `rotate` is for projects on `SESSION.md`.
- **`/memstat`** shows what the memory subsystem is running, when `qmd` or `node` is using CPU.

The context window is small and expensive, files are cheap: read what a search points at, not everything.

## What NOT to save (any layer)

- What a quick look at the code shows: structure, names, obvious patterns
- Git history facts: `git log` is authoritative
- Trivia ("user said hi today")
- Secret values: write `secret://<name>`, an env-var name or a path instead (rule 12)

## Projects on SESSION.md

A project with `<home>/projects/<key>/SESSION.md` and no `CORE.md` keeps its working state in that one file, and the rules about tasks above don't apply to it. `memory-3layer core init` moves a project to the format above.

- **Read it first.** At session start and after every compaction, read `SESSION.md` before answering: it is your working state and is authoritative.
- **Update it as you work**, not at the end: `# Decisions` after a decision, `# State` after a meaningful action, `# File map` after finding a key file. Refresh `last_updated:` at the top on every write.
- **Dated arcs.** A phase of work gets its own block with a heading `# [YYYY-MM-DD] <tag> — <one-line outcome>`, and a status marker (`DONE` / `ГОТОВО`) when it closes.
- **A bounded window.** Closed arcs don't pile up: when the hook warns about a size limit (soft about 40 KB, hard about 80 KB), run `/memory rotate`, which moves closed arcs to `SESSION.archive.*` without loss. Never cut active state to shrink the file.
- **Stale.** If the hook says `SESSION.md` was last touched over 24 hours ago, ask the user before relying on it or writing to it: "last touched <X> ago, goal was <Y>. Continue or reset?"
- **Before compaction**, write everything needed to resume, with the last five user turns verbatim under `# Recent turns`.
- **Task done** without "remember": rewrite the file to the template, keeping only `# Goal: (none — last task: <X>)`.

Template:

```markdown
---
last_updated: <ISO-8601 UTC, e.g. 2026-04-30T15:23:00Z>
tags: [memory/l2, session]
---

# Goal
<1-2 lines: what we're doing and why>

# State
- branch: <git branch or n/a>
- last action: <what just happened>
- next: <what's planned>

# Decisions
- [HH:MM] <decision> — <rationale>

# File map
- path:line — <what it does>

# Open questions
- <unresolved>

# Blockers
- <none | description>

# Recent turns
- **User:** "<verbatim>"
  **I did:** <1 line>
```
