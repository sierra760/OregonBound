"""Extract selected original System 7.0 bitmap fonts from its HFS disk.

The disk is an explicit local input. This script performs no downloads and
never changes the disk. See docs/ORIGINAL_SYSTEM_FONTS.md for provenance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import machfs
import macresources
from macresources.greggybits import unpack

try:
    from .extract_fonts import parse_fond, parse_nfnt, render_text
except ImportError:
    from extract_fonts import parse_fond, parse_nfnt, render_text

DISK_URL = "https://raw.githubusercontent.com/mihaip/infinite-mac/main/Images/System%207.0%20HD.dsk"
SOURCE_REVISION = "095b0fa8b5161d51fc11856d107bcfbbb605f5cd"
DISK_SHA256 = "691e76c73a88cd04ced93ec2c84661ca4d900581790e65188ce495f381b005b1"
SELECTIONS = ((0, "Chicago", 12), (3, "Geneva", 9), (3, "Geneva", 12))


def extract_system_fonts(disk_path: Path, output_dir: Path, controls_output_dir: Path | None = None) -> dict:
    disk = disk_path.read_bytes()
    digest = hashlib.sha256(disk).hexdigest()
    if digest != DISK_SHA256:
        raise ValueError("Disk does not match the verified System 7.0 reference image")
    volume = machfs.Volume()
    volume.read(disk)
    resource_fork = volume["System Folder"]["System"].rsrc
    resources = {(r.type, r.id): r for r in macresources.parse_file(resource_fork)}
    if controls_output_dir is not None:
        controls_output_dir.mkdir(parents=True, exist_ok=True)
        compressed = bytes(resources[b'CDEF', 0])
        (controls_output_dir / 'cdef_0.bin').write_bytes(compressed)
        (controls_output_dir / 'cdef_0_unpacked.bin').write_bytes(unpack(compressed))
    output_dir.mkdir(parents=True, exist_ok=True)
    families = {}
    fonts = []
    for family_id, name, size in SELECTIONS:
        family_data = bytes(resources[b"FOND", family_id])
        family = parse_fond(family_data, family_id, name)
        association = next(a for a in family["associations"] if a["size"] == size and a["style"] == 0)
        resource_id = association["resource_id"]
        data = bytes(resources[b"NFNT", resource_id])
        font, atlas = parse_nfnt(data, resource_id)
        font["family_associations"] = [{"family_id": family_id, "family_name": name, **association}]
        font["provenance"] = "system_font_manifest.json"
        (output_dir / f"nfnt_{resource_id}.bin").write_bytes(data)
        (output_dir / f"nfnt_{resource_id}.json").write_text(json.dumps(font, indent=2) + "\n")
        atlas.save(output_dir / font["atlas"]["file"])
        sample, advance = render_text(font, atlas, "Move   Stop Hunting")
        sample.save(output_dir / f"nfnt_{resource_id}_sample.png")
        (output_dir / f"system7_fond_{family_id}.bin").write_bytes(family_data)
        families[family_id] = family
        fonts.append({"resource_id": resource_id, "metrics_file": f"nfnt_{resource_id}.json",
                      "atlas_file": font["atlas"]["file"], "sample_advance": advance,
                      "source_sha256": font["source_sha256"], "source_length": len(data),
                      "family_associations": font["family_associations"]})
    manifest = {"schema_version": 1, "source_url": DISK_URL, "disk_sha256": digest,
                "source_revision": SOURCE_REVISION, "disk_length": len(disk), "hfs_path": "System Folder:System",
                "resource_fork_sha256": hashlib.sha256(resource_fork).hexdigest(),
                "families": list(families.values()), "fonts": fonts}
    (output_dir / "system_font_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/fonts"))
    parser.add_argument("--controls-output-dir", type=Path, help="Also preserve original and unpacked CDEF0")
    args = parser.parse_args()
    manifest = extract_system_fonts(args.disk, args.output_dir, args.controls_output_dir)
    print(f"Extracted {len(manifest['fonts'])} System 7.0 strikes")
