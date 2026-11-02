#!/usr/bin/env bash
# Tests for sync. Machines are temp HOMEs, storages are temp bare repositories.
# No real data, no network. Fake credentials are assembled at runtime.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin/memory-3layer"
T=$(mktemp -d)
# Hooks start background syncs, which must finish before the temp dir goes away.
cleanup() { local i; [[ -n "${HTTP_PID:-}" ]] && kill "$HTTP_PID" 2>/dev/null; for i in $(seq 1 50); do [[ -z "$(find "$T" -name '*.lock' 2>/dev/null)" ]] && break; sleep 0.2; done; sleep 0.3; rm -rf "$T"; }
trap cleanup EXIT
unset MEMORY_3LAYER_HOME MEMORY_3LAYER_SECRETS MEMORY_3LAYER_CONFIG XDG_DATA_HOME XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_HOME
fail=0; n=0
ok() { n=$((n+1)); if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$3], got [$2]"; fail=1; fi; }

# on <machine> <args...>: run memory-3layer on one machine
on() { local m=$1; shift; HOME="$T/$m" bash "$BIN" "$@"; }
data() { printf '%s/%s/.local/share/memory-3layer' "$T" "$1"; }
conf() { printf '%s/%s/.config/memory-3layer/storage.conf' "$T" "$1"; }
bare() { git init -q --bare -b main "$T/$1.git"; printf '%s/%s.git' "$T" "$1"; }
mk() { # mk <machine> <path> <content>
  mkdir -p "$(dirname "$(data "$1")/$2")"; printf '%s\n' "$3" > "$(data "$1")/$2"
}
rd() { cat "$(data "$1")/$2" 2>/dev/null; }
exists() { test -e "$(data "$1")/$2"; echo $?; }
session() { printf -- '---\nlast_updated: %s\n---\n%s\n' "$1" "$2"; }
K=projects/github.com/o/r

mkdir -p "$T/a" "$T/b" "$T/c"

# --- nothing configured ---
ok "no storage: nothing happens" "$(on a sync --quiet; echo $?)" 0
case "$(on a sync)" in *"No storage configured"*) r=y ;; *) r=n ;; esac; ok "no storage: says so" $r y
case "$(on a context </dev/null)" in *[Ss]ync*) r=y ;; *) r=n ;; esac; ok "no storage: context has no sync note" $r n

# --- first push, second machine starts empty ---
S=$(bare main)
mk a identity/IDENTITY.md "me"
mk a "$K/SESSION.md" "$(session 2026-01-01T00:00:00Z 'from a')"
mk a "$K/project.md" "facts"
mk a "$K/SESSION.archive.2026-01.md" "old"
mk a "$K/imported/claude-code/note.md" "native"
on a sync init "$S" >/dev/null
ok "init writes the local file" "$(cat "$(conf a)")" "default = $S"
on a sync init "$S" >/dev/null 2>&1; ok "init won't replace a default" $? 2
on a sync --quiet; ok "first sync succeeds" $? 0
ok "storage holds the file" "$(git -C "$S" show main:$K/project.md)" facts
on b sync init "$S" >/dev/null
on b sync --quiet
ok "empty machine gets identity" "$(rd b identity/IDENTITY.md)" me
ok "empty machine gets L2" "$(rd b "$K/SESSION.md" | tail -1)" "from a"
ok "empty machine gets archive" "$(rd b "$K/SESSION.archive.2026-01.md")" old
ok "empty machine gets imported" "$(rd b "$K/imported/claude-code/note.md")" native
on b sync --quiet
ok "storage intact after the empty machine" "$(git -C "$S" show main:$K/project.md)" facts

# --- changes, deletions ---
mk a "$K/project.md" "facts 2"; on a sync --quiet; on b sync --quiet
ok "change travels" "$(rd b "$K/project.md")" "facts 2"
rm "$(data a)/$K/SESSION.archive.2026-01.md"; on a sync --quiet; on b sync --quiet
ok "deletion travels" "$(exists b "$K/SESSION.archive.2026-01.md")" 1
ok "deletion leaves other files" "$(rd b "$K/project.md")" "facts 2"

