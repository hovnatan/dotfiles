#!/usr/bin/python3

import sys
import json
from pathlib import Path

from pythonopensubtitles.opensubtitles import OpenSubtitles
from pythonopensubtitles.utils import File

ost = OpenSubtitles()

auth_info = json.load(
    open(Path.home() / "Dropbox" / "scripts" / "opensubtitles.json")
)
ost.login(auth_info["user"], auth_info["password"])

file_path = Path(sys.argv[1])
file_name = file_path.name
file_dir = file_path.parent

output_dir = file_dir / 'downloaded_subtitles'
output_dir.mkdir(exist_ok=True, parents=True)

f = File(file_path)

data = ost.search_subtitles(
    [
        {
            'sublanguageid': 'eng',
            'moviehash': f.get_hash(),
            'moviebytesize': f.size
        }
    ]
)

for i, sub in enumerate(data):
    id_subtitle_file = sub.get('IDSubtitleFile')
    sub_file = file_path.stem + "_" + str(i) + ".srt"

    ost.download_subtitles(
        [id_subtitle_file],
        override_filenames={
            id_subtitle_file: sub_file,
        },
        output_directory=output_dir,
    )
    print(output_dir / sub_file)
