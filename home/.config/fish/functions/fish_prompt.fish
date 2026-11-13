function fish_prompt --description 'Write out the prompt'
    set -l last_status $status

    set -l normal (set_color normal)

    # Hack; fish_config only copies the fish_prompt function (see #736)
    if not set -q -g __fish_classic_git_functions_defined
        set -g __fish_classic_git_functions_defined

        function __fish_repaint_user --on-variable fish_color_user --description "Event handler, repaint when fish_color_user changes"
            if status --is-interactive
                commandline -f repaint 2>/dev/null
            end
        end

        function __fish_repaint_host --on-variable fish_color_host --description "Event handler, repaint when fish_color_host changes"
            if status --is-interactive
                commandline -f repaint 2>/dev/null
            end
        end

        function __fish_repaint_status --on-variable fish_color_status --description "Event handler; repaint when fish_color_status changes"
            if status --is-interactive
                commandline -f repaint 2>/dev/null
            end
        end

        function __fish_repaint_bind_mode --on-variable fish_key_bindings --description "Event handler; repaint when fish_key_bindings changes"
            if status --is-interactive
                commandline -f repaint 2>/dev/null
            end
        end

        # initialize our new variables
        if not set -q __fish_classic_git_prompt_initialized
            set -qU fish_color_user; or set -U fish_color_user -o green
            set -qU fish_color_host; or set -U fish_color_host -o cyan
            set -qU fish_color_status; or set -U fish_color_status red
            set -U __fish_classic_git_prompt_initialized
        end
    end

    set -l color_cwd
    set -l prefix
    switch $USER
        case root toor
            if set -q fish_color_cwd_root
                set color_cwd $fish_color_cwd_root
            else
                set color_cwd $fish_color_cwd
            end
            set suffix '#'
        case '*'
            set color_cwd $fish_color_cwd
            set suffix '%'
    end

    set -l prompt_status
    if test $last_status -ne 0
        set prompt_status ' ' (set_color $fish_color_status) "[$last_status]" "$normal"
    end

    # The machine's name in a block, e.g. " mbp ", on every prompt, past ones
    # included: a landmark to find in the scrollback where each command began
    # and the last one's output ended. The same over ssh as here. In the tmux
    # bar's colours (tmux.conf, @bar_light / @bar_dark), following the
    # terminal's light or dark theme, so the prompt and the bar read as one
    # family; any filled block is enough to scan by. A terminal that does not
    # report its colours ("unknown") gets the name in plain text.
    # Tried 2026-11-13 and left: red (the exit status's [127] and the bell's
    # colour), gruvbox purple (kitschy), inverse video (too heavy). If this
    # tan proves too faint, one step darker is gruvbox bg3, bdae93. Not a
    # transient prompt (fish_transient_prompt) either: tried the same day, it
    # shrank past prompts to "<cwd> % <command>" and took the landmark with it.
    set -l block
    switch "$fish_terminal_color_theme"
        case light
            set block (set_color -b d5c4a1 3c3836)
        case dark
            set block (set_color -b 504945 ebdbb2)
    end
    set -l prpwd (prompt_pwd)
    set -l host (machine_name)
    set -l gitpr (__fish_git_prompt)
    echo -n -s $block " $host " $normal ' ' (set_color $color_cwd) $prpwd $normal $gitpr $normal $prompt_status "$mode_str" " "
    echo -n "% "
end
