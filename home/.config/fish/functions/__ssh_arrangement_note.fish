# __ssh_arrangement_note <log name> <message>: one line in that event log,
# for the login-shell ends of a restored iTerm2 ssh arrangement
# (tmux_attach_requested, login_dir_requested), through the repo's
# scripts/lib/event_log.sh, found from this file's real path
# (~/.config/fish is a link into the checkout). Fails, saying so, when the
# line could not be written: that log is what tells a restore whose request
# was never received from one that was refused.
#   __ssh_arrangement_note login_dir_requested "cd /home/me/d"
#   -> ~/.dotfiles/.logs/<UTC day>_login_dir_requested/events.log
function __ssh_arrangement_note
    set -l lib (path resolve (path dirname (functions --details __ssh_arrangement_note))/../../../../scripts/lib/event_log.sh)
    bash -c '. "$1" && shift && event_log_note "$@"' _ $lib $argv[1] "$argv[2..]"
    and return 0
    echo "$argv[1]: could not write the event log through $lib" >&2
    return 1
end
