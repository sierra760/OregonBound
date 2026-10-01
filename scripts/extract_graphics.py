#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import macresources

from graphics_extract.cicn import decode_cicn
from graphics_extract.cd_display import CD16Palette
from graphics_extract.exporter import write_outputs
from graphics_extract.imag import decode_imag, fallback_palette_from_resources
from graphics_extract.models import DecodeDiagnostic, Manifest, PaletteInfo, PaletteRecord
from graphics_extract.palette import parse_color_table
from graphics_extract.pict import convert_pict
from graphics_extract.resource_reader import graphical_resources, read_resources
from graphics_extract.validation import validate_manifest


def build_palette_records(records) -> list[PaletteRecord]:
    palette_records: list[PaletteRecord] = []
    for record in records:
        if record.type_code != b"clut":
            continue
        try:
            colors = parse_color_table(record.data, 0)
            palette_records.append(
                PaletteRecord(
                    resource=record.info,
                    palette=PaletteInfo(
                        source="clut",
                        entry_count=len(colors),
                        resource_id=record.info.resource_id,
                    ),
                    colors=colors,
                )
            )
        except Exception as exc:
            palette_records.append(
                PaletteRecord(
                    resource=record.info,
                    palette=PaletteInfo(
                        source="clut",
                        entry_count=0,
                        resource_id=record.info.resource_id,
                    ),
                    colors=[],
                    diagnostics=[DecodeDiagnostic("error", "clut.decode_failed", str(exc))],
                )
            )
    return palette_records


def extract(input_path: Path, output_dir: Path, strict: bool = False, *,
            source_name: str = "oregon_color", palette_context: tuple[bytes, str] | None = None,
            expected_counts: dict[str, int] | None = None,
            empty_placeholders: set[tuple[str, int]] | None = None,
            cd16_palette: CD16Palette | None = None) -> Manifest:
    raw_resources = list(macresources.parse_file(input_path.read_bytes()))
    fallback_palette, fallback_source = palette_context or fallback_palette_from_resources(raw_resources)
    records = graphical_resources(read_resources(input_path, source_name))
    manifest = Manifest(source_file=source_name)
    manifest.palettes.extend(build_palette_records(records))

    for record in records:
        if (record.info.resource_type, record.info.resource_id) in (empty_placeholders or set()):
            if record.type_code not in {b"Imag", b"Ima4"} or record.data != b"\x00\x00":
                raise ValueError("Invalid empty graphics placeholder")
            continue
        if record.type_code in {b"Imag", b"Ima4"}:
            frames = decode_imag(record.info, record.data, fallback_palette, fallback_source)
            if record.type_code == b"Ima4" and cd16_palette is not None:
                frames = [cd16_palette.convert(frame) for frame in frames]
            manifest.images.extend(frames)
        elif record.type_code == b"cicn":
            manifest.images.extend(decode_cicn(record.info, record.data))
        elif record.type_code == b"PICT":
            manifest.images.append(convert_pict(record.info, record.data))

    manifest.diagnostics.extend(validate_manifest(manifest, strict=strict, expected_counts=expected_counts))
    if strict:
        diagnostics = manifest.diagnostics + [d for i in manifest.images for d in i.diagnostics] + [d for p in manifest.palettes for d in p.diagnostics]
        failures = [d for d in diagnostics if d.severity == "error" or (d.severity == "warning" and d.code != "imag.palette_fallback")]
        if failures:
            raise ValueError("Graphics extraction failed: " + failures[0].message)
        if any(i.image is None for i in manifest.images):
            raise ValueError("Graphics extraction failed: missing decoded pixels")
    write_outputs(output_dir, manifest)
    return manifest


def error_diagnostics(manifest: Manifest) -> list[DecodeDiagnostic]:
    errors = [diag for diag in manifest.diagnostics if diag.severity == "error"]
    for image in manifest.images:
        errors.extend(diag for diag in image.diagnostics if diag.severity == "error")
    for palette in manifest.palettes:
        errors.extend(diag for diag in palette.diagnostics if diag.severity == "error")
    return errors


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Extract Oregon Color graphical resources")
    parser.add_argument("--input", type=Path, default=root / "raw" / "oregon_color.rsrc")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=root / "assets" / "graphics" / "oregon_color",
    )
    parser.add_argument("--strict", action="store_true", help="Return nonzero when validation emits errors")
    args = parser.parse_args(argv)

    manifest = extract(args.input, args.output_dir, strict=args.strict)
    errors = error_diagnostics(manifest)
    print(
        f"Wrote {len(manifest.images)} image records and "
        f"{len(manifest.palettes)} palette records to {args.output_dir}"
    )
    if args.strict and errors:
        for diag in errors:
            print(f"{diag.code}: {diag.message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
