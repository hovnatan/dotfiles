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
# Every API call also bills quota to the client's GCP project, which the work
# account has no role on: without this grant (run as the project owner) each
# call fails with 403 "Caller does not have required permission to use
# project". The project has no billing account, so nothing is charged.
#   gcloud projects add-iam-policy-binding (jq -r .installed.project_id ~/.config/gws/client_secret.json) \
#       --member=user:<work-email> --role=roles/serviceusage.serviceUsageConsumer
function gws-work --wraps gws --description "gws against the work account's config dir"
    set -lx GOOGLE_WORKSPACE_CLI_CONFIG_DIR ~/.config/gws-work
    command gws $argv
end
