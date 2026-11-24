---
name: slack-post
description: "Posting to Slack as me. Load before sending, editing or uploading anything to Slack, by the slack CLI or the Slack MCP tools."
---

# Slack: draft in my self-DM, post elsewhere where I name

## Rules

- **Target.** My self-DM, unless my request names another channel or DM (by
  name, link or id). Naming one covers that one post; a later post or edit
  there needs its own ask. Before posting outside the self-DM, check it
  (`conversations.info channel=<id> include_num_members=true`) and tell me
  what it is: name, kind, private or external, members.
- **Self-DM.** `conversations.open users=<my id>` returns its id; my id is
  `auth.test`'s `user_id`. The same call with a person's id opens our DM,
  so it, too, waits for my request to name that person.
- **One message.** Text and its images go up together, the text as the
  images' caption, so a forward carries both (a copy-paste drops the
  images). `files.upload` is retired: `files.getUploadURLExternal` per file,
  POST the bytes to its URL, then one `files.completeUploadExternal` with the
  text as `initial_comment`.
- **Revise in place.** A change to a posted message is an update: same
  link, files kept. A new post only when I ask for one.
- **Read it back.** After posting or editing, read the message back and give
  me its permalink.
- **Token.** `SLACK_USER_TOKEN`, a user token, so posts are mine, with no
  footer. Check the environment for it (`[ -n "${SLACK_USER_TOKEN:-}" ]`).
  When it is not set, or there is no `slack` CLI, ask me where the token is
  or whether to use the MCP route, and wait for the answer. Load a file I
  name in each shell call that runs `slack`, since environment does not carry
  between calls:
  `set -a; source <(grep -m1 '^SLACK_USER_TOKEN=' <file>); set +a`.
  Output and command lines stay free of the token.
- **MCP route.** Post to my self-DM only, with my own user id as
  `channel_id`, whatever target my request named: a direct send carries an
  unsuppressible "Sent using @Claude" footer. Send it directly, since
  `slack_send_message_draft` drops markdown links (only the label text
  survives). Give me the link; I forward or copy-paste from there.