# --- merge and conflict ---
printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\n' > "$(data a)/$K/notes.md"; on a sync --quiet; on b sync --quiet
sed -i 's/one/ONE/' "$(data a)/$K/notes.md"; sed -i 's/seven/SEVEN/' "$(data b)/$K/notes.md"
on a sync --quiet; on b sync --quiet; on a sync --quiet
ok "git merges different parts" "$(sed -n '1p;7p' "$(data a)/$K/notes.md" | tr '\n' ' ')" "ONE SEVEN "
ok "merge reaches both" "$(md5sum < "$(data a)/$K/notes.md")" "$(md5sum < "$(data b)/$K/notes.md")"
session 2026-03-01T00:00:00Z 'newer from a' > "$(data a)/$K/SESSION.md"
session 2026-02-01T00:00:00Z 'older from b' > "$(data b)/$K/SESSION.md"
on a sync --quiet; on b sync --quiet; on a sync --quiet
ok "conflict: newer keeps the name" "$(rd b "$K/SESSION.md" | tail -1)" "newer from a"
ok "conflict: same on the other machine" "$(rd a "$K/SESSION.md" | tail -1)" "newer from a"
L=$(find "$(data a)/$K/superseded" -name SESSION.md)
ok "conflict: older version kept" "$(tail -1 "$L")" "older from b"
case "$L" in */superseded/conflict-*/SESSION.md) r=y ;; *) r="$L" ;; esac; ok "conflict: kept under superseded" "$r" y
case "$(cd "$T" && mkdir -p r && git -C r init -q 2>/dev/null; git -C r remote add origin git@github.com:o/r.git 2>/dev/null; cd r && HOME="$T/a" bash "$BIN" context </dev/null)" in
  *"superseded"*) r=y ;; *) r=n ;; esac; ok "conflict: context tells the agent" $r y

# --- two machines with the same file on their first sync ---
S2=$(bare first)
mk c "$K/x.md" "from c"
HOME="$T/c" bash "$BIN" sync init "$S2" >/dev/null; on c sync --quiet
mkdir -p "$T/d"; mk d "$K/x.md" "from d"; touch -d '2020-01-01' "$(data d)/$K/x.md"
on d sync init "$S2" >/dev/null; on d sync --quiet
ok "first sync: newer stays" "$(rd d "$K/x.md")" "from c"
ok "first sync: other version kept" "$(cat "$(find "$(data d)/$K/superseded" -name x.md)")" "from d"

# --- routing ---
mkdir -p "$T/e" "$T/f"
P=$(bare personal); W=$(bare work); A=$(bare arch)
K2=projects/gitlab.example.com/t/app
K3=projects/github.com/o/local-only
mk e identity/IDENTITY.md me
mk e "$K/SESSION.md" s1; mk e "$K/SESSION.archive.1.md" a1; mk e "$K/project.md" p1
mk e "$K2/SESSION.md" s2; mk e "$K2/SESSION.archive.1.md" a2; mk e "$K2/project.md" p2
mk e "$K3/SESSION.md" s3
mkdir -p "$(dirname "$(conf e)")"
cat > "$(conf e)" <<X
default = $P
archive = $A   # a comment
[project gitlab.example.com/t/app]
default = $W
[project github.com/o/local-only]
default = none
X
on e sync --quiet; ok "several storages succeed" $? 0
has() { if git -C "$1" cat-file -e "main:$2" 2>/dev/null; then echo 0; else echo 1; fi; }
ok "default takes identity" "$(has "$P" identity/IDENTITY.md)" 0
ok "default takes L2" "$(has "$P" "$K/SESSION.md")" 0
ok "layer rule moves an archive" "$(has "$A" "$K/SESSION.archive.1.md")" 0
ok "archive left the default" "$(has "$P" "$K/SESSION.archive.1.md")" 1
ok "project goes to its storage" "$(has "$W" "$K2/SESSION.md")" 0
ok "project beats a layer rule" "$(has "$W" "$K2/SESSION.archive.1.md")" 0
ok "work data not in default" "$(has "$P" "$K2/SESSION.md")" 1
ok "work data not in layer storage" "$(has "$A" "$K2/SESSION.archive.1.md")" 1
ok "none stays local: default" "$(has "$P" "$K3/SESSION.md")" 1
ok "none file still on disk" "$(rd e "$K3/SESSION.md")" s3
ok "route: project" "$(on e sync route gitlab.example.com/t/app | sed -n 3p | awk '{print $2}')" "$W"
ok "route: identity is global" "$(on e sync route x/y/z | sed -n 1p | awk '{print $2}')" "$P"

