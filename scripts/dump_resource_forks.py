#!/usr/bin/env python3
"""Write raw/oregon_trail.rsrc and raw/oregon_color.rsrc from your own copy of the game.

The reference extraction pipeline and the Python tests read those two raw
resource forks. Point this at any of: a folder holding the "Oregon Trail" and
"Oregon Color" files with native resource forks (macOS), an HFS or Disk Copy 4.2
disk image, or MacBinary (.bin) files. Nothing is downloaded or modified.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

try:
    import machfs
except ImportError:  # pragma: no cover
    machfs = None


def hfs_forks(image: bytes) -> dict[str, bytes]:
    if machfs is None:
        raise SystemExit("pip install machfs to read disk images")
    if len(image) > 84 and image[82:84] == b"\x01\x00":
        data_size, _tag = struct.unpack_from(">II", image, 64)
        if len(image) == 84 + data_size + _tag:
            image = image[84:84 + data_size]
    volume = machfs.Volume()
    volume.read(image)
    forks: dict[str, bytes] = {}

    def walk(folder):
        for name, entry in folder.items():
            if isinstance(entry, machfs.File):
                if entry.rsrc:
                    forks[name] = entry.rsrc
            else:
                walk(entry)
    walk(volume)
    return forks


def macbinary_fork(data: bytes) -> bytes | None:
    if len(data) < 128 or data[0] != 0 or data[74] != 0 or not 1 <= data[1] <= 63:
        return None
    data_len, rsrc_len = struct.unpack_from(">II", data, 83)
    start = 128 + (data_len + 127) // 128 * 128
    return data[start:start + rsrc_len] or None


def native_fork(path: Path) -> bytes | None:
    fork = Path(str(path) + "/..namedfork/rsrc")
    try:
        return fork.read_bytes() or None
    except OSError:
        return None


def collect(source: Path) -> dict[str, bytes]:
    if source.is_dir():
        found: dict[str, bytes] = {}
        for child in sorted(source.rglob("*")):
            if child.is_file() and not child.name.startswith("."):
                found.update(collect(child))
        return found
    data = source.read_bytes()
    if len(data) > 1026 and data[1024:1026] == b"BD" or (len(data) > 1110 and data[1108:1110] == b"BD"):
        return hfs_forks(data)
    fork = macbinary_fork(data)
    if fork is not None:
        return {source.stem: fork}
    fork = native_fork(source)
    if fork is not None:
        return {source.name: fork}
    if data[:4] == b"\x00\x00\x01\x00":
        return {source.stem: data}
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="folder, disk image, or MacBinary file")
    parser.add_argument("--output", type=Path, default=Path("raw"))
    args = parser.parse_args()
    forks = collect(args.source)
    wanted = {"Oregon Trail": "oregon_trail.rsrc", "Oregon Color": "oregon_color.rsrc"}
    args.output.mkdir(parents=True, exist_ok=True)
    written = 0
    for name, filename in wanted.items():
        match = next((fork for key, fork in forks.items() if key.lower() == name.lower()), None)
        if match is None:
            print(f"{name}: not found (have {', '.join(sorted(forks)) or 'nothing'})", file=sys.stderr)
            continue
        (args.output / filename).write_bytes(match)
        print(f"{name}: {len(match)} bytes -> {args.output / filename}")
        written += 1
    return 0 if written == 2 else 1


if __name__ == "__main__":
    raise SystemExit(main())
