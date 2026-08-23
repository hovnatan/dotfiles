# /// script
# requires-python = ">=3.11"
# dependencies = ["lxml", "pyspellchecker"]
# ///
"""What survived is not CORRUPT.

Coverage proves nothing was dropped; it cannot see mangled text, because all the
words are still there. This finds the mangling.

The signal that matters is `paragraphs starting lowercase`. It is the
fingerprint of dropped or mis-joined text -- a bullet whose continuation never
rejoined, a hyphen split across a page break, a figure box that ate a line of
prose. Anything above 0 is a real defect. The other counts are advisory.
"""

import argparse
import collections
import re
import sys
import zipfile

from lxml import etree
from spellchecker import SpellChecker

ap = argparse.ArgumentParser()
ap.add_argument("epub")
ap.add_argument("--show", type=int, default=10)
args = ap.parse_args()

z = zipfile.ZipFile(args.epub)
paras, items, heads = [], [], []
for n in sorted(z.namelist()):
    if not n.endswith(".xhtml") or "nav" in n:
        continue
    for e in etree.fromstring(z.read(n)).iter():
        tag = etree.QName(e).localname
        txt = " ".join("".join(e.itertext()).split())
        if not txt:
            continue
        if tag == "p":
            paras.append((n, txt))
        elif tag == "li":
            items.append((n, txt))
        elif tag in ("h1", "h2", "h3"):
            heads.append((n, txt))

print(f"paragraphs={len(paras)}  list-items={len(items)}  headings={len(heads)}\n")
TERM = (".", "?", "!", '"', "”", "’", "'", ")", ":", "…")


def report(title, hits):
    print(f"--- {title}: {len(hits)}")
    for n, t in hits[:args.show]:
        print(f"    [{n.split('/')[-1]}] {t[:96]}")
    print()
    return hits


# THE signal: a paragraph must not begin mid-sentence.
broken = report("paragraphs starting lowercase  <<< must be 0",
                [(n, t) for n, t in paras if t[:1].islower()])
report("list items starting lowercase  <<< must be 0",
       [(n, t) for n, t in items if t[:1].islower()])

# advisory
report("paragraphs with no terminal punctuation (run-in labels are fine)",
       [(n, t) for n, t in paras if not t.endswith(TERM)])
report("mid-word stray punctuation (broken hyphen joins)",
       [(n, t) for n, t in paras + items
        if re.search(r"[a-z][”\"’] [a-z]{2,}", t)])
report("doubled words (a heading merged into its paragraph?)",
       [(n, t) for n, t in paras + items if re.search(r"\b(\w+) \1\b", t, re.I)])

sp = SpellChecker()
words = collections.Counter()
for _, t in paras + items + heads:
    for w in re.findall(r"[A-Za-z][a-z’']{2,}", t):
        words[w.lower().replace("’", "'")] += 1
unknown = sp.unknown([w for w in words if "'" not in w])
print(f"--- unknown words (mostly jargon; scan for OCR garbage): {len(unknown)}")
for c, w in sorted(((words[w], w) for w in unknown), reverse=True)[:20]:
    print(f"    {c:4d}x  {w}")

sys.exit(1 if broken else 0)