# project + layer is the most specific
cat >> "$(conf e)" <<X
[project github.com/o/r]
session = $W
X
mk e "$K/SESSION.md" s1b; on e sync --quiet
ok "project + layer wins" "$(git -C "$W" show main:$K/SESSION.md)" s1b
case "$(on e sync status)" in *"routed elsewhere"*) r=y ;; *) r=n ;; esac; ok "status warns about the old storage" $r y
ok "old storage keeps it, no deletion" "$(has "$P" "$K/SESSION.md")" 0

# --- routing travels, local rule wins ---
S3=$(bare routed); W3=$(bare routedwork)
mkdir -p "$T/g" "$T/h"
mk g routing.conf "default = $S3
[project gitlab.example.com/t/app]
default = $W3"
mk g "$K2/SESSION.md" w1; mk g "$K/project.md" p1
mkdir -p "$(dirname "$(conf g)")"; printf 'default = %s\n' "$S3" > "$(conf g)"
on g sync --quiet
ok "routing goes to the default storage" "$(has "$S3" routing.conf)" 0
on h sync init "$S3" >/dev/null; on h sync --quiet
ok "new machine learns routing and pulls the other storage" "$(rd h "$K2/SESSION.md")" w1
mkdir -p "$T/i"; mkdir -p "$(dirname "$(conf i)")"
printf 'default = %s\n[project gitlab.example.com/t/app]\ndefault = none\n' "$S3" > "$(conf i)"
on i sync --quiet
ok "local rule beats routing" "$(exists i "$K2/SESSION.md")" 1

# --- one storage down doesn't stop the others ---
mkdir -p "$T/j"; G=$(bare good)
mk j "$K/project.md" p; mk j "$K2/project.md" q
mkdir -p "$(dirname "$(conf j)")"
printf 'default = %s\n[project github.com/o/r]\ndefault = %s/gone.git\n' "$G" "$T" > "$(conf j)"
printf 'default = %s/gone.git\n[project gitlab.example.com/t/app]\ndefault = %s\n' "$T" "$G" > "$(conf j)"
on j sync --quiet 2>/dev/null; ok "unreachable storage is reported" $? 1
ok "the other storage still synced" "$(has "$G" "$K2/project.md")" 0
ok "local data untouched" "$(rd j "$K/project.md")" p
case "$(on j sync status)" in *"fail (not found)"*) r=y ;; *) r=n ;; esac; ok "status shows the failed storage" $r y
mkdir -p "$T/r2"; git -C "$T/r2" init -q; git -C "$T/r2" remote add origin git@github.com:o/r.git
case "$(cd "$T/r2" && HOME="$T/j" bash "$BIN" context </dev/null)" in *"not found"*) r=y ;; *) r=n ;; esac; ok "context says a storage is down" $r y

