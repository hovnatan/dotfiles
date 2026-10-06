#!/usr/bin/env bash
# check.sh covers: scripts/apt_bundle.sh scripts/install_docker.sh scripts/lib/* apt/*
# check.sh runs-on: Linux
#
# apt_bundle_test.sh -- end-to-end checks for scripts/apt_bundle.sh, which
# brings an Ubuntu box in step with apt/Aptfile. Runs the script for real,
# against the real Aptfile, in a throwaway ubuntu:24.04 container: as a user
# with sudo, the way it is run on a box. Needs docker with a running daemon
# and the network (Ubuntu's archive, Docker's repository); about half a
# minute once the image is pulled, most of it apt installing docker-ce.
#
#   host                                  container (ubuntu:24.04, as root)
#   apt_bundle_test.sh  --docker run-->   apt_bundle_test.sh --in-container
#     the repo mounted read-only            copies apt/ and scripts/ into
#     at /repo                              ~ubuntu/.dotfiles, then runs
#                                           apt_bundle.sh as ubuntu
#
#   arguments     no command, an unknown one, check --yes: status 2
#   bad Aptfile   an unknown entry, a repo without its key, a short repo
#                 line, an http uri, a bad or repeated package: status 2,
#                 the line named (the copy's Aptfile is overwritten for
#                 each, then put back)
#   fresh box     check: status 1, the repo and every package reported
#   no CA certs   with the CA bundle moved aside, install refuses, names
#                 ca-certificates, writes nothing
#   rival entry   a docker.list naming the same repository: check reports
#                 it, install refuses and writes nothing; a commented-out
#                 line is no rival
#   install       --yes: status 0, docker runs, the .sources file names the
#                 box's codename and architecture, check is 0, the run is
#                 in the event log
#   again         a second install does nothing, runs no apt-get
#   drift         an edited .sources file, a replaced key and a removed
#                 package are each reported by check and repaired by install
#
# Exit 0 = all passed; a failed check prints the output it looked at.

set -uo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# --- host: hand over to the container -------------------------------------------

if [ "${1:-}" != --in-container ]; then
  command -v docker >/dev/null || {
    echo "apt_bundle_test.sh: docker not on PATH" >&2
    exit 1
  }
  docker info >/dev/null 2>&1 || {
    echo "apt_bundle_test.sh: no docker daemon answers (docker info); start it" >&2
    exit 1
  }
  log "running in ubuntu:24.04"
  exec docker run --rm -v "$REPO:/repo:ro" ubuntu:24.04 \
    bash /repo/scripts/tests/apt_bundle_test.sh --in-container
fi

# --- container ------------------------------------------------------------------

failures=0
pass() { log "PASS $*"; }
fail() {
  log "FAIL $*"
  sed 's/^/    | /' "$OUT"
  failures=$((failures + 1))
}

U=/home/ubuntu
BUNDLE="$U/.dotfiles/scripts/apt_bundle.sh"
OUT=/tmp/out
SOURCES=/etc/apt/sources.list.d/docker.sources
KEY=/etc/apt/keyrings/docker.asc

# bundle <args>: apt_bundle.sh as the ubuntu user; output in $OUT, status in $rc
bundle() {
  # shellcheck disable=SC2024  # $OUT is root's on purpose; only the script runs as ubuntu
  sudo -H -u ubuntu "$BUNDLE" "$@" >"$OUT" 2>&1
  rc=$?
}
# expect <status> <name>: the last bundle exited with it
expect() {
  if [ "$rc" -eq "$1" ]; then pass "$2: status $1"; else fail "$2: status $rc, expected $1"; fi
}
# says <text> <name>: the last bundle's output has the text
says() {
  if grep -qF -- "$1" "$OUT"; then pass "$2"; else fail "$2: output lacks '$1'"; fi
}
says_not() {
  if grep -qF -- "$1" "$OUT"; then fail "$2: output has '$1'"; else pass "$2"; fi
}
# aptfile <line>...: the copy's Aptfile becomes those lines
aptfile() { printf '%s\n' "$@" >"$U/.dotfiles/apt/Aptfile"; }

# The image's own user gets passwordless sudo and a copy of the repo's apt/
# and scripts/ where a clone would be.
log "setup: sudo, ca-certificates, the ubuntu user, ~/.dotfiles"
{
  apt-get update -q && apt-get install -y -q sudo ca-certificates
} >"$OUT" 2>&1 || {
  fail "setup: apt-get install sudo ca-certificates"
  exit 1
}
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/ubuntu
mkdir -p "$U/.dotfiles"
cp -r /repo/apt /repo/scripts "$U/.dotfiles/"
chown -R ubuntu:ubuntu "$U/.dotfiles"
n_packages=$(grep -c '^apt ' "$U/.dotfiles/apt/Aptfile")

# --- arguments ------------------------------------------------------------------

bundle
expect 2 "no command"
bundle frobnicate
expect 2 "unknown command"
bundle check --yes
expect 2 "check --yes"

# --- bad Aptfile ----------------------------------------------------------------

aptfile '# a comment' '' 'brew docker'
bundle check
expect 2 "unknown entry"
says "Aptfile:3: unknown entry 'brew'" "unknown entry: line named"

