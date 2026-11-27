#!/usr/bin/env bash
#
# scantailor_boxes_test.sh -- the book-scan skill's script
# (home/.agents/skills/book-scan/scantailor_boxes.py) end to end, on a
# made-up four-page book (the stages are listed in
# scantailor_boxes_test.py's docstring). No call to a model is paid for: a
# stub `claude` stands first on PATH. It keeps each call's arguments in
# <work>/calls.jsonl and answers as the real one does (--output-format
# json), from the table of regions in the prompt: a region touching the scan
# edge is junk, and on the first pass page 1's largest region is mixed, which
# sends that page through the fine pass.
#
# Needs uv (it fetches numpy, pillow and scipy, as the script's own header
# asks) and python3; about 2 s, more the first time uv fills its cache.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO/scripts/lib/event_log.sh"

# Keep the log in the checkout; an installed ~/.dotfiles is not required.
EVENT_LOG_ROOT="$REPO/.logs"
event_log_start scantailor_boxes_test --no-prune
log "regression log: $EVENT_LOG_FILE"
for cmd in uv python3; do
  command -v "$cmd" >/dev/null || {
    log "ERROR: $cmd is missing; it is in the Nix package set (nix/flake.nix): nix profile upgrade nix"
    exit 1
  }
done

WORK=$(mktemp -d)
mkdir "$WORK/bin"
cat >"$WORK/bin/claude" <<'STUB'
#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

argv = sys.argv[1:]
with (Path(__file__).parent.parent / "calls.jsonl").open("a") as f:
    f.write(json.dumps(argv) + "\n")
prompt = argv[argv.index("-p") + 1]
image = re.search(r"`(previews[^`]*)`", prompt).group(1)
rows = re.findall(r"^\| (\d+) \| \d+ \| \d+ \| (\d+) \| (\d+) \| (yes|no) \|$", prompt, re.M)
junk = [int(n) for n, _, _, edge in rows if edge == "yes"]
mixed = []
if image == "previews/page-001.png":
    largest = max((r for r in rows if r[3] == "no"), key=lambda r: int(r[1]) * int(r[2]))
    mixed = [int(largest[0])]
verdict = {"junk": junk, "mixed": mixed, "unsure": [], "note": "stub"}
print(json.dumps({
    "is_error": False,
    "subtype": "success",
    "structured_output": verdict,
    "result": json.dumps(verdict),
    "total_cost_usd": 0.0,
    "modelUsage": {argv[argv.index("--model") + 1]: {}},
}))
STUB
chmod +x "$WORK/bin/claude"

PATH="$WORK/bin:$PATH" uv run --quiet --managed-python --script \
  "$REPO/scripts/tests/scantailor_boxes_test.py" "$REPO" "$WORK" "$EVENT_LOG_FILE"