# --- secrets ---
mkdir -p "$T/k" "$T/l"; X=$(bare secrets)
FAKE="ghp""_$(printf 'a1B2%.0s' {1..10})"
mk k "$K/ok.md" "clean"; mk k "$K/SESSION.md" "state 1"
on k sync init "$X" >/dev/null; on k sync --quiet
mk k "$K/SESSION.md" "token $FAKE"; mk k "$K/leak.md" "token $FAKE"; mk k "$K/ok.md" "clean 2"
out=$(on k sync 2>&1)
case "$out" in *"$FAKE"*) r=leak ;; *) r=clean ;; esac; ok "output hides the secret" $r clean
ok "new file with a secret stays local" "$(has "$X" "$K/leak.md")" 1
case "$(git -C "$X" show main:$K/SESSION.md)" in *"$FAKE"*) r=leak ;; *) r=clean ;; esac; ok "changed file with a secret stays out" $r clean
case "$(git -C "$X" log --all -p)" in *"$FAKE"*) r=leak ;; *) r=clean ;; esac; ok "nothing in storage history" $r clean
ok "other files still go" "$(git -C "$X" show main:$K/ok.md)" "clean 2"
ok "local version not overwritten" "$(rd k "$K/SESSION.md")" "token $FAKE"
PW="Pr0d-Pa55-Word"
on l sync init "https://u:$PW@example.com/x.git" >/dev/null 2>&1; ok "init refuses a password in the address" $? 2
mkdir -p "$(dirname "$(conf l)")"; printf 'default = https://u:%s@example.com/x.git\n' "$PW" > "$(conf l)"
out=$(on l sync 2>&1); rc=$?; ok "sync refuses a password in the address" $rc 1
case "$out" in *"$PW"*) r=leak ;; *) r=clean ;; esac; ok "refusal hides the password" $r clean
ok "no state file for a refused address" "$(find "$T/l" -name '*.state' | wc -l | tr -d ' ')" 0

# --- aliases follow the project's storage ---
mkdir -p "$T/m" "$T/n"; Y=$(bare al1); Z=$(bare al2)
mk m aliases.tsv "$(printf 'old/personal\tgithub.com/o/r\nold/work\tgitlab.example.com/t/app')"
mkdir -p "$(dirname "$(conf m)")"
printf 'default = %s\n[project gitlab.example.com/t/app]\ndefault = %s\n' "$Y" "$Z" > "$(conf m)"
mk m "$K2/project.md" q
on m sync --quiet
ok "alias goes to the project's storage" "$(git -C "$Z" show main:aliases.tsv)" "$(printf 'old/work\tgitlab.example.com/t/app')"
ok "work alias not in the default" "$(git -C "$Y" show main:aliases.tsv)" "$(printf 'old/personal\tgithub.com/o/r')"
on n sync init "$Y" >/dev/null; on n sync --quiet
ok "alias reaches a new machine" "$(rd n aliases.tsv)" "$(printf 'old/personal\tgithub.com/o/r')"

# a key that starts with a dash, as the old layout made them, must not repeat
mkdir -p "$T/da" "$T/db"; D=$(bare dash)
mk da aliases.tsv "$(printf -- '-home-x-old\tgithub.com/o/r')"
on da sync init "$D" >/dev/null; on da sync --quiet; on da sync --quiet
ok "dash alias isn't duplicated" "$(rd da aliases.tsv | wc -l | tr -d ' ')" 1
ok "dash alias once in storage" "$(git -C "$D" show main:aliases.tsv | wc -l | tr -d ' ')" 1
on db sync init "$D" >/dev/null; on db sync --quiet
ok "dash alias reaches a new machine" "$(rd db aliases.tsv)" "$(printf -- '-home-x-old\tgithub.com/o/r')"

