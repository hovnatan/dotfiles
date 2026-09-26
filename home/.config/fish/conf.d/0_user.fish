# ctrl-d: with text on the line, move forward a word (which also accepts one
# word of an autosuggestion). On an empty line, exit only on a second press
# within ~2s, so a stray ctrl-d (say, one meant for a REPL that already
# ended) does not close the shell. date +%s is whole seconds, so the window
# is 2-3s.
#   empty line, ctrl-d            -> "Press ctrl-d again to exit"
#   empty line, ctrl-d ctrl-d     -> exit
#   empty line, ctrl-d ... ctrl-d -> hint again (window expired)
function forward-word-or-exit
    # "$(...)" joins a multi-line command line into one string for test
    if test -n "$(commandline)"
        commandline -f forward-word
        return
    end

    set -l now (date +%s)
    if set -q __ctrl_d_armed_at; and test (math $now - $__ctrl_d_armed_at) -le 2
        exit
    end
    set -g __ctrl_d_armed_at $now
    echo
    echo "Press ctrl-d again to exit"
    commandline -f repaint
end

# ctrl-p/ctrl-n: fish's up-or-search/down-or-search, but the history search
# matches only at the start of the line. With "git pu" typed:
#   up-or-search          -> "echo git pu inside", "git pull --rebase", ...
#   up-or-prefix-search   -> "git pull --rebase", "git push ...", never "echo ..."
# The rest is as upstream (fish 4.9 embedded functions): an open completion
# pager moves its selection, and in a multi-line command only the top/bottom
# line starts a search, other lines move the cursor.
function up-or-prefix-search --description 'Prefix-search history back, or move cursor up 1 line'
    if commandline --search-mode
        commandline -f history-prefix-search-backward
    else if commandline --paging-mode
        commandline -f up-line
    else if test (commandline -L) -eq 1
        commandline -f history-prefix-search-backward
    else
        commandline -f up-line
    end
end

function down-or-prefix-search --description 'Prefix-search history forward, or move cursor down 1 line'
    if commandline --search-mode
        commandline -f history-prefix-search-forward
    else if commandline --paging-mode
        commandline -f down-line
    else if test (commandline -L) -eq (count (commandline))
        commandline -f history-prefix-search-forward
    else
        commandline -f down-line
    end
end

function hybrid_bindings --description "Vi-style bindings that inherit emacs-style bindings in all modes"
    for mode in default insert visual
        fish_default_key_bindings -M $mode
    end
    fish_vi_key_bindings --no-erase
    # History up/down in insert mode too: fish's vi preset binds insert-mode
    # ctrl-n to accept-autosuggestion, so after ctrl-p walked back, ctrl-n
    # accepted the grey suggestion (or did nothing) instead of coming forward.
    # Prefix-only search; the arrow keys keep fish's substring search.
    bind \cp up-or-prefix-search
    bind \cn down-or-prefix-search
    bind -M insert \cp up-or-prefix-search
    bind -M insert \cn down-or-prefix-search
    bind \cd forward-word-or-exit
    bind -M insert \cd forward-word-or-exit
#    bind -M insert -m default jk backward-char force-repaint
#    bind -m insert \e force-repaint
end

set -g fish_key_bindings hybrid_bindings
