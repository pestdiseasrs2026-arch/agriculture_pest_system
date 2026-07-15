"""Build normalized CSV manifests for disease and weed classifiers."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from pathlib import Path

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
FIELDS = ["path", "task", "split", "class_name", "class_index", "source"]


def normalized(value: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "_", value.strip().lower())
    return value.strip("_")


def stable_split(value: Path | str) -> str:
    key = value.as_posix() if isinstance(value, Path) else value
    bucket = int(hashlib.sha256(key.encode()).hexdigest()[:8], 16) % 100
    return "train" if bucket < 70 else "val" if bucket < 85 else "test"


def image_files(folder: Path):
    return sorted(path for path in folder.rglob("*") if path.suffix.lower() in IMAGE_SUFFIXES)


def disease_rows(rice_root: Path, plantvillage_root: Path | None):
    pending: list[dict[str, str]] = []
    if rice_root.is_dir():
        for class_dir in sorted(path for path in rice_root.iterdir() if path.is_dir()):
            class_name = f"rice__{normalized(class_dir.name)}"
            for path in image_files(class_dir):
                pending.append({
                    "path": str(path.resolve()), "task": "disease",
                    "split": stable_split(path), "class_name": class_name,
                    "source": "rice_leaf_diseases",
                })
    if plantvillage_root and plantvillage_root.is_dir():
        leaf_map_path = plantvillage_root.parent.parent / "leaf_grouping" / "leaf-map.json"
        leaf_map = json.loads(leaf_map_path.read_text(encoding="utf-8")) if leaf_map_path.is_file() else {}
        for class_dir in sorted(path for path in plantvillage_root.iterdir() if path.is_dir()):
            class_name = f"plantvillage__{normalized(class_dir.name)}"
            for path in image_files(class_dir):
                source_key = path.stem.split("___", 1)[-1].lower().strip()
                groups = leaf_map.get(source_key, [])
                matching_groups = [group for group in groups if group.split(":::", 1)[0] == class_dir.name]
                group_key = matching_groups[0] if matching_groups else path.as_posix()
                pending.append({
                    "path": str(path.resolve()), "task": "disease",
                    "split": stable_split(f"plantvillage:{group_key}"), "class_name": class_name,
                    "source": "plantvillage",
                })
    classes = {name: index for index, name in enumerate(sorted({row["class_name"] for row in pending}))}
    for row in pending:
        row["class_index"] = str(classes[row["class_name"]])
    return pending


def deepweeds_rows(root: Path, fold: int):
    labels_root, images_root = root / "labels", root / "images"
    species: dict[str, str] = {}
    with (labels_root / "labels.csv").open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            species[row["Label"]] = normalized(row["Species"])
    rows: list[dict[str, str]] = []
    missing = 0
    for split, prefix in (("train", "train"), ("val", "val"), ("test", "test")):
        with (labels_root / f"{prefix}_subset{fold}.csv").open(newline="", encoding="utf-8-sig") as handle:
            for source_row in csv.DictReader(handle):
                path = images_root / source_row["Filename"]
                missing += not path.is_file()
                rows.append({
                    "path": str(path.resolve()), "task": "weed", "split": split,
                    "class_name": f"deepweeds__{species[source_row['Label']]}",
                    "class_index": source_row["Label"], "source": "deepweeds",
                })
    return rows, missing


def write_manifest(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rice-root", type=Path, default=Path("rice+leaf+diseases"))
    parser.add_argument("--deepweeds-root", type=Path, default=Path("DeepWeeds-master/DeepWeeds-master"))
    parser.add_argument(
        "--plantvillage-root", type=Path,
        default=Path("PlantVillage-Dataset-master/PlantVillage-Dataset-master/raw/color"),
    )
    parser.add_argument("--fold", type=int, choices=range(5), default=0)
    parser.add_argument("--output", type=Path, default=Path("ai_training/data"))
    args = parser.parse_args()

    disease = disease_rows(args.rice_root, args.plantvillage_root)
    weeds, missing = deepweeds_rows(args.deepweeds_root, args.fold)
    write_manifest(args.output / "disease_manifest.csv", disease)
    write_manifest(args.output / "weed_manifest.csv", weeds)
    print(f"Disease records: {len(disease)}")
    print(f"DeepWeeds records: {len(weeds)}; missing images: {missing}")
    if missing:
        print(f"Extract images.zip into: {(args.deepweeds_root / 'images').resolve()}")
    if not args.plantvillage_root.is_dir():
        print(f"PlantVillage optional dataset not found at: {args.plantvillage_root.resolve()}")


if __name__ == "__main__":
    main()
