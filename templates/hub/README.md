---
contract: 1
template: 7.2.0-dev
---
# Memory hub

Memory of coding agents, kept apart from the code it is about. A hub is one git repository and
one trust boundary: everyone with access reads everything in it. It is never public.

The client is `memory-3layer`. This file belongs to it and is overwritten by `memory-3layer hub
upgrade`; rules of your own hub go into another file. The full contract is `docs/hub.md` in
https://github.com/openronin/memory-3layer.

## Layout

    README.md                             this file
    contacts.md                           members: login, name, contact
    aliases.tsv                           project key renames
    identity/@<login>/IDENTITY.md         who a member is, for their own agents
    projects/<key>/@<login>/
      CORE.md                             what that member's agent knows about the project
      CORE.log.YYYY-MM.md                 changes of CORE.md with the code revision
      CORE.archive.YYYY-MM.md             parts moved out of CORE.md
      _tasks/<slug>.md                    open task journals
      _tasks/archive/YYYY-MM/<slug>.md    closed ones

`<key>` is the project's git remote without the scheme and `.git`: `github.com/owner/repo`.

## Rules

1. A member writes only under their own `@<login>`. Everyone reads everything.
2. The branch is `main`, and a push is a fast-forward. Regular files only.
3. No secret values: only `secret://<name>`.
4. Files are written by the client. A journal is appended to, not edited.
