#!/usr/bin/env python3
"""Check that the app's Swift importer reproduces the reference Python pipeline.

    "Oregon Bound" --import <sources...> --output /tmp/oregon-data
    python3 scripts/verify_swift_import.py /tmp/oregon-data

Images are compared pixel by pixel (indexed images also by palette and index),
WAVs byte for byte, and JSON documents structurally.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"


def compare_png(reference: Path, candidate: Path) -> str | None:
    with Image.open(reference) as a, Image.open(candidate) as b:
        if a.size != b.size:
            return f"size {a.size} != {b.size}"
        if a.mode == "P":
            if b.mode != "P":
                return f"mode {a.mode} != {b.mode}"
            if a.tobytes() != b.tobytes():
                return "palette indices differ"
            pa, pb = a.getpalette(), b.getpalette()
            if (pa + [0] * 768)[:768] != (pb + [0] * 768)[:768]:
                return "palette differs"
            return None
        mode = "L" if a.mode in ("1", "L") else "RGBA"
        if a.convert(mode).tobytes() != b.convert(mode).tobytes():
            return "pixels differ"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help='folder written by `"Oregon Bound" --import`')
    args = parser.parse_args()
    out = args.output
    pairs: list[tuple[Path, Path]] = []
    graphics = ASSETS / "graphics" / "oregon_color"
    pairs.append((graphics / "manifests" / "graphics_manifest.json", out / "graphics_manifest.json"))
    pairs.append((graphics / "diagnostics" / "summary.json", out / "diagnostics" / "summary.json"))
    for png in sorted((graphics / "images").rglob("*.png")):
        pairs.append((png, out / "images" / png.relative_to(graphics / "images")))
    for folder, patterns in {
        "pictures": ["*.json"], "strings": ["*.json"], "guidebook": ["*.json"], "dialogs": ["*.json"],
        "map_viewports": ["*.json"], "metadata": ["orgn.json"], "sounds": ["*.wav"],
        "fonts": ["nfnt_*.json", "nfnt_*.png", "manifest.json", "system_font_manifest.json"],
        "system_controls": ["system7_alert_icon_*.png", "system7_scrollbar_*.png", "system7_alert_icons.json",
                            "system7_scrollbar.json", "system7_scrollbar_color.json"],
    }.items():
        for pattern in patterns:
            for reference in sorted((ASSETS / folder).glob(pattern)):
                if reference.name.endswith("_sample.png") or reference.name == "system7_scrollbar_examples_rgb.png":
                    continue
                pairs.append((reference, out / folder / reference.name))
    failures = 0
    for reference, candidate in pairs:
        problem: str | None
        if not candidate.exists():
            problem = "missing"
        elif reference.suffix == ".png":
            problem = compare_png(reference, candidate)
        elif reference.suffix == ".json":
            problem = None if json.loads(reference.read_text()) == json.loads(candidate.read_text()) else "JSON differs"
        else:
            problem = None if reference.read_bytes() == candidate.read_bytes() else "bytes differ"
        if problem:
            failures += 1
            print(f"MISMATCH {candidate.relative_to(out)}: {problem}")
    print(f"{len(pairs)} files compared, {failures} mismatches")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
