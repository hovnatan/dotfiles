#!/usr/bin/env bash
#
# apt_bundle.sh -- bring an Ubuntu box in step with apt/Aptfile, the curated
# list of apt packages and the third-party repositories they come from: what
# `brew bundle` is to the Brewfile. The Aptfile's header has the format.
#
#   apt_bundle.sh check             what the Aptfile lists and the box lacks;
#                                   changes nothing, needs no root
#   apt_bundle.sh install [--yes]   add the repositories and install what is
#                                   missing, through sudo; --yes answers apt
#
#   apt/Aptfile                           apt/keys/<name>.asc
#     repo <name> <uri> ...                        |
#          |                                       |
#          v                                       v
#     /etc/apt/sources.list.d/<name>.sources   /etc/apt/keyrings/<name>.asc
#          check:   compared with what install would write
#          install: written when different, then `apt-get update`
#
#     apt <package>
#          |
#          v
#     dpkg's status of the package
#          check:   reported when not installed
#          install: `apt-get install` of the ones not installed
#
# Packages only: what one needs set up afterwards (the docker group,
# /etc/docker/daemon.json, the fleet policy in claude_tmux_session/AGENTS.md)
# stays a separate step.
#
# Exit status:
#   check     0 in step, 1 drift, 2 an error (a bad Aptfile, not Ubuntu, ...)
#   install   0 in step afterwards, 2 anything else
#
# Only install changes the box, so only it logs:
# ~/.dotfiles/.logs/<UTC>_apt_bundle/events.log (scripts/lib/event_log.sh).

set -euo pipefail

# set -e stops the script with the failed command's own status, which can be
# 1 -- check's "drift". So drift and die exit through finish, and any other
# failed exit is turned into 2 here.
chosen_exit=
finish() {
  chosen_exit=1
  exit "$1"
}
on_exit() {
  local status=$?
  if [ "$status" -eq 0 ] || [ -n "$chosen_exit" ]; then return; fi
  say "apt_bundle.sh: error: stopped on a failed command (status $status), see above" >&2
  exit 2
}
trap on_exit EXIT

# say is a plain line for check and a logged, timestamped one once install
# has started its log.
say() { echo "$*"; }
die() {
  say "apt_bundle.sh: error: $*" >&2
  finish 2
}

# --- arguments ----------------------------------------------------------------

apt_yes=()
case "$*" in
  check | install) action=$1 ;;
  "install --yes")
    action=install
    apt_yes=(--yes)
    ;;
  *) die "usage: apt_bundle.sh check | install [--yes]" ;;