aptfile 'repo nokey https://example.com/apt stable main'
bundle check
expect 2 "repo without a key"
says "keys/nokey.asc is missing" "repo without a key: key file named"

aptfile 'repo docker https://download.docker.com/linux/ubuntu'
bundle check
expect 2 "short repo line"

aptfile 'repo docker http://download.docker.com/linux/ubuntu noble stable'
bundle check
expect 2 "http uri"
says "is not https://" "http uri: said so"

aptfile 'apt Docker_CE'
bundle check
expect 2 "bad package name"

aptfile 'apt docker-ce' 'apt docker-ce'
bundle check
expect 2 "package listed twice"
says "Aptfile:2: package 'docker-ce' is listed twice" "package listed twice: line named"

cp /repo/apt/Aptfile "$U/.dotfiles/apt/Aptfile"

# --- fresh box ------------------------------------------------------------------

bundle check
expect 1 "fresh box: check"
says "repo docker: not configured" "fresh box: repo reported"
says "repo docker: signing key $KEY is missing" "fresh box: key reported"
n=$(grep -c '^apt .*: not installed$' "$OUT")
if [ "$n" -eq "$n_packages" ]; then
  pass "fresh box: all $n_packages packages reported"
else
  fail "fresh box: $n packages reported, the Aptfile lists $n_packages"
fi

# --- no CA certs ----------------------------------------------------------------

CA=/etc/ssl/certs/ca-certificates.crt
mv "$CA" "$CA.aside"
bundle install --yes
expect 2 "no CA certs: install"
says "sudo apt-get install ca-certificates" "no CA certs: the fix is named"
if [ ! -e "$SOURCES" ] && [ ! -e "$KEY" ]; then
  pass "no CA certs: nothing written"
else
  fail "no CA certs: $SOURCES or $KEY was written"
fi
mv "$CA.aside" "$CA"

# --- rival entry ----------------------------------------------------------------

# What the retired scripts/install_docker.sh left behind.
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" \
  >/etc/apt/sources.list.d/docker.list
bundle check
expect 1 "rival entry: check"
says "/etc/apt/sources.list.d/docker.list lists https://download.docker.com/linux/ubuntu too" "rival entry: check names the file"
bundle install --yes
expect 2 "rival entry: install"
says "sudo rm /etc/apt/sources.list.d/docker.list" "rival entry: install names the fix"
if [ ! -e "$SOURCES" ]; then pass "rival entry: nothing written"; else fail "rival entry: $SOURCES was written"; fi

sed -i 's/^/# /' /etc/apt/sources.list.d/docker.list
bundle check
says_not "docker.list" "rival entry: a commented-out line is no rival"
rm /etc/apt/sources.list.d/docker.list

# --- install --------------------------------------------------------------------

log "install --yes (the slow step: apt downloads docker-ce)"
bundle install --yes
expect 0 "install"
says "apt-get install docker-ce" "install: says what it installs"
if docker --version >/dev/null 2>&1; then pass "install: docker runs"; else fail "install: docker --version failed"; fi

cp "$SOURCES" "$OUT"
says "Suites: noble" "install: .sources names the box's codename"
says "Architectures: $(dpkg --print-architecture)" "install: .sources names the box's architecture"
says "Signed-By: $KEY" "install: .sources names the key"
if cmp -s "$KEY" "$U/.dotfiles/apt/keys/docker.asc"; then pass "install: key is the vendored one"; else fail "install: $KEY differs from the vendored key"; fi

bundle check
expect 0 "install: check afterwards"
says "in step with" "install: check says in step"

cat "$U"/.dotfiles/.logs/*_apt_bundle/events.log >"$OUT" 2>&1
says "repo docker: wrote $SOURCES" "install: event log has the repo"
says "apt-get install docker-ce" "install: event log has the install"

# --- again ----------------------------------------------------------------------

bundle install --yes
expect 0 "again: install"
says "nothing to do" "again: says nothing to do"
says_not "apt-get update" "again: no apt-get run"

# --- drift ----------------------------------------------------------------------

echo '# edited by hand' >>"$SOURCES"
echo 'not a key' >"$KEY"
apt-get remove -y -q docker-compose-plugin >"$OUT" 2>&1 || {
  fail "apt-get remove docker-compose-plugin"
  exit 1
}
bundle check
expect 1 "drift: check"
says "$SOURCES differs from the Aptfile's entry" "drift: edited .sources reported"
says "$KEY differs from" "drift: replaced key reported"
says "apt docker-compose-plugin: not installed" "drift: removed package reported"
n=$(grep -c '^apt .*: not installed$' "$OUT")
if [ "$n" -eq 1 ]; then pass "drift: only the removed package reported"; else fail "drift: $n packages reported, expected 1"; fi

bundle install --yes
expect 0 "drift: install repairs"
says_not "apt-get install docker-ce" "drift: installs only what is missing"
bundle check
expect 0 "drift: check afterwards"

if [ "$failures" -eq 0 ]; then
  log "all passed"
else
  log "$failures failed"
  exit 1
fi
