"""Preserve verified System 7 CDEF1 and extract its embedded monochrome art.

Requires the exact disk used for the recovered system fonts. Color pixs masks are
also preserved, but are NOT complete color controls: CDEF1 applies color-table
entries and bevel primitives at draw time. No image is synthesized by guessing.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import struct
from pathlib import Path
import machfs
import macresources
from macresources.greggybits import unpack
from PIL import Image

DISK_SHA256 = "691e76c73a88cd04ced93ec2c84661ca4d900581790e65188ce495f381b005b1"
NAMES = ["up", "up_pressed", "down", "down_pressed", "left", "left_pressed",
         "right", "right_pressed", "vertical_thumb", "horizontal_thumb"]


def monochrome_bitmaps(code: bytes) -> list[tuple[dict, Image.Image]]:
    """CDEF1:0aa8 references ten relative bitmap pointers at 0db2."""
    images = []
    for index, name in enumerate(NAMES):
        offset = 0xDB2 + struct.unpack_from(">h", code, 0xDB2 + index * 2)[0]
        row_bytes, top, left, bottom, right = struct.unpack_from(">Hhhhh", code, offset)
        width, height = right - left, bottom - top
        if (row_bytes, width, height) != (2, 16, 16):
            raise ValueError("Unexpected System 7 CDEF1 embedded bitmap")
        pixels = code[offset + 10:offset + 10 + row_bytes * height]
        if len(pixels) != row_bytes * height:
            raise ValueError("Truncated embedded bitmap")
        image = Image.new("RGBA", (width, height), (255, 255, 255, 255))
        for y in range(height):
            for x in range(width):
                if pixels[y * row_bytes + x // 8] & (0x80 >> (x % 8)):
                    image.putpixel((x, y), (0, 0, 0, 255))
        images.append(({"name": name, "index": index, "offset": offset,
                        "row_bytes": row_bytes, "width": width, "height": height}, image))
    return images


def extract(resource_fork: bytes, output: Path) -> dict:
    resources = {(r.type, r.id): r for r in macresources.parse_file(resource_fork)}
    compressed = bytes(resources[b"CDEF", 1])
    code = unpack(compressed)
    bitmaps = monochrome_bitmaps(code)
    output.mkdir(parents=True, exist_ok=True)
    (output / "system7_cdef_1.bin").write_bytes(compressed)
    (output / "system7_cdef_1_unpacked.bin").write_bytes(code)
    atlas = Image.new("RGBA", (160, 16))
    records = []
    for index, (record, image) in enumerate(bitmaps):
        atlas.paste(image, (index * 16, 0))
        records.append({**record, "atlas_rect": [index * 16, 0, 16, 16]})
    atlas.save(output / "system7_scrollbar_monochrome.png")
    color = []
    for index in range(14):
        rid, foreground, background, frame = struct.unpack_from(">hhhh", code, 0xC62 + index * 8)
        data = bytes(resources[b"pixs", rid])
        filename = f"system7_scrollbar_pixs_{rid}.bin"
        (output / filename).write_bytes(data)
        color.append({"index": index, "resource_id": rid, "file": filename,
                      "foreground_entry": foreground, "background_entry": background,
                      "frame_entry": frame})
    manifest = {"source_disk_sha256": DISK_SHA256,
                "source_resource_fork_sha256": hashlib.sha256(resource_fork).hexdigest(),
                "source_hfs_path": "System Folder:System", "resource_type": "CDEF", "resource_id": 1,
                "unpacked_sha256": hashlib.sha256(code).hexdigest(), "unpacked_length": len(code),
                "atlas_file": "system7_scrollbar_monochrome.png", "monochrome_bitmaps": records,
                "color_masks": color,
                "limitation": "Atlas is the monochrome CDEF branch; color masks require original drawing primitives and control color table."}
    (output / "system7_scrollbar.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path("assets/system_controls"))
    args = parser.parse_args()
    data = args.disk.read_bytes()
    if hashlib.sha256(data).hexdigest() != DISK_SHA256:
        raise SystemExit("Disk is not the verified System 7.0 reference")
    volume = machfs.Volume(); volume.read(data)
    result = extract(volume["System Folder"]["System"].rsrc, args.output)
    print(f"Extracted {len(result['monochrome_bitmaps'])} original embedded bitmaps")
