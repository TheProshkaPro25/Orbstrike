"""Install the ten Vefects Trails from the publisher's ZIP for local preview."""

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "assets/vfx_vendor/local/vefects"
SOURCE_PREFIX = "Vefects/Trails VFX/"
TARGET_PREFIX = "assets/vfx_vendor/local/vefects/"
ARCHIVE_SHA256 = "c6d99c4f9417b4f61f8fdddd31bb5aab4a6f02376a6a687fcfe807edb0caa561"
TEXT_RESOURCE_SUFFIXES = {".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres"}
ELEMENTS = ("Cosmos", "Dark", "Earth", "Electric", "Fire", "Ice", "Nature", "Sound", "Void", "Water")


def install(archive_path: Path) -> int:
    with archive_path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != ARCHIVE_SHA256:
            raise ValueError("Archive SHA-256 differs from the pinned Vefects Trails VFX 1.0.3 ZIP")

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    if TARGET.exists():
        raise FileExistsError(f"Local installation already exists at {TARGET}")

    with zipfile.ZipFile(archive_path) as archive, tempfile.TemporaryDirectory(dir=TARGET.parent) as temporary:
        staging = Path(temporary) / "vefects"
        pending = [f"VFX/Particles/VFX_Trail_{element}.tscn" for element in ELEMENTS]
        pending += ["LICENSE.txt", "README.txt", "CHANGELOG.txt"]
        installed = set()
        while pending:
            relative = pending.pop()
            if relative in installed:
                continue
            path = PurePosixPath(relative)
            if path.is_absolute() or ".." in path.parts or "\\" in relative:
                raise ValueError(f"Unsafe resource path: {relative}")
            member = SOURCE_PREFIX + relative
            data = archive.read(member)
            if path.suffix in TEXT_RESOURCE_SUFFIXES:
                source = data.decode("utf-8")
                prefix = "res://" + SOURCE_PREFIX
                pending.extend(re.findall(re.escape(prefix) + r'([^"\r\n]+)"', source))
                source = source.replace(prefix, "res://" + TARGET_PREFIX)
                # Let the host project own resource UIDs.
                source = re.sub(r' uid="uid://[^"]+"', "", source)
                data = source.encode("utf-8")
            destination = staging / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            installed.add(relative)
            if path.suffix in {".tga", ".png", ".wav"}:
                try:
                    settings = archive.read(member + ".import").decode("utf-8")
                except KeyError:
                    continue
                # Preserve the author's import parameters with fresh Godot metadata.
                remap, params = settings.split("[params]", maxsplit=1)
                importer = re.search(r"^importer=.*$", remap, re.MULTILINE).group()
                resource_type = re.search(r"^type=.*$", remap, re.MULTILINE).group()
                destination.with_suffix(path.suffix + ".import").write_text(
                    f"[remap]\n\n{importer}\n{resource_type}\n\n[deps]\n\n"
                    f'source_file="res://{TARGET_PREFIX}{relative}"\n\n[params]{params}',
                    encoding="utf-8",
                )
        staging.rename(TARGET)
    return len(installed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="Official Vefects Trails VFX 1.0.3 ZIP")
    arguments = parser.parse_args()
    try:
        count = install(arguments.archive)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"{error}\n")
    print(f"Installed {count} files under {TARGET}")