esac
aptfile=$(cd "$(dirname "$0")/.." && pwd)/apt/Aptfile
keys_dir=${aptfile%/*}/keys

# --- the box ------------------------------------------------------------------

# The repositories are Ubuntu's (a Debian box would get packages built for
# another distribution), so anything else is refused rather than guessed at.
# scripts/update.sh asks the same question the same way (is_ubuntu).
[ -r /etc/os-release ] || die "no /etc/os-release: apt_bundle.sh is for Ubuntu boxes"
# shellcheck disable=SC1091  # the box's own file, not part of the repo
os_id=$(. /etc/os-release && echo "${ID:-}")
[ "$os_id" = ubuntu ] || die "this box is '$os_id', not ubuntu: the Aptfile's repositories are Ubuntu's"
# shellcheck disable=SC1091
codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
[ -n "$codename" ] || die "/etc/os-release has no VERSION_CODENAME"
arch=$(dpkg --print-architecture)

sources_dir=/etc/apt/sources.list.d
keyrings_dir=/etc/apt/keyrings

# --- the Aptfile --------------------------------------------------------------

# Read the Aptfile into these, in file order. Every line has to be an entry
# this script knows: one it skipped would be a package silently not installed.
#
#   repo docker https://download.docker.com/linux/ubuntu {codename} stable
#     -> repos=(docker)  repo_uri[docker]=https://...  repo_suite[docker]={codename}
#        repo_components[docker]=stable
#   apt docker-ce
#     -> packages=(docker-ce)
repos=()
declare -A repo_uri=() repo_suite=() repo_components=()
packages=()

parse_aptfile() {
  local line words name n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    read -r -a words <<< "$line"
    if [ "${#words[@]}" -eq 0 ]; then continue; fi
    case ${words[0]} in
      '#'*) ;;
      repo)
        [ "${#words[@]}" -ge 5 ] || die "$aptfile:$n: repo needs <name> <uri> <suite> <component>..., got: $line"
        name=${words[1]}
        [[ $name =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "$aptfile:$n: repo name '$name' is not lower-case letters, digits and dashes"
        [ -z "${repo_uri[$name]:-}" ] || die "$aptfile:$n: repo '$name' is listed twice"
        [[ ${words[2]} == https://* ]] || die "$aptfile:$n: repo '$name': uri '${words[2]}' is not https://"
        [ -f "$keys_dir/$name.asc" ] || die "$aptfile:$n: repo '$name' has no signing key: $keys_dir/$name.asc is missing (the Aptfile's header says how to vendor one)"
        repos+=("$name")
        repo_uri[$name]=${words[2]}
        repo_suite[$name]=${words[3]}
        repo_components[$name]=${words[*]:4}
        ;;
      apt)
        [ "${#words[@]}" -eq 2 ] || die "$aptfile:$n: apt takes one package name, got: $line"
        name=${words[1]}
        [[ $name =~ ^[a-z0-9][a-z0-9.+-]+$ ]] || die "$aptfile:$n: '$name' is not an apt package name"
        # a name holds no space (the check above), so this finds whole names
        [[ " ${packages[*]} " != *" $name "* ]] || die "$aptfile:$n: package '$name' is listed twice"
        packages+=("$name")
        ;;
      *) die "$aptfile:$n: unknown entry '${words[0]}' (an entry is 'repo ...' or 'apt <package>'): $line" ;;
    esac
  done < "$aptfile"
}

# --- comparing the box with it ------------------------------------------------

# The .sources file of a repo, as install writes it (deb822, apt's current
# format). Architectures keeps apt from asking the repository for a foreign
# architecture the box has enabled (i386 on amd64), which it would not have.
render_sources() {
  local name=$1
  cat << EOF
# Written by ~/.dotfiles/scripts/apt_bundle.sh from apt/Aptfile: change that
# and run \`apt_bundle.sh install\`, not this file.
Types: deb
URIs: ${repo_uri[$name]}
Suites: ${repo_suite[$name]//\{codename\}/$codename}
Components: ${repo_components[$name]}
Architectures: $arch
Signed-By: $keyrings_dir/$name.asc
EOF
}

# One line for each way the box's copy of a repo differs from the Aptfile's;
# nothing when it is in step.
repo_drift() {
  local name=$1
  local sources=$sources_dir/$name.sources key=$keyrings_dir/$name.asc
  if [ ! -e "$sources" ]; then
    echo "repo $name: not configured ($sources is missing)"
  elif ! render_sources "$name" | cmp -s - "$sources"; then
    echo "repo $name: $sources differs from the Aptfile's entry"
  fi
  if [ ! -e "$key" ]; then
    echo "repo $name: signing key $key is missing"
  elif ! cmp -s "$keys_dir/$name.asc" "$key"; then
    echo "repo $name: $key differs from $keys_dir/$name.asc"
  fi
}

# One line for each other apt source file that lists a repo's uri on a line
# that is not a comment: an entry somebody made by hand or an installer
# script left (docker.list from the retired scripts/install_docker.sh). With
# one repository in two files under two keys, every `apt-get update` fails.
rival_report() {
  local name file
  for name in "${repos[@]}"; do
    for file in /etc/apt/sources.list "$sources_dir"/*.list "$sources_dir"/*.sources; do
      # also drops a glob that matched nothing
      if [ ! -f "$file" ] || [ "$file" = "$sources_dir/$name.sources" ]; then continue; fi
      if awk -v uri="${repo_uri[$name]}" \
        '!/^[[:space:]]*#/ && index($0, uri) { found = 1 } END { exit !found }' "$file"; then
        echo "repo $name: $file lists ${repo_uri[$name]} too, and apt takes a repository from one file only; look at it, then: sudo rm $file"
      fi
    done
  done
}

# The Aptfile's packages that are not installed, one name per line.
missing_packages() {
  local package status
  for package in "${packages[@]}"; do
    # dpkg-query fails on a name it has never seen, which is "not installed" too
    status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2> /dev/null || true)
    [ "$status" = installed ] || echo "$package"
  done
}

# Every way the box is out of step with the Aptfile, one line each.
drift_report() {
  local name missing
  for name in "${repos[@]}"; do
    repo_drift "$name"
  done
  rival_report
  mapfile -t missing < <(missing_packages)
  [ "${#missing[@]}" -eq 0 ] || printf 'apt %s: not installed\n' "${missing[@]}"
}

in_step_line() {
  echo "in step with $aptfile (packages: ${#packages[@]}, repositories: ${#repos[@]})"
}

# --- check --------------------------------------------------------------------

check() {
  local drift
  drift=$(drift_report)
  if [ -z "$drift" ]; then
    in_step_line
    return
  fi
  echo "$drift"
  echo "to bring the box in step: ~/.dotfiles/scripts/apt_bundle.sh install"
  finish 1
}

# --- install ------------------------------------------------------------------

# Put a repo's key and .sources file in place. The file is rendered as the
# user and handed to root on stdin, so nothing but install(1) runs with sudo.
write_repo() {
  local name=$1
  "${as_root[@]}" install -d -m 0755 "$keyrings_dir"
  "${as_root[@]}" install -m 0644 "$keys_dir/$name.asc" "$keyrings_dir/$name.asc"
  render_sources "$name" | "${as_root[@]}" install -m 0644 /dev/stdin "$sources_dir/$name.sources"
  say "repo $name: wrote $sources_dir/$name.sources and $keyrings_dir/$name.asc"
}

install_all() {
  # shellcheck source=scripts/lib/event_log.sh
  . "$(dirname "$0")/lib/event_log.sh"
  event_log_start apt_bundle
  say() { log "$*"; }

  if [ -z "$(drift_report)" ]; then
    say "nothing to do: $(in_step_line)"
    return
  fi

  as_root=()
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo > /dev/null || die "not root and no sudo on PATH: run as root, or install sudo"
    as_root=(sudo)
  fi

  # Refused before anything is written, so the box's apt stays usable.
  local rivals
  rivals=$(rival_report)
  [ -z "$rivals" ] || die "${rivals//$'\n'/; }"

  # Every repo is https (parse_aptfile), which apt cannot verify on a box
  # without CA certificates: a minimal image, not a server install.
  if [ "${#repos[@]}" -gt 0 ] && [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    die "no CA certificates on this box (/etc/ssl/certs/ca-certificates.crt), so apt cannot verify an https repository; first: sudo apt-get install ca-certificates"
  fi

  local name missing
  for name in "${repos[@]}"; do
    [ -z "$(repo_drift "$name")" ] || write_repo "$name"
  done
  mapfile -t missing < <(missing_packages)

  # Also when only a package is missing: the box's lists may predate it.
  say "apt-get update"
  "${as_root[@]}" apt-get update ||
    die "apt-get update failed (its message above says why); the Aptfile's repositories are already in place under $sources_dir: fix the cause and rerun"
  if [ "${#missing[@]}" -gt 0 ]; then
    say "apt-get install ${missing[*]}"
    "${as_root[@]}" apt-get install "${apt_yes[@]}" -- "${missing[@]}" ||
      die "apt-get install did not go through (declined at its prompt, or its error above); rerun when ready"
  fi

  # Look again rather than take apt-get's exit status for it: this is what
  # the run was for.
  local drift
  drift=$(drift_report)
  [ -z "$drift" ] || die "still out of step after the install: ${drift//$'\n'/; }"
  say "$(in_step_line)"
}

parse_aptfile
case $action in
  check) check ;;
  install) install_all ;;
esac
