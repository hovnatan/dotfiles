from pathlib import Path
import argparse


def reverse_names(path: Path, prefix: str, output_path: Path):
    output_path.mkdir(parents=True, exist_ok=True)
    files = sorted(list(path.glob("*.jpeg")))
    print("Len:", len(files))
    parts_with_prefix = []
    for file in files:
        name_parts = file.stem.split("_")
        if name_parts[0] != prefix:
            continue
        parts_with_prefix.append((name_parts, file))

    for i, (name_parts, file) in enumerate(parts_with_prefix):
        new_name = name_parts[0] + "_" + "%03d" % (len(parts_with_prefix) - i - 1) + ".jpeg"
        # print(new_name)
        file.rename(output_path / new_name)
        # print(file)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", type=Path, help="Path to the directory with the images", default="/Users/hovnatan/GIRQ")
    parser.add_argument("--prefix", type=str, required=True, help="Prefix of the images" )
    parser.add_argument("--output_path", type=Path, help="Path to the directory to save the reversed images", default="/Users/hovnatan/GIRQ_reversed")
    args = parser.parse_args()
    reverse_names(args.path, args.prefix, args.output_path)