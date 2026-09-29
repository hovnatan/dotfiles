# pasteimg [file]: save an image pasted into this terminal as base64, on
# whatever machine the shell runs on. The remote-side counterpart of rshot:
# nothing is sent from the Mac by ssh, the bytes travel through the terminal.
#
#   iTerm2 cmd+v with an image -> "Paste Base64-Encoded Contents"
#        |  typed into this terminal, wrapped at 76 columns, so every line
#        |  stays far below the tty line limit (4095 on Linux, 1024 macOS)
#        v
#   base64 -d -> file   (default ~/screenshots/<UTC timestamp>.png, next to
#        |               rshot's; files there older than 7 days go)
#        |  Ctrl-D once the text stops scrolling ends the input
#        v
#   prints the absolute path, e.g. to hand to Claude Code
#
# A 4K screenshot (215 KB PNG) takes about 15 s to arrive, as iTerm2 types
# it. A timed read that ends by itself does not work here: its clock starts
# before the paste does, so it gives up on an empty input.
function pasteimg --description 'Save an image pasted as base64 (iTerm2 cmd+v) to a file'
    set -l file $argv[1]
    if not set -q argv[1]
        mkdir -p ~/screenshots
        find ~/screenshots -name '*.png' -mtime +7 -delete
        set file ~/screenshots/(date -u +%Y%m%d_%H%M%S).png
    end
    if test -e $file
        echo "pasteimg: $file exists; pass another name" >&2
        return 1
    end

    echo 'pasteimg: cmd+v, choose "Paste Base64-Encoded Contents", then Ctrl-D once it stops' >&2
    if not base64 -d >$file
        rm -f $file
        echo "pasteimg: the paste was not valid base64; nothing saved" >&2
        return 1
    end
    # Ctrl-D before any paste decodes nothing and succeeds: no empty file.
    if not test -s $file
        rm -f $file
        echo "pasteimg: nothing was pasted; nothing saved" >&2
        return 1
    end
    # The decoded bytes must be a PNG (iTerm2 pastes the clipboard's PNG
    # form). macOS base64 -d skips characters outside the alphabet instead of
    # failing, so pasted text would otherwise decode to junk and exit 0.
    set -l magic (head -c 8 $file | od -An -tx1 | string join '' | string replace -a ' ' '')
    if test "$magic" != 89504e470d0a1a0a
        rm -f $file
        echo "pasteimg: the paste did not decode to a PNG; nothing saved" >&2
        return 1
    end
    path resolve $file
end
