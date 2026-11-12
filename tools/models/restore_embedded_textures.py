#!/usr/bin/env python3
"""Restore PNGs derived from the checked-in creature GLBs before a clean import."""

import json
import struct
from pathlib import Path


ASSETS = Path(__file__).resolve().parents[2] / "assets"


def restore_textures(glb: Path) -> int:
    restored = 0
    with glb.open("rb") as stream:
        magic, version, _, json_length, chunk_type = struct.unpack("<4sIII4s", stream.read(20))
        if (magic, version, chunk_type) != (b"glTF", 2, b"JSON"):
            raise ValueError(f"Unexpected GLB header: {glb}")
        model = json.loads(stream.read(json_length))
        if not model.get("images"):
            return restored
        _, chunk_type = struct.unpack("<I4s", stream.read(8))
        if chunk_type != b"BIN\x00":
            raise ValueError(f"Missing binary chunk: {glb}")
        buffer_start = stream.tell()

        for index, image in enumerate(model["images"]):
            if image.get("mimeType") != "image/png" or "bufferView" not in image:
                continue
            name = image.get("name", str(index))
            path = glb.with_name(f"{glb.stem}_{name}.png")
            if path.exists() or not path.with_suffix(".png.import").is_file():
                continue
            view = model["bufferViews"][image["bufferView"]]
            stream.seek(buffer_start + view.get("byteOffset", 0))
            path.write_bytes(stream.read(view["byteLength"]))
            restored += 1
    return restored


if __name__ == "__main__":
    files = sorted(ASSETS.glob("creatures_hd/*.glb")) + sorted(ASSETS.glob("creatures_cmp/*.glb"))
    print(f"Restored {sum(restore_textures(glb) for glb in files)} embedded PNG textures")
