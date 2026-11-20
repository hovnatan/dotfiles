---
name: ntfy
description: "Phone notifications via ntfy.sh. Load when asked to notify, ping or alert my phone, or to send an ntfy message."
---

# Ntfy: how to notify my phone

When I ask to be notified on my phone / via ntfy, POST to the ntfy.sh topic
named in `~/.config/claude-ntfy/topic`. A topic name is a read capability
and this file is public, so the topics are kept in the private repo, one
per machine (`~/.dotfiles-private/machines/<name>/home/.config/claude-ntfy/`,
linked by the installer). If the file is missing on a machine, ask me for
the topic rather than inventing one.

    curl -sf --max-time 10 -H "Title: <short title>" -d "<message>" \
      "https://ntfy.sh/$(cat ~/.config/claude-ntfy/topic)"

From Python, stdlib urllib does the same (POST body = message; Title/Tags
as headers) -- no dependencies needed. The push at a finished turn nobody
looks at (`~/.dotfiles/home/.claude/mods/session-done/`) reads the same topic file, so one
subscription covers both.
