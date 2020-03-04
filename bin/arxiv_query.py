#!/usr/bin/python3

import json
import re
import sys
from pathlib import Path

import arxiv
import unidecode

ALPHA_NUM = re.compile(r'[\s]+')

for filepath in sys.argv[1:]:
    print(f"Processing {filepath}.")
    filepath = Path(filepath)
    if filepath.suffix[1:] != 'pdf':
        print("Not a PDF.")
        continue

    result = arxiv.query(id_list=[filepath.stem])
    if not result:
        print("Couldn't query.")
        continue

    result = result[0]
    published_date = result['published'].split('-')[0]
    # print(result['title'], result['authors'], published_date)

    metadata_path = filepath.parent / ".metadata.json"

    if metadata_path.exists():
        folder_metadata = json.load(open(metadata_path))
    else:
        folder_metadata = {}

    if filepath.name not in folder_metadata:
        folder_metadata[filepath.name] = {
            "title":
                ALPHA_NUM.sub(' ', unidecode.unidecode(result["title"])),
            "author":
                ALPHA_NUM.sub(
                    ' ', unidecode.unidecode(", ".join(result["authors"]))
                ),
            "year":
                published_date
        }
        json.dump(
            folder_metadata, open(metadata_path, "w"), indent=2, sort_keys=True
        )