# the user's own git settings must not change the bytes
mkdir -p "$T/ca" "$T/cb"; CR=$(bare crlf)
for m in ca cb; do git config --file "$T/$m/.gitconfig" core.autocrlf true; done
mk ca "$K/project.md" "line one"; on ca sync init "$CR" >/dev/null
out=$(on ca sync 2>&1); case "$out" in *CRLF*) r=warn ;; *) r=clean ;; esac; ok "autocrlf: no warning" "$r" clean
on cb sync init "$CR" >/dev/null; on cb sync --quiet; on cb sync --quiet; on ca sync --quiet
ok "autocrlf: new machine keeps LF" "$(grep -c $'\\r' "$(data cb)/$K/project.md")" 0
ok "autocrlf: origin machine keeps LF" "$(grep -c $'\\r' "$(data ca)/$K/project.md")" 0
ok "autocrlf: storage keeps LF" "$(git -C "$CR" show main:$K/project.md | grep -c $'\\r')" 0

# --- access: ssh, through a stub that logs what it is given ---
A1=$T/sshroot; mkdir -p "$A1" "$T/sa" "$T/bin"; git init -q --bare -b main "$A1/x.git"
cat > "$T/bin/stub-ssh" <<X
#!/bin/bash
printf 'SOCK=%s ARGS=%s\n' "\${SSH_AUTH_SOCK:-}" "\$*" >> "$T/ssh.log"
[[ -f "$T/deny" ]] && { echo 'Permission denied (publickey).' >&2; exit 255; }
[[ -f "$T/hostkey" ]] && { echo 'Host key verification failed.' >&2; exit 255; }
cmd="\${*: -1}"
[[ -f "$T/ro" && "\$cmd" == git-receive-pack* ]] && { echo 'ERROR: This deploy key does not have write access. You are not allowed to push.' >&2; exit 1; }
cd "$A1" && exec sh -c "\$cmd"
X
chmod +x "$T/bin/stub-ssh"
export GIT_SSH_COMMAND="$T/bin/stub-ssh" GIT_SSH_VARIANT=ssh
SA=git@fake.invalid:x.git
ssh-keygen -q -t ed25519 -N '' -f "$T/k1"; ssh-keygen -q -t ed25519 -N 'phrase' -f "$T/k2"
mkdir -p "$(dirname "$(conf sa)")"; mk sa "$K/project.md" viakey
printf 'default = %s\n[storage %s]\nssh_key = %s\n' "$SA" "$SA" "$T/k1" > "$(conf sa)"
on sa sync --quiet; ok "ssh_key: syncs" $? 0
ok "ssh_key: reached the storage" "$(git -C "$A1/x.git" show main:$K/project.md)" viakey
case "$(cat "$T/ssh.log")" in *"-i $T/k1 -o IdentitiesOnly=yes"*) r=y ;; *) r=n ;; esac; ok "ssh_key: passed alone" $r y
case "$(on sa sync check)" in *"read: ok"*"write: ok"*) r=y ;; *) r=n ;; esac; ok "check: read and write ok" $r y
before=$(git -C "$A1/x.git" rev-parse main); on sa sync check >/dev/null; ok "check: changes nothing" "$(git -C "$A1/x.git" rev-parse main)" "$before"
touch "$T/ro"; out=$(on sa sync check); rc=$?; rm "$T/ro"
case "$out" in *"read: ok"*"write: access denied"*) r=y ;; *) r="$out" ;; esac; ok "check: finds a read-only key" "$r" y; ok "check: read-only is a failure" $rc 1
touch "$T/deny"; out=$(on sa sync check); rm "$T/deny"
case "$out" in *"read: access denied"*"rejected this key"*) r=y ;; *) r="$out" ;; esac; ok "check: rejected key" "$r" y
touch "$T/deny"; printf 'default = %s\n[storage %s]\nssh_key = %s\n' "$SA" "$SA" "$T/k2" > "$(conf sa)"; out=$(on sa sync check); rm "$T/deny"
case "$out" in *"has a passphrase"*) r=y ;; *) r="$out" ;; esac; ok "check: explains a passphrase" "$r" y
touch "$T/hostkey"; out=$(on sa sync check); rm "$T/hostkey"
case "$out" in *"host key not trusted"*) r=y ;; *) r="$out" ;; esac; ok "check: host key" "$r" y
touch "$T/deny"; printf 'default = %s\n' "$SA" > "$(conf sa)"; on sa sync --quiet 2>/dev/null; rm "$T/deny"
case "$(on sa sync status)" in *"fail (access denied)"*) r=y ;; *) r=n ;; esac; ok "status names the reason" $r y
python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind('$T/ag.sock')"
: > "$T/ssh.log"; printf 'default = %s\n[storage %s]\nssh_agent = %s\n' "$SA" "$SA" "$T/ag.sock" > "$(conf sa)"
SSH_AUTH_SOCK= on sa sync --quiet; ok "ssh_agent: syncs" $? 0
case "$(cat "$T/ssh.log")" in *"SOCK=$T/ag.sock"*) r=y ;; *) r=n ;; esac; ok "ssh_agent: socket reaches ssh" $r y
printf 'default = %s\n[storage %s]\nssh_agent = %s/nope\n' "$SA" "$SA" "$T" > "$(conf sa)"
case "$(on sa sync check)" in *"agent socket is not running"*) r=y ;; *) r=n ;; esac; ok "check: dead agent" $r y
printf 'default = %s\n[storage %s]\nssh_key = %s/nope\n' "$SA" "$SA" "$T" > "$(conf sa)"
case "$(on sa sync check)" in *"key file is missing"*) r=y ;; *) r=n ;; esac; ok "check: missing key" $r y
mkdir -p "$T/sb" "$(dirname "$(conf sb)")"; mk sb routing.conf "default = $SA
[storage $SA]
ssh_key = $T/k1"
printf 'default = %s\n' "$SA" > "$(conf sb)"; : > "$T/ssh.log"
out=$(on sb sync --quiet 2>&1); case "$out" in *"read only from"*) r=y ;; *) r=n ;; esac; ok "[storage] ignored in routing.conf" $r y
case "$(cat "$T/ssh.log")" in *"-i "*) r=y ;; *) r=n ;; esac; ok "that key isn't used" $r n
unset GIT_SSH_COMMAND GIT_SSH_VARIANT

