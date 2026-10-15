# gws keeps one account per config directory, so the second (work) account
# lives in its own directory: `gws-work auth login -s drive,gmail,...` logs it
# in there, then `gws-work drive files list` talks to it while plain `gws`
# stays on the personal account.
#
# One-time setup on a new machine (reuses the personal OAuth client, so the
# work address must be a test user on its consent screen):
#   mkdir -p ~/.config/gws-work
#   cp ~/.config/gws/client_secret.json ~/.config/gws-work/
#   GOOGLE_WORKSPACE_CLI_CONFIG_DIR=~/.config/gws-work gws auth login -s drive,gmail,calendar,docs,slides,sheets,tasks
function gws-work --wraps gws --description "gws against the work account's config dir"
    set -lx GOOGLE_WORKSPACE_CLI_CONFIG_DIR ~/.config/gws-work
    command gws $argv
end
