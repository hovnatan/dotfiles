# LC_CLIENT_TZ: the Mac's time zone, for the machines it ssh's into. macOS
# ssh sends LC_* (SendEnv in /etc/ssh/ssh_config.d/100-macos.conf) and the
# VM's sshd accepts it, so a tmux client attached over ssh carries it, and
# the tmux bar there shows this zone, not the server's
# (home/.config/tmux/client-clock.sh). macOS keeps its zone as the
# /etc/localtime link, not in TZ:
#
#   /etc/localtime -> /var/db/timezone/zoneinfo/Asia/Yerevan  ->  Asia/Yerevan
#
# Every fish, not only interactive ones: an ssh from a script carries it too.
# Mac only: on Linux this fish is usually the far end of an ssh, and must pass
# on the zone that came with it rather than put the VM's (UTC) in its place.
# Read at fish start, so a shell opened before travel sends the old zone
# until a new one is opened.
if test (uname) = Darwin
    set -l link (readlink /etc/localtime)
    set -l zone (string replace -rf '^.*/zoneinfo/' '' -- $link)
    if test -n "$zone"
        set -gx LC_CLIENT_TZ $zone
    else
        echo "client_tz.fish: /etc/localtime links to '$link', not into a zoneinfo directory;" \
            "LC_CLIENT_TZ not set, so tmux over ssh shows the server's time (System Settings > Date & Time)" >&2
    end
end