# --- access: https with a secret, through a real smart-http server ---
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
TOK="tok-$(printf 'Fake%.0s' 1 2 3)-value"; H=$T/httproot; mkdir -p "$H"; git init -q --bare -b main "$H/m.git"
cat > "$T/bin/srv.py" <<'X'
import base64,http.server,os,subprocess,sys
root,token,portfile=sys.argv[1:4]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def go(self):
        a=self.headers.get('Authorization','')
        if a!='Basic '+base64.b64encode(('oauth2:'+token).encode()).decode():
            self.send_response(401); self.send_header('WWW-Authenticate','Basic realm="x"'); self.send_header('Content-Length','0'); self.end_headers(); return
        n=int(self.headers.get('Content-Length',0) or 0); body=self.rfile.read(n)
        path,_,q=self.path.partition('?')
        e=dict(os.environ,GIT_PROJECT_ROOT=root,GIT_HTTP_EXPORT_ALL='1',PATH_INFO=path,QUERY_STRING=q,REQUEST_METHOD=self.command,REMOTE_USER='oauth2',CONTENT_TYPE=self.headers.get('Content-Type',''),CONTENT_LENGTH=str(n),HTTP_CONTENT_ENCODING=self.headers.get('Content-Encoding',''))
        out=subprocess.run(['git','http-backend'],input=body,env=e,capture_output=True).stdout
        head,_,data=out.partition(b'\r\n\r\n'); code=200; hs=[]
        for l in head.decode().split('\r\n'):
            k,_,v=l.partition(': ')
            if k=='Status': code=int(v.split()[0])
            elif k: hs.append((k,v))
        self.send_response(code)
        for k,v in hs: self.send_header(k,v)
        self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    do_GET=do_POST=go
