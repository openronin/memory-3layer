#!/usr/bin/env bash
# memory-hub.sh — create a memory hub, bring its README up to date, connect to one.
# Contract: docs/hub.md. Run through `memory-3layer hub`.

set -u

SELF_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
CONFIG_DIR="${MEMORY_3LAYER_CONFIG_DIR:?}"
LOCAL_CONF="$CONFIG_DIR/storage.conf"
TEMPLATE="$SELF_DIR/../templates/hub/README.md"
CONTRACT=1

die() { printf 'memory-3layer: %s\n' "$*" >&2; exit 1; }
g() {
  # The author is whoever runs the command; a machine with no git identity still commits.
  local -a who=()
  git -C "$DIR" config user.name >/dev/null 2>&1 || who+=(-c user.name=memory-3layer)
  git -C "$DIR" config user.email >/dev/null 2>&1 || who+=(-c user.email=memory-3layer@localhost)
  git -C "$DIR" ${who[@]+"${who[@]}"} -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"
}

header() {
  # header <file> <key>: a value from the README header, or nothing.
  awk -v k="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$1" 2>/dev/null
}

write_readme() {
  # write_readme <search url or nothing>: the template, with the hub's search address.
  local search=$1
  [[ -f "$TEMPLATE" ]] || die "the hub template is missing: $TEMPLATE"
  [[ "$search" != *$'\n'* ]] || die "bad search address"
  awk -v s="$search" 'NR > 1 && $0 == "---" && !done { if (s != "") print "search: " s; done = 1 } { print }' "$TEMPLATE" > "$DIR/README.md"
}

clone_dir() {
  DIR=${1:-}
  [[ -n "$DIR" && -d "$DIR" ]] || die "no such directory: ${DIR:-<none>}"
  git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$DIR is not a git working tree: clone the hub's repository, or git init it"
}

