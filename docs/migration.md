# Migration

Find your version with `claude plugin list`, or in `CHANGELOG.md` of your copy. Older versions have no plugin: if memory is in `~/.claude`, you are on 6.x or earlier.

## 7.1.1 to 7.1.2

Update the plugin. The next `/memory rotate` folds existing `→ archived` stubs into one line per archive file.

## 7.1.0 to 7.1.1

Update the plugin. On macOS, also run `brew install bash`: sync needs it.

If `$HOME` goes through a symlink, a project with no remote gets a shorter key. Its memory stays under the old one, so move it with `memory-3layer rekey <old> <new>`. `memory-3layer key` prints the new key, and `memory-3layer projects` lists the old one.

## 7.0 to 7.1

Update the plugin: see [INSTALL.md](../INSTALL.md#claude-code-plugin). Data and settings stay as they are.

## 6.x and earlier to 7

Memory moves from `~/.claude` to `~/.local/share/memory-3layer`, and projects are found by git remote instead of by directory. Files are copied, and the old ones stay until you delete them. On several machines, repeat this on each: conflicts resolve as described in [sync.md](sync.md#conflicts).

**1. Copy the data.** From a clone of this repository, nothing needs installing first:

```bash
git clone https://github.com/openronin/memory-3layer.git && cd memory-3layer
bin/memory-3layer migrate claude-code           # shows the plan, changes nothing
bin/memory-3layer migrate claude-code --apply
```

This copies `IDENTITY.md`, `.memory-config`, and each project's `SESSION*.md` and `project.md`. It is safe to repeat.

- When several old folders belong to one project, the newest file wins. The others go to `superseded/<old folder>/` in that project.
- A file containing a secret is skipped and printed. Move the value with `bin/memory-3layer secret adopt <file>:<line> <name>` and run `migrate` again.

**2. Assign what has no project.** A folder whose directory no longer exists lands in `projects/_unassigned/`. Give each one its key:

```bash
ls ~/.local/share/memory-3layer/projects/_unassigned/
bin/memory-3layer assign <old folder> github.com/owner/repo
```

**3. Move the secrets**, if `~/.local/share/agent-secrets` exists. The format is the same:

```bash
mv ~/.local/share/agent-secrets ~/.local/share/memory-3layer-secrets
```

**4. Remove the old install**, or its hooks run alongside the new ones. Keep anything of your own in these places:

- in `~/.claude/settings.json`, the hook entries that call `~/.claude/hooks/session-start.sh`, `pre-compact.sh`, `session-end.sh` or `~/.claude/bin/memory-3layer`;
- those scripts, plus `~/.claude/bin/{memory-3layer,memory-secrets.sh,memory-sync.sh,codemap.sh,memstat.sh}`;
- `~/.claude/commands/{recall,codemap,memory,memstat,migrate-legacy-memory}.md`;
- `~/.claude/CLAUDE.md`, if it holds only the protocol. The plugin delivers the protocol itself.

Skip this step if you stay on a manual install, and run `./install.sh` instead.

**5. Install the new version:** see [INSTALL.md](../INSTALL.md).

From here `memory-3layer` is the installed client. In a terminal, use the `Client:` path from the session context.

**6. Rebuild search**, if you use qmd. The collection is now `memory-3layer`:

```bash
qmd collection remove claude-l0
qmd collection remove claude-projects
memory-3layer refresh
```

**7. Check.** Open a session in a project. The agent should name its goal from `SESSION.md`. `memory-3layer projects` lists every project with memory.

**8. Clean up.** Once this works, delete `SESSION*.md` and `project.md` under `~/.claude/projects/*/memory/`, then `~/.claude/memory/` and `~/.claude/.memory-config`.

### Notes kept by the harness

Files that Claude Code saved in its own memory (`MEMORY.md`, `feedback_*.md` and so on) aren't touched by `migrate`, and the harness goes on using them. To copy them as well:

```bash
memory-3layer import claude-code            # shows the plan
memory-3layer import claude-code --apply    # copies to projects/<key>/imported/claude-code/
```

The copies are unreviewed: move what still holds into `project.md` or the repo's docs.

### Older file formats

No conversion is needed. A `<!-- last_updated: ... -->` comment is read like the YAML frontmatter, and a file with no marker only produces a warning.
