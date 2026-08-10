#!/usr/bin/env bash

# Preview.app markup ("AnnotationKit") defaults: magenta arrows/shapes,
# magenta 24pt annotation text, and a solid black fill so text boxes get a
# readable background over busy screenshots -- markup that stands out from
# any UI for LLM review (see .claude/skills/review-screenshot).
#
# Preview has no settings UI for these -- it just remembers the last-used
# values in its prefs, so picking another color in the markup toolbar
# overrides this. Re-run this script to reset to magenta.

set -euo pipefail

[ "$(uname)" = "Darwin" ] || { echo "macOS only"; exit 1; }

# Preview caches its prefs in-process and would overwrite ours on quit.
if pgrep -xq Preview; then
  echo "Quitting Preview..."
  osascript -e 'quit app "Preview"'
  sleep 2
fi

python3 - <<'EOF'
import plistlib
import subprocess

R, G, B = 1.0, 0.0, 1.0              # magenta: stroke + text
FILL_R, FILL_G, FILL_B = 0.0, 0.0, 0.0  # black: text box / shape background


# An NSKeyedArchiver-encoded CIColor, the same format Preview writes
# itself (csid 15 = its default color space).
def cicolor(r, g, b, a=1.0):
    return plistlib.dumps({
        '$version': 100000,
        '$archiver': 'NSKeyedArchiver',
        '$top': {'root': plistlib.UID(1)},
        '$objects': [
            '$null',
            {'$class': plistlib.UID(2), 'csid': 15,
             'red': r, 'green': g, 'blue': b, 'alpha': a},
            {'$classname': 'CIColor', '$classes': ['CIColor', 'NSObject']},
        ],
    }, fmt=plistlib.FMT_BINARY)

# Text tool: RTF attribute sample -- 24pt (fs48 = half-points) centered
# Helvetica; color 2 in \colortbl is the text color (0-255 per channel).
rtf = (r"""{\rtf1\ansi\ansicpg1252\cocoartf2870
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;\red%d\green%d\blue%d;}
{\*\expandedcolortbl;;\cssrgb\c%d\c%d\c%d;}
\pard\pardirnatural\qc\partightenfactor0

\f0\fs48 \cf2 a}""" % (round(R * 255), round(G * 255), round(B * 255),
                       round(R * 100000), round(G * 100000),
                       round(B * 100000))).encode('ascii')


def write(key, data):
    subprocess.run(
        ['defaults', 'write', 'com.apple.Preview',
         'com.apple.AnnotationKit.' + key, '-data', data.hex()],
        check=True)


write('strokeColor', cicolor(R, G, B))
write('fillColor', cicolor(FILL_R, FILL_G, FILL_B))
write('textAttributes', rtf)
print('Preview markup defaults set: '
      'magenta stroke + magenta 24pt text on solid black fill')
EOF
