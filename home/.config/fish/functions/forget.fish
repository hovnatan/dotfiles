# forget (ctrl-g, config.fish): drop the command on the command line from
# history, after a Y/n prompt. Two histories hold it, so both lose it:
#
#   fish_history  autosuggestions, ctrl-p/Up   history delete --exact
#   atuin         ctrl-r                       atuin search --delete
#
# atuin has no exact-match delete: its prefix delete would also take every
# longer command starting with this text (forget `ls` -> `ls -la` gone too).
# So atuin's copies go only when each prefix match is this exact command;
# otherwise forget says so and leaves them for ctrl-r, where ctrl-o then
# ctrl-d deletes the selected entry.
function forget
    set -l cmd (commandline | string collect)
    printf "\nDo you want to forget '%s'? [Y/n]\n" $cmd
    switch (read | tr A-Z a-z)
        case n no
            commandline -f repaint
            return
        case y yes ''
            history delete --exact --case-sensitive -- $cmd

            # Prefix search is case-insensitive, so `LS` also blocks `ls`:
            # erring towards deleting nothing. Status 1 means no match.
            if type -q atuin
                set -l matches (atuin search --search-mode prefix --filter-mode global --cmd-only --print0 -- $cmd | string split0)
                set -l others
                for m in $matches
                    test "$m" = "$cmd"; or set -a others $m
                end
                if test (count $matches) -gt 0
                    if test (count $others) -eq 0
                        atuin search --delete --search-mode prefix --filter-mode global -- $cmd
                    else
                        printf "forget: kept in atuin, which holds %d other command(s) starting with it, e.g. '%s'; delete it in ctrl-r: select it, ctrl-o, ctrl-d\n" (count $others) $others[1] >&2
                    end
                end
            end

            commandline ""
            commandline -f repaint
    end
end
