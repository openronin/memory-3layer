# Task journals and CORE.md

Status: design for an experiment on the `feat/tasks-journal` branch. Nothing here is implemented yet.

## Why

One `SESSION.md` per repository mixes everything: parallel tasks overwrite one `State`, permanent rules sit next to the next step, and the whole file loads at every start. A file edited by hand also can't be rotated or queried mechanically.

The split:

| | Task journal | `CORE.md` |
|---|---|---|
| Holds | one piece of work: progress, next step, blockers | live extracts the agent wants to keep: decisions, rules, findings |
| Written | only through the client, append-only | freely by the agent, rewritten when out of date |
| Rotated | mechanically, when the task closes | by the agent, when the size warning fires |
| Loaded | index line at start; the rest on request | the `# Brief` block at start; the rest on request |

`project.md` stays what changes only at the user's word. `CORE.md` is the agent's own judgment.

## Files

    projects/<key>/
      CORE.md                        replaces SESSION.md
      CORE.archive.YYYY-MM.md        parts moved out of CORE.md, search only
      tasks/<slug>.md                active and blocked tasks
      tasks/archive/YYYY-MM/<slug>.md  closed tasks, complete, search only

`SESSION.archive*` files stay where they are, and search still finds them.

## Journal format

Markdown, so a person can read it and search can index it. The header line is strict, the body is free:

    ## 2026-10-31T20:07:29Z-a3f1 next s:53e2b2ce
    Tag v7.1.0 on origin/main and watch the release run.

The header holds a UTC time with a random suffix (the record's id; two machines can't collide), the type, and the session. The client writes all of it.

Types: `open`, `note`, `decision`, `next`, `blocker`, `close`. Task state is computed from the records:

- status: `done` after `close`; `blocked` if a `blocker` is the latest of `blocker` and `next`; otherwise `active`;
- stale: no record for `TASK_STALE_DAYS`, 7 by default;
- next step: the latest `next`.

## Commands

The body always comes through stdin, so an agent can't trip over quoting.

    memory-3layer task open <slug>              # stdin: the goal
    memory-3layer task log <slug> <type>        # stdin: the record
    memory-3layer task resume <slug>            # bind this session, print the task's state
    memory-3layer task show <slug> [--log]      # state, or the whole journal
    memory-3layer task close <slug>             # stdin: the result, required
    memory-3layer state                         # index: active and recent tasks
    memory-3layer core stash <title>            # stdin: text to archive; prints a link to leave in its place

Each write takes a lock, scans the body for secrets, and refuses the whole record on a finding.

The session id comes from `CLAUDE_CODE_SESSION_ID`, with `--session` for harnesses that don't set one. Bindings live in `$STATE_DIR`, since they belong to one machine.

The guard blocks direct writes to `tasks/`, including shell redirects. A mistake is corrected with a new record. The one exception is a `task redact` command for a secret that got through.

## Closing a task

`task close` needs the result and moves the journal, complete, to `tasks/archive/`. Before closing, the agent moves what must outlive the task into `CORE.md`. There are no separate stubs: the recent list is computed from the archive's `close` records, so nothing else grows.

## What a session gets

Injected, so it can't be skipped:

    Memory: github.com/openronin/memory-3layer
    Active tasks:
      release-v7.1 [blocked] waiting for the admin's approval
      docs-rewrite [active] commit the README
      search-rework [stale, 12d]
    Recently closed: sync-setup, codex-package
    <IDENTITY.md>
    <# Brief from CORE.md>
    Commands: memory-3layer task show <slug>, state. Rules: the protocol skill.

After a compaction, the state of the task bound to this session is added. An unbound session picks a task with `task resume`, or opens one.

`# Brief` runs from that heading to the next first-level heading. It is limited to `CORE_BRIEF_BYTES`, 5000 by default. Past that it is cut, and the agent is told so and asked to shorten it. If there is no brief, the agent is asked to read the file.

Size warnings on `CORE.md` fire at 20 KB and 40 KB, half of those on `SESSION.md`, because working state no longer lives there.

## Sync

`bin/memory-sync.sh` routes by file name, and today anything unknown becomes the `project` layer with the parent directory taken as the key. So this has to change before any of it reaches a storage:

| File | Layer |
|---|---|
| `CORE.md`, `tasks/*.md` | `session` |
| `CORE.archive*`, `tasks/archive/**` | `archive` |

The layer keys in `storage.conf` and `routing.conf` keep their names: they name a layer, not a file.

Conflicts in a journal don't use "newer wins", which would lose records. Both sides' records are joined and sorted by id. `CORE.md` conflicts work like `SESSION.md` today.

## Migration

`migrate` renames `SESSION.md` to `CORE.md` and adds an empty `# Brief`. The agent moves active work into tasks by hand: nothing can tell a task from a note automatically. The client keeps reading `SESSION.md` for a project without `CORE.md`, because machines update at different times.

## The experiment

The stable plugin stays published and unchanged, and no release tag is made from this branch.

- **Plugin.** Version `7.2.0-dev`, built by `tools/package.sh` from the branch into a local directory and installed from a local marketplace. Only one of the two can be enabled, or hooks run twice. Going back means disabling the dev plugin and enabling the stable one.
- **Data.** Only this repository's project uses tasks and `CORE.md`, moved by hand. Other projects keep `SESSION.md`, read as before. `migrate` isn't run on real data until the experiment ends.

## What decides it

After two weeks of real work on this repository:

1. The agent keeps journals on its own, without reminders.
2. The context at session start is smaller than today.
3. Nothing is lost across compactions.
4. Work doesn't drift into `CORE.md` because writing there is easier. If it does, the scheme gets simpler rather than gaining rules.

## Open

- Verbatim recent turns: a hook would do this mechanically, but that bypasses "the agent writes the memory". Left out of the first version; `CORE.md` and journals have to show whether they're missed.
- Search over tasks and archives: a separate review after the first version. Journals and archives are plain markdown, so qmd indexes them as they are.
- Codex: session id and hook behaviour are unverified.