s=http.server.HTTPServer(('127.0.0.1',0),H); open(portfile,'w').write(str(s.server_port)); s.serve_forever()
X
python3 "$T/bin/srv.py" "$H" "$TOK" "$T/port" >/dev/null 2>&1 & HTTP_PID=$!
for _ in $(seq 1 50); do [[ -s "$T/port" ]] && break; sleep 0.1; done
HA="http://127.0.0.1:$(cat "$T/port")/m.git"
mkdir -p "$T/ha" "$(dirname "$(conf ha)")"; mk ha "$K/project.md" viatoken
printf 'default = %s\n' "$HA" > "$(conf ha)"
out=$(on ha sync check); case "$out" in *"read: access denied"*"no credentials"*) r=y ;; *) r="$out" ;; esac; ok "https: no credentials explained" "$r" y
printf 'default = %s\n[storage %s]\nusername = oauth2\npassword = %s\n' "$HA" "$HA" "$TOK" > "$(conf ha)"
out=$(on ha sync 2>&1); rc=$?; ok "https: literal password refused" $rc 1
case "$out" in *"$TOK"*) r=leak ;; *) r=clean ;; esac; ok "https: refusal hides it" $r clean
printf 'default = %s\n[storage %s]\nusername = oauth2\npassword = secret://mem\n' "$HA" "$HA" > "$(conf ha)"
case "$(on ha sync check)" in *"secret mem is missing"*) r=y ;; *) r=n ;; esac; ok "https: missing secret explained" $r y
printf '%s' "wrong" | on ha secret put mem >/dev/null
out=$(on ha sync check); case "$out" in *"read: access denied"*"rejected the login"*) r=y ;; *) r="$out" ;; esac; ok "https: wrong secret explained" "$r" y
printf '%s' "$TOK" | on ha secret put mem >/dev/null
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/argv.log"\nexec %s "$@"\n' "$T" "$(command -v git)" > "$T/bin/git"; chmod +x "$T/bin/git"
out=$(PATH="$T/bin:$PATH" on ha sync 2>&1); rc=$?; ok "https: syncs with the secret" $rc 0
ok "https: reached the storage" "$(git -C "$H/m.git" show "$(git -C "$H/m.git" for-each-ref --format='%(refname)' | head -1):$K/project.md")" viatoken
out2=$(on ha sync check); case "$out2" in *"read: ok"*"write: ok"*) r=y ;; *) r="$out2" ;; esac; ok "https: check ok" "$r" y
case "$out$out2" in *"$TOK"*) r=leak ;; *) r=clean ;; esac; ok "secret not in output" $r clean
case "$(cat "$T/argv.log")" in *"$TOK"*) r=leak ;; *) r=clean ;; esac; ok "secret not in git arguments" $r clean
ok "secret not in clone or state" "$(grep -rl -- "$TOK" "$T/ha/.local/state" "$T/ha/.config" "$(data ha)" 2>/dev/null | wc -l | tr -d ' ')" 0
case "$(git -C "$(ls -d "$T/ha/.local/state/memory-3layer/stores/"*/ | head -1)" remote get-url origin)" in "$HA") r=y ;; *) r=n ;; esac; ok "clone url stays clean" $r y

# a storage's own README isn't memory, so it isn't "routed elsewhere"
mkdir -p "$T/ra" "$T/rb"; RS=$(bare readme); git clone -q "$RS" "$T/rc" 2>/dev/null; echo hi > "$T/rc/README.md"; git -C "$T/rc" add -A 2>/dev/null; git -C "$T/rc" -c user.name=t -c user.email=t@t commit -qm i; git -C "$T/rc" push -q origin HEAD:main
mk ra identity/IDENTITY.md me; on ra sync init "$RS" >/dev/null; on ra sync --quiet
case "$(on ra sync status)" in *"routed elsewhere"*) r=y ;; *) r=n ;; esac; ok "status ignores a README" $r n
ok "README stays out of memory" "$(exists ra README.md)" 1

