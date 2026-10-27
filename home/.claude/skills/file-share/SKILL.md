---
name: file-share
description: "Handing files to me on my own machine (screenshots, tarballs, artifacts). Load when you produce a file for me to open locally, or I ask to send, share or download one."
---

# File share: handing files to the host

Put the file in the file share folder the project's AGENTS.md names; if it
names none, ask where. Nothing syncs that folder: after writing there, print
the command I run on my machine (the ssh client) to fetch it, with `<vm>`
replaced by this machine's `hostname` (my ssh alias for it) and `<folder>` by
the folder's path relative to `~`:

```bash
mkdir -p ~/file_share/<vm> && rsync -av <vm>:<folder>/ ~/file_share/<vm>/
```
