# Memory hub protocol

Status: draft, `contract: 1`. Implemented in the client so far: `hub init`, `hub upgrade`, `hub add`, and sync into a member's namespace. The rest is not.

This is the contract between the memory-3layer client and a memory hub. The client side is this repository. A hosting service (xchg.app is the first) implements the hub side from this text alone, the way it reads a mail hub from the xchg contract.

The protocol stays small on purpose. It says what a client writes and reads. Limits, quotas, who may create a hub and what a push is checked for belong to the service that hosts it.

## What a hub is

A memory hub is a git repository with the layout below. It replaces what `docs/sync.md` calls a storage.

- **Git is the transport.** Reading is a fetch, writing is a commit and a push. Any git hosting can hold a hub. Everything a service adds (search, write checks) is optional, and the client works without it.
- **A hub is a trust boundary.** Everyone with access reads everything in it. A team hub is used by a team that may see all of its projects. What is personal goes into a separate private hub. A memory hub is never public.
- **One writer per namespace.** A member writes only under their own login. So two people never edit the same file, and a push conflict can only come from the same person's other machine.
- **A hub holds knowledge about code, apart from the code.** The repository entry files (`CLAUDE.md`, `.claude-docs/`) stop being a memory layer. See [Migration](#migration).

A user is usually in several hubs: a private one for `IDENTITY.md` and personal projects, and a team hub per team. Each project lives in one hub.

## The local directory

A hub is optional. Without one, memory is a plain directory on the machine, as it is today: no git, no login, no account.

    <home>/identity/IDENTITY.md
    <home>/projects/<key>/CORE.md
    <home>/projects/<key>/_tasks/...

This directory holds only the user's own memory and has no namespaces. The `@<login>/` level exists only in a hub: sync maps `projects/<key>/<file>` to `projects/<key>/@<login>/<file>` in the hub's clone, and back. The clone stays transport, kept apart from the data directory. Other members' memory is read from the clone and is never copied into the data directory.

So connecting a hub, or leaving one, moves no local file.

## Names

**Login.** Local to the hub: lowercase letters, digits, `-`, `_`, `.`, starting with a letter or digit. A service decides what a login is; on xchg.app it is the account's login.

**Project key.** The project's git remote without the scheme, credentials, port or `.git`: `github.com/owner/repo`. The host is lowercased, the path is kept as the remote spells it, and a key is compared byte for byte. A key has two or more segments of `A-Z a-z 0-9 . _ -`, and none is `.` or `..`. The key is the same on every machine and for every member, so it identifies the project across hubs and across mail and memory.

A key has a variable number of segments, so a namespace directory is marked with `@`: in a path under `projects/`, the key ends before the first segment that starts with `@`.

A key of the form `local/<path>` belongs to one machine. The client does not send such a project to a hub that has other members.

## Layout

    README.md                             the hub contract
    contacts.md                           members: login, name, contact (same format as a mail hub)
    aliases.tsv                           project key renames
    identity/@<login>/IDENTITY.md         L0, one per member; only in the hub that member keeps identity in
    projects/<key>/@<login>/
      CORE.md                             knowledge about the project, current state
      CORE.log.YYYY-MM.md                 its changes with the code revision
      CORE.archive.YYYY-MM.md             parts moved out of CORE.md
      _tasks/<slug>.md                    open task journals
      _tasks/<slug>.files/                files a task needs beyond a session
      _tasks/archive/YYYY-MM/<slug>.md    closed journals, with their .files/

- The branch is `main`. Nothing else is pushed.
- The tree holds regular files only: no symlinks and no submodules.
- Inside `@<login>/` a client may write files this text does not name, and a service keeps them without reading them. A new path at the root, or directly under `identity/` or `projects/<key>/`, comes only with a new contract number.
- Routing rules are not in the hub. Which hub holds a project is local configuration, and a new machine restores it from the hubs it connects: a project lives in the hub that has `projects/<key>/@<login>/`. The user names only the default hub, and the hub for a project found in two.

`README.md` is written by the client's `hub init` and `hub upgrade` commands and by nothing else. Who may run them is up to the hub: on a plain git hosting any member, on xchg.app only the service's own member. Its header, between two `---` lines at the top of the file:

    ---
    contract: 1
    template: 7.3.0
    search: https://hub.example.com/api/memory/<hub>/search
    ---

`contract` is the layout version. A client of another contract version does not write to the hub. `template` is the client release the text came from. `search` is present only when the hub offers it.

## Files

**Task journal.** A journal is a sequence of records. A record starts at a header line and runs to the next one:

    ## 2026-11-18T09:14:03Z-a3f1 note s:53e2b2ce r:f8b92e4 b:feat/tasks-journal

    header = "## " id " " type *( " " field )
    id     = UTC time "YYYY-MM-DDTHH:MM:SSZ" "-" 4 hex digits
    type   = open | note | decision | next | blocker | checkpoint | close
    field  = name ":" value        ; no spaces in either

The id is unique in the hub. Fields: `s` is the session, `r` the short hash of the project's `HEAD` when the record was written (`r:f8b92e4+` when the working tree had changes), `b` the branch. `r` and `b` are absent outside a git repository and in records written before this contract. A reader accepts a header without fields and ignores a field or a type it does not know. How task state follows from the records is in `docs/tasks.md`.

The client only appends to a journal, with two exceptions: `task redact` rewrites the body of a record that held a secret, and a journal can be deleted whole. Closing a task moves the file to `_tasks/archive/`.

**CORE.md.** Markdown, rewritten freely by its owner's agent. Two things in it have a fixed meaning:

- `# Brief` runs to the next first-level heading and is injected into every session of that member.
- A line ending in `[user YYYY-MM-DD]` was written at the user's word. The agent does not remove, change or archive it without the user's permission, and the client reports a marked line that is gone or changed since the last sync.

`project.md` is gone. What it held becomes marked lines in `CORE.md`.

**CORE.log.YYYY-MM.md.** Records in the journal format, type `core`, appended by the client when it finds `CORE.md` changed (at sync, and before compaction). The body is the unified diff:

    ## 2026-11-18T09:20:11Z-7c02 core s:53e2b2ce r:f8b92e4 b:feat/tasks-journal
    <unified diff of CORE.md>

`CORE.md` stays the current state, and the log is the stream of changes tied to code revisions. A revision that was never pushed can't be resolved by anyone else, and then the branch and the time are what is left.

**CORE.archive.YYYY-MM.md.** Markdown, appended by `core stash`, editable by its owner.

**aliases.tsv.** One rename per line, `<old key><TAB><new key>`. Members add lines, and two versions merge as the union of their lines.

**Secrets.** No file in a hub holds a secret value, only `secret://<name>`. The client scans what it sends.

## Writing

1. A member changes only `identity/@<own login>/`, `projects/<key>/@<own login>/`, their own row in `contacts.md`, and adds lines to `aliases.tsv`.
2. The client fetches, merges and pushes. A push is a fast-forward of `main`.
3. Merging, when the same member's two machines differ:
   - journals and `CORE.log.*`: the records of both sides are joined and sorted by id, so a merge can put records in the middle of a file;
   - `CORE.md`, `IDENTITY.md`: three-way merge, and on a conflict the newer file wins and the other is kept on that machine;
   - an open journal whose every record is in the archive is dropped: it is a closed task that came back.
4. What entered a hub stays in its git history.

A hub may refuse a push for reasons of its own: access, a size limit, a path it does not allow. The client shows every line the remote sent, keeps the local data, and tries again at its next sync. A refusal for breaking this contract starts with `memory-3layer:`, and the client tells the agent what to fix. What a service may check under that prefix:

- a change outside the member's namespace (rule 1);
- `README.md` changed by someone the hub does not let run `hub upgrade`;
- a `contract` the service does not support;
- a symlink or a submodule.

The protocol asks for none of these checks and sets no limits. A service is not expected to check what is inside a journal.

## Reading

A session gets its own member's memory as today: the task index, `IDENTITY.md`, `# Brief`. Other members' namespaces are in the clone, readable and searchable, and are never injected. The session is told once that the project's memory is shared and with which hub. The index adds one line with the count of other members' open tasks, and `memory-3layer state --all` lists them.

Handing a task to another member is not in contract 1.

## Search

Search is a chain of providers, tried in order. The next one is used when a provider fails, never because it found nothing.

- **Local providers** search the data directory and the clones on this machine. They are configured once, globally. Since a clone holds every member's namespace, local search covers a team hub as well.
- **Remote providers** receive queries, and some receive content. They are off unless a rule allows one for a project. A hub's own search is allowed for the projects kept in that hub.

A local provider is a command: the query in its arguments, the scope in the environment, one result per line on stdout, `path:line<TAB>snippet`.

A hub's search, when `README.md` names one. The client sends its token only to the host of the hub's git remote, and ignores a `search` address on any other host.

    POST <search>
    Authorization: Bearer <token>

    {"query": "mongo legacy index", "projects": ["github.com/owner/repo"], "logins": [], "kinds": [], "limit": 20}

    200
    {"indexed": "<commit of main>",
     "results": [{"path": "projects/github.com/owner/repo/@bob/_tasks/archive/2026-10/mongo-move.md",
                  "line": 41, "record": "2026-10-12T08:01:55Z-19be", "kind": "taskarchive",
                  "project": "github.com/owner/repo", "login": "bob",
                  "snippet": "...", "score": 0.81}]}

- `projects`, `logins`, `kinds` narrow the scope, and an empty list means all. `projects` matches a key exactly: the client expands `aliases.tsv` before it asks.
- A kind follows from the path: `identity` (`IDENTITY.md`), `core` (`CORE.md`), `corelog`, `corearchive`, `task` (open journals), `taskarchive` (closed ones). Files under `.files/`, and files this text does not name, are not indexed.
- The unit of a result is a record for journals and `CORE.log.*`, and a section (the text under one heading) for the other files. `record` is the record's id, absent for a section. `line` is the line of the match. `project` is absent for `identity`.
- A result is a pointer plus a short snippet. The client reads the text from its own clone by `path`, so the service needs no endpoint that serves files.
- `score` orders the results of one answer and means nothing beyond it.
- `indexed` is the commit the index was built from, `null` for an empty hub. The client's last push is searchable when it is an ancestor of `indexed`.
- The service indexes `main` after a push, in the background. `identity/` of other members is indexed like the rest: the hub is the trust boundary.
- `limit` is 20 when absent. A service may cap it and may cap the length of a query.

A failure is a status with `{"error": "<code>", "message": "<one line>"}`. On any failure the client goes to the next provider. It also tells the user when a person has to act:

| Status | Meaning | The user is told |
|---|---|---|
| 400 | bad request, or over the service's limits | yes: a client bug |
| 401 | token missing, wrong or expired | yes: renew the token |
| 403 | no access, or no such hub | yes |
| 429 | too many requests | no |
| 503, other 5xx, no connection | index not ready, service down | no |

How results are ranked is the service's business. Results from different providers are shown grouped by provider, not merged into one ranking.

## Migration

Done by the client, per project, when the project first goes to a hub of this contract:

1. In the hub, the project's files go under `projects/<key>/@<login>/`. Nothing moves in the local directory.
2. `project.md` is merged into `CORE.md`, its entries marked `[user <date>]`.
3. `memory-3layer core adopt` shows the repository's `CLAUDE.md` and `.claude-docs/`. The agent checks each fact against the code and moves what still holds into `CORE.md`, unmarked. It deletes nothing in the repository. Removing those files is a commit the user asks for, after a check of which harnesses read their protocol rules from the entry file.

Moving a project into a team hub publishes its whole memory to the team, old journals included. The client says so and asks before the first push.

## Open

- **Secrets between machines.** Not in contract 1. A new machine gets `secret://` references with no values behind them. A likely shape: values encrypted on the client, the hub storing only ciphertext.
- **Shared knowledge.** With a namespace per member, each agent learns the same pitfalls on its own, and search is the only bridge. A team-wide `CORE.md` would need a merge rule that one writer per namespace avoids.
- **Access narrower than the hub.** Contract 1 has none: a second hub is the answer.
- **Letter case in a key.** `github.com/Owner/Repo` and `github.com/owner/repo` are two keys. Two members whose remotes differ in case get two project directories, and only `aliases.tsv` joins them.
- **Leaving a hub.** Who removes a member's row from `contacts.md` is up to the hub. Their namespace stays.
- **Names in the client.** `storage.conf` and the `sync` commands still say storage. Whether they are renamed to hub is undecided.
