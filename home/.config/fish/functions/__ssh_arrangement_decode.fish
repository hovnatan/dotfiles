# __ssh_arrangement_decode <log name> <variable> <value>: print a value a saved
# iTerm2 ssh arrangement sent (scripts/lib/iterm2_ssh_arrangement.py,
# send_line: %-encoded, "/" too, ":" kept), decoded, for the login-shell ends
# (tmux_attach_requested, login_dir_requested). A value it could not have
# written is refused, on stderr and in that event log, status 1:
#   claude:api%2Fdocs       -> claude:api/docs
#   %2Fhome%2Fit%27s%20here -> /home/it's here
#   %zz, a/b (a raw "/")    -> refused: not %-encoded as the arrangement writes it
#   %2Fa%0Ab                -> refused: a newline, which the save refuses too,
#                              and which the caller's (...) would split at
function __ssh_arrangement_decode
    set -l log $argv[1]
    set -l variable $argv[2]
    set -l value $argv[3]
    set -l why
    if not string match -qr '^(?:[A-Za-z0-9_.~:-]|%[0-9A-Fa-f]{2})*$' -- $value
        set why "not %-encoded as the arrangement writes it"
    else if string match -qir '%0a' -- $value
        set why "a newline (%0A), which the arrangement never saves"
    end
    if test -n "$why"
        set -l shown (string escape -- $value)
        __ssh_arrangement_note $log "$variable=$shown refused: $why"
        echo "$log: $variable is $shown: $why" >&2
        return 1
    end
    string unescape --style=url -- $value
end
