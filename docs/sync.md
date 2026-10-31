# Sync between machines

Status: implemented in `bin/memory-sync.sh`; commands are under `memory-3layer sync`.

## Which storage holds what

The user configures storages. Sync runs against every storage in use.

| Data | Storage is set | Notes |
|---|---|---|
| L0 (`IDENTITY.md`) | globally only | one per user, belongs to no project |
| L1 in the repo (`CLAUDE.md`, `.claude-docs`) | not configurable | travels with the code |
| `project.md`, imported notes | by layer, by project | |
| L2 (`SESSION.md`) | by layer, by project | |
| L2 archive | by layer, by project | defaults to the L2 storage |

The most specific rule wins:

    project + layer  >  project  >  layer  >  default

A project beats a layer on purpose. If a project is assigned to a corporate storage and all L2 to a personal one, that project's L2 stays corporate. The reverse order would leak work data because of a rule that never mentions the project.

`none` is a valid storage at every level and means the data stays on this machine.

Other rules:

- Credentials are never in the configuration: an ssh key, or `secret://<name>`.
- An unreachable storage doesn't block the others. Each one reports its own state.
- Changing a project's storage copies the data. Removing it from the old storage is done by hand and can't reach git history, so `sync status` warns about that.
- `memory-3layer secret scan` runs before anything is sent. A file with a finding stays local and blocks only itself.

## Configuration format

Same grammar as xchg: `key = value`, `[section]`, `# comment`.

    default = git@xchg.app:someone/memory.git
    archive = none

    [project gitlab.example.com/team/app]
    default = git@gitlab.example.com:someone/memory.git
    archive = none

    [project github.com/someone/private-notes]
    default = none

Keys: `default`, `identity` (global only), `project` (the `project.md` layer), `session`, `archive`.

Two files. At the same level of the order above, the first one wins:

1. `~/.config/memory-3layer/storage.conf`: this machine only, never synced.
2. `routing.conf` at the root of the data directory: goes to the default storage and travels to a new machine.

A new machine needs one address, the default storage. A rule that must not be visible in that storage, such as a corporate project's name or address, goes in the local file and is set again on each machine.

`aliases.tsv` entries are stored with the project's own storage, for the same reason.

## Access

Sync runs plain git, so what already works for git works here: `~/.ssh/config`, an agent, credential helpers. For one storage, add a section to `storage.conf`:

    [storage git@gitlab.example.com:someone/memory.git]
    ssh_key = ~/.ssh/memory_key        # used alone, without the agent or other keys

    [storage git@other.example.com:someone/memory.git]
    ssh_agent = ~/.ssh/agent.sock

    [storage https://gitlab.example.com/someone/memory.git]
    username = oauth2
    password = secret://gitlab-memory

- `[storage]` is read only from `storage.conf`. Paths belong to one machine, and `routing.conf` travels.
- `password` is only ever `secret://<name>`. A literal value, or a password inside the address, is refused.
- Sync never prompts. A key with a passphrase and no agent can't work in the background, so hooks need a key without one (limited to this repository), a token, or a running agent.
- `memory-3layer sync check` tests read and write access, changes nothing, and says what to fix.

## Mechanics

Each storage is a private git repository, cloned to `~/.local/state/memory-3layer/stores/<id>/`. The data directory stays a single plain tree, so agents, hooks and search don't know about storages. Clones are only transport.

    sync, for each storage:
      fetch
      for each file routed here: three-way compare of data dir, clone, remote
      scan what is going out
      commit, push

Triggers:

| When | What | If it fails |
|---|---|---|
| Session start | pull, limited to a few seconds | start with local data, say so |
| Before compaction, session end | commit and push in the background | retried at the next trigger |
| `memory-3layer sync` | everything, in the foreground | reported per storage |

A harness with no suitable hook relies on the session start of the next session, or on the command.

## Conflicts

One repo has one L2, so two machines can change the same `SESSION.md`.

- Git merges changes in different parts of a file.
- If it can't, the newer version by `last_updated` keeps the name, and the other goes to `superseded/conflict-<host>/SESSION.md`. Nothing is lost.
- The agent is told at session start that a superseded version exists, and merges it with the user.

Archives are append-only in practice and rarely conflict. The same rule applies to them, `project.md`, and `IDENTITY.md`.
