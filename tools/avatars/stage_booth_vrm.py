"""Copy exported VRMs to an editor-import folder for the offline costume builder."""

import argparse
import json
from pathlib import Path
import struct


def stage(source: Path, destination: Path) -> None:
    data = source.read_bytes()
    magic, version, declared_length, json_size, chunk = struct.unpack_from("<4sIII4s", data)
    if magic != b"glTF" or version != 2 or declared_length != len(data) or chunk != b"JSON":
        raise ValueError(f"Unsupported exported VRM: {source}")
    document = json.loads(data[20:20 + json_size])
    old_vrm = document.get("extensions", {}).get("VRM")
    if old_vrm is not None and old_vrm.pop("secondaryAnimation", None):
        # The wardrobe uses the target's existing skeleton. Leave the real
        # exported VRM intact and skip the old add-on's secondary importer.
        encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode()
        encoded += b" " * (-len(encoded) % 4)
        remaining = data[20 + json_size:]
        data = struct.pack("<4sIII4s", magic, version, 20 + len(encoded) + len(remaining), len(encoded), chunk) + encoded + remaining
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists() or destination.read_bytes() != data:
        destination.write_bytes(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_folder", type=Path)
    parser.add_argument("import_folder", type=Path)
    args = parser.parse_args()
    for donor in sorted(args.export_folder.glob("*.vrm")):
        stage(donor, args.import_folder / donor.name)
