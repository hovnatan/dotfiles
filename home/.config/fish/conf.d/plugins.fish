# Plugins, managed by fisher (https://github.com/jorgebucaran/fisher) and
# pinned by commit in ../fish_plugins, fisher itself included:
#
#   fish_plugins (repo, tracked) --fisher update--> $fisher_path (machine-local)
#                                                    functions/ completions/ conf.d/
#                                                         |  loaded below
#                                                         v
#                                                    this shell
#
# fisher_path sits outside ~/.config/fish because that directory is a link
# into the repo: fisher's default ($__fish_config_dir) would copy every plugin
# file into home/.config/fish/{functions,completions,conf.d} next to ours.
# fisher records what it installed in universal variables (_fisher_*), which
# live in the gitignored fish_variables, so each machine tracks its own state.
#
# Install / apply after fish_plugins changed: scripts/setup_user_symlinks.sh
# (dotup runs it; it bootstraps fisher at the pinned commit when missing).
# Bump a plugin: edit its @<sha> in fish_plugins, then `fisher update`.
# Add one:       fisher install owner/repo@<sha>   (fisher appends the line)
# fish_plugins holds no comments: fisher rewrites the file after each run.

set -g fisher_path $HOME/.local/share/fisher

# Plugin functions/completions go right after the user's own directories, so
# a function in home/.config/fish/functions still overrides a plugin's.
set -l user_functions (contains -i -- $__fish_config_dir/functions $fish_function_path)
set -l user_completions (contains -i -- $__fish_config_dir/completions $fish_complete_path)
if test -z "$user_functions"; or test -z "$user_completions"
    echo "plugins.fish: $__fish_config_dir/{functions,completions} missing from fish_function_path/fish_complete_path; plugins not loaded" >&2
    return 1
end
if not test -f $fisher_path/functions/fisher.fish
    echo "plugins.fish: fisher not installed in $fisher_path; run ~/.dotfiles/scripts/setup_user_symlinks.sh" >&2
    return 1
end
set fish_function_path $fish_function_path[1..$user_functions] $fisher_path/functions $fish_function_path[(math $user_functions + 1)..]
set fish_complete_path $fish_complete_path[1..$user_completions] $fisher_path/completions $fish_complete_path[(math $user_completions + 1)..]

# Plugin conf.d snippets, as fish would source them from conf.d/. They run
# from here, after 0_user.fish ("plugins" sorts after it), because fzf's
# snippet binds into the key bindings 0_user.fish sets up.
for file in $fisher_path/conf.d/*.fish
    source $file
end
