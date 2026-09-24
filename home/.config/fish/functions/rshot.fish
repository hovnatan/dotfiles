# rshot [host]: send the image on the Mac clipboard to a remote machine, so a
# Claude Code session running there (over ssh, in tmux) can read it. Claude's
# Ctrl+V takes images from the clipboard of the machine it runs on, and a
# headless box has none; a file path in the prompt works instead.
#
#   Mac clipboard image (e.g. cmd+ctrl+shift+4)
#        |  AppleScript writes it out as PNG
#        v
#   <host>:~/screenshots/<UTC timestamp>.png   (files older than 7 days go)
#        |
#        v
#   the remote path replaces the clipboard: cmd+v it into the remote prompt
#
# The default host is the universal variable RSHOT_HOST, set once per machine
# (`set -U RSHOT_HOST <host>`). Universal variables live in fish_variables,
# which is gitignored, so host names stay out of this public repo.
function rshot --description 'Copy the clipboard image to a remote host; clipboard gets its path'
    set -l host $RSHOT_HOST
    set -q argv[1]; and set host $argv[1]
    if test -z "$host"
        echo "rshot: no host; pass one (rshot <host>) or set a default once: set -U RSHOT_HOST <host>" >&2
        return 1
    end
    if test (uname) != Darwin
        echo "rshot: macOS only (reads the Mac clipboard)" >&2
        return 1
    end

    # Clipboard -> local PNG. Fails when the clipboard holds no image, e.g.
    # after copying text: say so rather than sending an empty file.
    set -l tmp (mktemp -t rshot).png
    if not osascript -e 'on run argv' \
            -e 'set f to open for access (POSIX file (item 1 of argv)) with write permission' \
            -e 'try' \
            -e 'write (the clipboard as «class PNGf») to f' \
            -e 'on error' \
            -e 'close access f' \
            -e 'error "no image on the clipboard"' \
            -e 'end try' \
            -e 'close access f' \
            -e 'end run' $tmp 2>/dev/null
        rm -f $tmp
        echo "rshot: no image on the clipboard; take one with cmd+ctrl+shift+4 or copy an image" >&2
        return 1
    end

    # One ssh round trip: store the file, prune old ones, print the absolute
    # path (the remote $HOME is not the Mac's).
    set -l name (date -u +%Y%m%d_%H%M%S).png
    set -l remote_path (ssh $host "mkdir -p ~/screenshots && f=\$HOME/screenshots/$name && cat > \"\$f\" && find ~/screenshots -name '*.png' -mtime +7 -delete && echo \"\$f\"" <$tmp)
    set -l ssh_status $status
    rm -f $tmp
    if test $ssh_status -ne 0; or test -z "$remote_path"
        echo "rshot: copying to $host failed (ssh exit $ssh_status)" >&2
        return 1
    end

    printf '%s' $remote_path | pbcopy
    echo "$host:$remote_path (path on the clipboard)"
end