# --- pull mode, lock, hooks ---
mkdir -p "$T/o"; Q=$(bare pull)
mk o "$K/project.md" p1; on o sync init "$Q" >/dev/null; on o sync --quiet
mk o "$K/project.md" p2; on o sync --pull --quiet
ok "pull mode doesn't push" "$(git -C "$Q" show main:$K/project.md)" p1
on o sync --quiet; ok "next sync pushes" "$(git -C "$Q" show main:$K/project.md)" p2
L2=$(ls -d "$T/o/.local/state/memory-3layer/stores/"*/ | head -1); mkdir "${L2%/}.lock"
case "$(on o sync)" in *"another sync"*) r=y ;; *) r=n ;; esac; ok "a second sync steps aside" $r y
rmdir "${L2%/}.lock"
mkdir -p "$T/p"; V=$(bare hook)
mk p "$K/project.md" h1
mkdir -p "$T/rp"; git -C "$T/rp" init -q; git -C "$T/rp" remote add origin git@github.com:o/r.git
on p sync init "$V" >/dev/null
out=$(cd "$T/rp" && echo '{"hook_event_name":"SessionStart"}' | HOME="$T/p" bash "$REPO/hooks/session-start.sh")
ok "session hook still answers in JSON" "$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])')" SessionStart
(cd "$T/rp" && HOME="$T/p" bash "$REPO/hooks/session-end.sh" </dev/null)
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do git -C "$V" cat-file -e main:$K/project.md 2>/dev/null && break; sleep 0.3; done
ok "session end pushes in the background" "$(has "$V" "$K/project.md")" 0

# --- a session writes while a sync runs ---
# A git shim makes the write land between copy_out and copy_in.
RS=$(bare race); RK=projects/github.com/o/race
mkdir -p "$T/ra" "$T/rb" "$T/shim"; for m in ra rb; do mkdir -p "$(dirname "$(conf $m)")"; printf 'default = %s\n' "$RS" > "$(conf $m)"; done
REAL_GIT=$(command -v git)
{
  printf '#!/usr/bin/env bash\n'
  printf 'if [[ " $* " == *" merge "* && -n "${RACE_FILE:-}" && ! -e "$RACE_FILE.done" ]]; then\n'
  printf '  : > "$RACE_FILE.done"; printf "%%s\\n" "$RACE_TEXT" >> "$RACE_FILE"\nfi\n'
  printf 'exec "%s" "$@"\n' "$REAL_GIT"
} > "$T/shim/git"
chmod +x "$T/shim/git"
raced() { RACE_FILE="$(data ra)/$1" RACE_TEXT="$2" PATH="$T/shim:$PATH" on ra sync --quiet; rm -f "$(data ra)/$1.done"; }
mk ra "$RK/SESSION.md" "one"
on ra sync --quiet
raced "$RK/SESSION.md" "edit during sync"
ok "race: a write during sync survives" "$(grep -c 'edit during sync' "$(data ra)/$RK/SESSION.md")" 1
on ra sync --quiet; on rb sync --quiet
ok "race: it reaches the other machine" "$(grep -c 'edit during sync' "$(data rb)/$RK/SESSION.md")" 1
printf 'from b\n' > "$(data rb)/$RK/SESSION.md"; on rb sync --quiet
raced "$RK/SESSION.md" "local during merge"
ok "race: local version keeps the name" "$(grep -c 'local during merge' "$(data ra)/$RK/SESSION.md")" 1
ok "race: remote version kept beside it" "$(cat "$(data ra)/$RK/superseded/conflict-remote/SESSION.md")" "from b"

echo; [[ $fail -eq 0 ]] && echo "all $n passed" || echo "FAILED"
exit $fail
