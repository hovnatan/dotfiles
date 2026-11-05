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
    # ctrl-d never closes the shell: fish's preset exits on an empty line, and a
    # stray press meant for a REPL that already ended lands here. With text on
    # the line it moves forward a word, which also accepts one word of an
    # autosuggestion; on an empty line it does nothing. `exit` closes the shell.
    bind \cd forward-word
    bind -M insert \cd forward-word
    bind -M visual \cd forward-word
    #    bind -M insert -m default jk backward-char force-repaint
    #    bind -m insert \e force-repaint
end

set -g fish_key_bindings hybrid_bindings
