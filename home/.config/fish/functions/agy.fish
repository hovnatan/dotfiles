# Start agy with Remote Control on from fish: agy has no settings.json key for
# Remote Control at startup (unlike claude's remoteControlAtStartup). Settings
# that do live in ~/.gemini/antigravity-cli/settings.json (altScreenMode, model)
# are merged there by scripts/setup_user_symlinks.sh. Subcommands and -p accept
# --remote-control too.
function agy --wraps agy --description 'agy with Remote Control on'
    command agy --remote-control $argv
end
