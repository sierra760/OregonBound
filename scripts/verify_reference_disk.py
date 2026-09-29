"""Compare an explicitly supplied reference DC42 disk with the local original.

Read-only: no downloads, mounts, or writes to either source. Prints evidence
as JSON. The downloaded archive is unpacked separately with unar.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

import machfs


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def verify_disk(image_path: Path):
    image = image_path.read_bytes()
    data_size, tag_size = struct.unpack_from(">II", image, 64)
    if len(image) != 84 + data_size + tag_size or image[82:84] != b"\x01\x00":
        raise ValueError("Expected a complete Disk Copy 4.2 image")
    volume = machfs.Volume()
    volume.read(image[84:84 + data_size])
    files = []
    for name in ("Oregon Trail", "Oregon Color", "Oregon Config", "Icon\r"):
        reference = volume["Oregon Trail"][name]
        local = Path("Original/Oregon Trail") / name
        resource_path = Path(str(local) + "/..namedfork/rsrc")
        resource = resource_path.read_bytes() if resource_path.exists() else b""
        entry = {"name": name, "type": reference.type.decode("mac_roman"),
                 "creator": reference.creator.decode("mac_roman"), "forks": {}}
        for fork, actual, expected in (("data", reference.data, local.read_bytes()), ("resource", reference.rsrc, resource)):
            entry["forks"][fork] = {"reference_length": len(actual), "local_length": len(expected),
                                     "reference_sha256": sha256(actual), "local_sha256": sha256(expected),
                                     "identical": actual == expected}
        if name in ("Oregon Trail", "Oregon Color"):
            raw = Path("raw/oregon_trail.rsrc" if name == "Oregon Trail" else "raw/oregon_color.rsrc")
            entry["raw_resource_identical"] = raw.read_bytes() == reference.rsrc
        files.append(entry)
    return {"disk_length": len(image), "disk_sha256": sha256(image), "hfs_data_length": data_size,
            "all_original_forks_identical": all(f["identical"] for entry in files for f in entry["forks"].values()),
            "files": files}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    result = verify_disk(args.image)
    print(json.dumps(result, indent=2))
    if not result["all_original_forks_identical"] or not all(e.get("raw_resource_identical", True) for e in result["files"]):
        raise SystemExit(1)
