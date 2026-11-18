# Memory hub protocol

Status: draft, `contract: 1`. Nothing here is implemented yet.

This is the contract between the memory-3layer client and a memory hub. The client side is this repository. A hosting service (xchg.app is the first) implements the hub side from this text alone, the way it reads a mail hub from the xchg contract.

## What a hub is

A memory hub is a git repository with the layout below. It replaces what `docs/sync.md` calls a storage.

- **Git is the transport.** Reading is a fetch, writing is a commit and a push. Any git hosting can hold a hub. Everything a service adds (search, write checks) is optional, and the client works without it.
- **A hub is a trust boundary.** Everyone with access reads everything in it. A team hub is used by a team that may see all of its projects. What is personal goes into a separate private hub.
- **One writer per namespace.** A member writes only under their own login. So two people never edit the same file, and a push conflict can only come from the same person's other machine.
- **A hub holds knowledge about code, apart from the code.** The repository entry files (`CLAUDE.md`, `.claude-docs/`) stop being a memory layer. See [Migration](#migration).

A user is usually in several hubs: a private one for `IDENTITY.md` and personal projects, and a team hub per team. The client routes each project to one hub, with the rules in `docs/sync.md`.

## Names

**Login.** Local to the hub: lowercase letters, digits, `-`, `_`, `.`, starting with a letter or digit. On a service that also hosts mail hubs, a person's login is the same in both.

**Project key.** The project's git remote without the scheme, credentials or `.git`: `github.com/owner/repo`. It is the same on every machine and for every member, so it identifies the project across hubs and across mail and memory. A key of the form `local/<path>` belongs to one machine and is refused in a hub with more than one member.

A key has a variable number of path segments. A namespace directory is therefore marked with `@`, which no key segment starts with.

## Layout

    README.md                             the hub contract; the header holds contract: N
    contacts.md                           members: login, name, contact (same format as a mail hub)
    routing.conf                          routing rules that travel with the user (private hubs only)
    aliases.tsv                           project key renames, merged as a union
    identity/@<login>/IDENTITY.md         L0, one per member; only in the hub that member routes identity to
    projects/<key>/@<login>/
      CORE.md                             knowledge about the project, current state
      CORE.log.YYYY-MM.md                 its changes with the code revision, append-only
      CORE.archive.YYYY-MM.md             parts moved out of CORE.md
      _tasks/<slug>.md                    open task journals
      _tasks/<slug>.files/                files a task needs beyond a session
      _tasks/archive/YYYY-MM/<slug>.md    closed journals, with their .files/

Nothing else is written under `projects/` or `identity/`. A service must ignore, and keep, files it does not know: a newer client may add them.

`README.md` belongs to the client and is overwritten on upgrade. Its header:

    contract: 1
    template: 7.3.0
    search: https://hub.example.com/api/memory/<hub>/search

`contract` is the layout version. A client of another contract version refuses to write. `template` is the client release the text came from. `search` is present only when the hub offers it.

## Files

**Task journal.** Format and state rules are in `docs/tasks.md`. A record header:

    ## 2026-11-18T09:14:03Z-a3f1 note s:53e2b2ce r:f8b92e4 b:feat/tasks-journal

`r:` and `b:` are new: the short hash of the project's `HEAD` and its branch when the record was written, `r:f8b92e4+` when the working tree had changes. They are omitted outside a git repository. Readers must accept headers without them, and must ignore fields they do not know.

**CORE.md.** Markdown, rewritten freely by its owner's agent. Two things in it have a fixed meaning:

- `# Brief` runs to the next first-level heading and is injected into every session of that member.
- A line ending in `[user YYYY-MM-DD]` was written at the user's word. The agent does not remove, change or archive it without the user's permission. The client reports a marked line that is gone or changed since the last sync.

`project.md` is gone. What it held becomes marked lines in `CORE.md`.

**CORE.log.YYYY-MM.md.** Written only by the client, when it finds `CORE.md` changed since the last record (at sync, and before compaction). One record per change:

    ## 2026-11-18T09:20:11Z-7c02 core s:53e2b2ce r:f8b92e4 b:feat/tasks-journal
    <unified diff of CORE.md>

`CORE.md` stays the current state, and the log is the stream of changes tied to code revisions. A revision that was never pushed can't be resolved by anyone else, and then the branch and the time are what is left.

**Secrets.** No file in a hub holds a secret value, only `secret://<name>`. The client scans what it sends. A hub may scan too and refuse the push.

## Writing

1. A member changes only `identity/@<own login>/`, `projects/<key>/@<own login>/`, their own row in `contacts.md`, and adds lines to `aliases.tsv`.
2. The client fetches, merges and pushes. A push is always a fast-forward of the default branch.
3. Merging, when the same member's two machines differ:
   - journals and `CORE.log.*`: the records of both sides are joined and sorted by id. No record is ever dropped;
   - `CORE.md`, `IDENTITY.md`: three-way merge, and on a conflict the newer file wins and the other is kept beside it as `superseded/`, on that machine only;
   - an open journal whose every record is in the archive is dropped: it is a closed task that came back.
4. A deletion is pushed only for a file that machine had at its last sync. More than ten at once are held back.
5. What entered a hub stays in its git history. Removing it needs the hub's administrator.

A hub may refuse a push and say why in one line starting with `memory-3layer:`. The client shows the line, keeps the local data and does not retry. Reasons a service is expected to check, none of them required:

- a change outside the member's namespace (rule 1);
- a rewritten or removed record in a journal or a `CORE.log.*` file;
- a `contract` the service does not support;
- a `local/` key in a hub with several members;
- text that looks like a secret.

A service never writes to the repository itself.

## Reading

A session gets its own member's memory as today: the task index, `IDENTITY.md`, `# Brief`. Other members' namespaces are in the clone, readable and searchable, and are never injected. The session is told once that the project's memory is shared and with which hub. The index adds one line with the count of other members' open tasks, and `memory-3layer state --all` lists them.

A member can hand a task to another: a `handoff` record names the receiver and closes the journal, and the receiver's new journal names its source in the `open` record. This is not in contract 1.

## Search

Search is a chain of providers, tried in order. The next one is used only when a provider is unreachable or fails, never because it found nothing.

- **Local providers** search the data directory and the clones on this machine. They are configured once, globally. Since a clone holds every member's namespace, local search covers a team hub as well.
- **Remote providers** receive queries, and some receive content. They are off unless a routing rule allows one for a project, with the same precedence as storage rules. A hub's own search is allowed for the projects routed to that hub.

A local provider is a command: the query in its arguments, the scope in the environment, one result per line on stdout, `path:line<TAB>snippet`.

A hub's search, when `README.md` names one:

    POST <search>
    Authorization: Bearer <token>

    {"query": "mongo legacy index", "projects": ["github.com/owner/repo"], "logins": [], "kinds": [], "limit": 20}

    {"indexed": "<commit of the default branch>",
     "results": [{"path": "projects/github.com/owner/repo/@bob/_tasks/archive/2026-10/mongo-move.md",
                  "line": 41, "record": "2026-10-12T08:01:55Z-19be", "kind": "task",
                  "project": "github.com/owner/repo", "login": "bob",
                  "snippet": "...", "score": 0.81}]}

- `projects`, `logins`, `kinds` narrow the scope, and an empty list means all. Kinds: `identity`, `core`, `corelog`, `task`, `archive`.
- A result is a pointer plus a short snippet. The client reads the text from its own clone by `path`, so the service needs no endpoint that serves files.
- `indexed` lets the client see that its last push is not searchable yet.
- The service indexes the default branch after each push. `identity/` of other members is indexed like the rest: the hub is the trust boundary.
- The token is a `secret://` reference in the client's local configuration.

How results are ranked is the service's business. Results from different providers are shown grouped by provider, not merged into one ranking.

## Migration

Done by the client, per project, when the project is first routed to a hub of this contract:

1. `projects/<key>/*` moves to `projects/<key>/@<login>/`.
2. `project.md` is merged into `CORE.md`, its entries marked `[user <date>]`.
3. `memory-3layer core adopt` shows the repository's `CLAUDE.md` and `.claude-docs/`. The agent checks each fact against the code and moves what still holds into `CORE.md`, unmarked. It deletes nothing in the repository. Removing those files is a commit the user asks for, after a check of which harnesses read their protocol rules from the entry file.

Moving a project into a team hub publishes its whole memory to the team, old journals included. The client says so and asks before the first push.

## Open

- **Secrets between machines.** Not in contract 1. A new machine gets `secret://` references with no values behind them. A likely shape: values encrypted on the client, the hub storing only ciphertext.
- **Shared knowledge.** With a namespace per member, each agent learns the same pitfalls on its own, and search is the only bridge. A team-wide `CORE.md` would need a merge rule that one writer per namespace avoids.
- **Access narrower than the hub.** Contract 1 has none: a second hub is the answer.
- **Names in the client.** `storage.conf` and the `sync` commands still say storage. Whether they are renamed to hub is undecided.
- **Per-layer routing.** With `project.md` gone the layers are `identity`, `session` and `archive`. Whether a project's archive may still live in a different hub than its `CORE.md` is undecided.
