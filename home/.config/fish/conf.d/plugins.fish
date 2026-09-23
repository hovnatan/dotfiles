# Vendored plugins, loaded without fisher. Each plugins/<repo>/ is a full
# snapshot of an upstream repo pinned by its .upstream file (repo, branch,
# commit), the same format as the vendored Claude Code skills: nothing is
# fetched at install or shell start, and changing a plugin is a reviewed
# commit in this repo.
#
#   plugins/<repo>/functions/     -> $fish_function_path, right after the
#                                    user's functions/ (so those still win)
#   plugins/<repo>/completions/   -> $fish_complete_path, likewise
#   plugins/<repo>/conf.d/*.fish  -> sourced here, as fisher's copies in
#                                    conf.d/ were ("plugins" sorts after
#                                    0_user.fish, which sets the key bindings
#                                    fzf's conf.d binds into)
#
# Check for updates / re-vendor (script shared with the skills):
#   SKILLS_DIR=~/.dotfiles/home/.config/fish/plugins ~/.dotfiles/scripts/check_skill_updates.sh [--apply [repo...]]
# Add one: copy the repo at a commit into plugins/<repo>/ (no .git) and write
# its .upstream; `--apply` then keeps it current.
#
# Fisher-isms the plugins still carry:
# - fisher fired <name>_install once, at install; nothing fires it here.
#   nvm.fish's handler only pre-downloads the Node index, which `nvm`
#   fetches itself on first use.
# - plugin-git's conf.d initializes from $fisher_path/functions, so
#   fisher_path points at the plugin being loaded while its conf.d runs;
#   without it the git abbreviations silently never appear.

set -l plugins_dir $__fish_config_dir/plugins
set -l user_functions (contains -i -- $__fish_config_dir/functions $fish_function_path)
set -l user_completions (contains -i -- $__fish_config_dir/completions $fish_complete_path)
if test -z "$user_functions"; or test -z "$user_completions"
    echo "plugins.fish: $__fish_config_dir/{functions,completions} missing from fish_function_path/fish_complete_path; plugins not loaded" >&2
    return 1
end

for plugin in $plugins_dir/*/
    set plugin (string trim --right --chars=/ -- $plugin)

    if test -d $plugin/functions
        set fish_function_path $fish_function_path[1..$user_functions] $plugin/functions $fish_function_path[(math $user_functions + 1)..]
        set user_functions (math $user_functions + 1)
    end
    if test -d $plugin/completions
        set fish_complete_path $fish_complete_path[1..$user_completions] $plugin/completions $fish_complete_path[(math $user_completions + 1)..]
        set user_completions (math $user_completions + 1)
    end

    set -l fisher_path $plugin
    for file in $plugin/conf.d/*.fish
        source $file
    end
end