parse_search() {
  SEARCH=""; SEARCH_SET=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --search) [[ $# -ge 2 ]] || die "--search needs an address"; SEARCH=$2; SEARCH_SET=1; shift ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
}

cmd_init() {
  clone_dir "${1:-}"; shift
  parse_search "$@"
  [[ -z "$(header "$DIR/README.md" contract)" ]] || die "$DIR is a hub already. To refresh its README: memory-3layer hub upgrade $DIR"
  [[ ! -e "$DIR/projects" && ! -e "$DIR/identity" ]] || die "$DIR holds memory in the old layout. A hub starts empty."
  git -C "$DIR" rev-parse -q --verify HEAD >/dev/null 2>&1 || git -C "$DIR" symbolic-ref HEAD refs/heads/main
  write_readme "$SEARCH"
  [[ -f "$DIR/contacts.md" ]] || printf '# Contacts\n\n| login | name | aliases | contact |\n|---|---|---|---|\n' > "$DIR/contacts.md"
  g add README.md contacts.md
  g commit -q -m "[memory-3layer] hub init, contract $CONTRACT" || die "cannot commit in $DIR"
  printf 'Hub created in %s, contract %s. Push it: git -C %s push origin main\n' "$DIR" "$CONTRACT" "$DIR"
}

cmd_upgrade() {
  clone_dir "${1:-}"; shift
  parse_search "$@"
  local has
  has=$(header "$DIR/README.md" contract)
  [[ -n "$has" ]] || die "$DIR is not a hub. To make it one: memory-3layer hub init $DIR"
  [[ "$has" -le "$CONTRACT" ]] 2>/dev/null || die "the hub is on contract $has, this client knows $CONTRACT: update the client"
  [[ $SEARCH_SET -eq 1 ]] || SEARCH=$(header "$DIR/README.md" search)
  write_readme "$SEARCH"
  g add README.md
  if g diff --cached --quiet; then echo "README.md is up to date."; return 0; fi
  g commit -q -m "[memory-3layer] hub upgrade, contract $CONTRACT" || die "cannot commit in $DIR"
  printf 'README.md updated. Push it: git -C %s push origin main\n' "$DIR"
}

fetch_token() {
  # fetch_token <url> <secret name>: the token goes from the service into the secret store
  # and is never printed. The answer is the token as plain text, or JSON with "token".
  local url=$1 name=$2 body tok
  command -v curl >/dev/null || die "curl is needed to fetch the token"
  body=$(curl -fsS -X POST --max-time 30 "$url") || die "could not get a token from the address given. A setup link works once and for a limited time: ask for a new one"
  tok=$(printf '%s' "$body" | sed -nE 's/.*"token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1)
  [[ -n "$tok" ]] || tok=$(printf '%s' "$body" | tr -d '[:space:]')
  [[ -n "$tok" && "$tok" != *[\{\}\<\>]* ]] || die "the service did not answer with a token"
  printf '%s' "$tok" | bash "$SELF_DIR/memory-secrets.sh" put "$name" >/dev/null || die "could not store the token"
}

cmd_add() {
  # add <name> <remote> --login <login> [--token-from <url>]
  local name=${1:-} remote=${2:-} login="" from="" secret
  [[ -n "$name" && -n "$remote" ]] || die "usage: hub add <name> <remote> --login <login> [--token-from <url>]"
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --login) login=${2:-}; shift ;;
      --token-from) from=${2:-}; shift ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "bad hub name '$name' (lowercase letters, digits, . _ -)"
  [[ "$login" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "--login is required: lowercase letters, digits, . _ -"
  [[ ! "$remote" =~ ://[^/@:]+:[^/@]+@ ]] || die "the address has a password in it. Pass the token with --token-from"
  mkdir -p "$CONFIG_DIR"; touch "$LOCAL_CONF"
  ! grep -qxF "[storage $remote]" "$LOCAL_CONF" || die "$remote is already in $LOCAL_CONF"
  secret="hub-$name"
  [[ -z "$from" ]] || fetch_token "$from" "$secret"
  # A rule outside a section has to come before the first section.
  if ! grep -qE '^[[:space:]]*default[[:space:]]*=' "$LOCAL_CONF"; then
    { printf 'default = %s\n' "$remote"; cat "$LOCAL_CONF"; } > "$LOCAL_CONF.$$.tmp" && mv -f "$LOCAL_CONF.$$.tmp" "$LOCAL_CONF"
  fi
  {
    printf '\n[storage %s]\nlogin = %s\n' "$remote" "$login"
    [[ -z "$from" ]] || printf 'username = %s\npassword = secret://%s\n' "$login" "$secret"
  } >> "$LOCAL_CONF"
  printf 'Hub %s connected as %s.\n' "$name" "$login"
  if [[ "$(sed -nE 's/^[[:space:]]*default[[:space:]]*=[[:space:]]*//p' "$LOCAL_CONF" | head -n1)" == "$remote" ]]; then
    echo "It is the default: memory with no rule of its own goes there. Run: memory-3layer sync"
  else
    printf 'Nothing goes there yet. To keep a project in it, add to %s:\n  [project <key>]\n  default = %s\n' "$LOCAL_CONF" "$remote"
  fi
}

cmd_contact() {
  # contact rm <clone dir> <login>: take a member out of the contact book. Their
  # namespace and the history stay. Commits, does not push.
  [[ "${1:-}" == rm && $# -eq 3 ]] || die "usage: hub contact rm <clone dir> <login>"
  local login=$3
  clone_dir "$2"
  [[ "$login" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "bad login '$login'"
  grep -qF "| $login |" "$DIR/contacts.md" 2>/dev/null || die "no $login in contacts.md"
  grep -vF "| $login |" "$DIR/contacts.md" > "$DIR/contacts.md.$$.tmp" && mv -f "$DIR/contacts.md.$$.tmp" "$DIR/contacts.md"
  g add contacts.md
  g commit -q -m "[memory-3layer] contacts: -$login" || die "cannot commit in $DIR"
  printf 'Removed %s from contacts.md. Push it: git -C %s push origin main\n' "$login" "$DIR"
}

sub=${1:-}; [[ $# -gt 0 ]] && shift
case "$sub" in
  contact) cmd_contact "$@" ;;
  init) cmd_init "$@" ;;
  upgrade) cmd_upgrade "$@" ;;
  add) cmd_add "$@" ;;
  *) echo "usage: hub init <clone dir> [--search <url>] | hub upgrade <clone dir> [--search <url>] | hub add <name> <remote> --login <login> [--token-from <url>] | hub contact rm <clone dir> <login>" >&2; exit 2 ;;
esac
