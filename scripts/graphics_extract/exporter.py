from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw

from .models import DecodeImage, Manifest

ALLOWED_RESOURCE_TYPES = frozenset({"Imag", "PICT", "cicn", "clut"})


def safe_resource_type(resource_type: str) -> str:
    if resource_type not in ALLOWED_RESOURCE_TYPES:
        raise ValueError(f"Invalid resource type path segment: {resource_type!r}")
    return resource_type


def root_child_path(root: Path, *parts: str) -> Path:
    root_resolved = root.resolve()
    path = root.joinpath(*parts)
    path_resolved = path.resolve()
    if not path_resolved.is_relative_to(root_resolved):
        raise ValueError(f"Output path escapes root: {path}")
    return path


def existing_image_path(root: Path, image_path: str) -> Path:
    path = Path(image_path)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Invalid image path: {image_path!r}")
    try:
        return root_child_path(root, *path.parts)
    except ValueError as error:
        raise ValueError(f"Invalid image path: {image_path!r}") from error


def image_output_path(root: Path, image: DecodeImage) -> Path:
    resource_type = safe_resource_type(image.resource.resource_type)
    stem = f"{resource_type.lower()}_{image.resource.resource_id}"
    if image.frame_index is not None and image.frame_count and image.frame_count > 1:
        stem += f"_{image.frame_index:02d}"
    return root_child_path(root, "images", resource_type, f"{stem}.png")


def write_outputs(root: Path, manifest: Manifest) -> Manifest:
    for image in manifest.images:
        if image.image is None:
            continue
        output_path = image_output_path(root, image)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        image.image.save(output_path)
        image.image_path = str(output_path.relative_to(root))

    manifest_dir = root / "manifests"
    diagnostics_dir = root / "diagnostics"
    contact_dir = root / "contact_sheets"
    manifest_dir.mkdir(parents=True, exist_ok=True)
    diagnostics_dir.mkdir(parents=True, exist_ok=True)
    contact_dir.mkdir(parents=True, exist_ok=True)

    (manifest_dir / "graphics_manifest.json").write_text(
        json.dumps(manifest.to_dict(), indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (diagnostics_dir / "summary.json").write_text(
        json.dumps(status_summary(manifest), indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    write_contact_sheets(root, manifest)
    return manifest


def status_summary(manifest: Manifest) -> dict[str, object]:
    by_type: dict[str, dict[str, int]] = defaultdict(lambda: {"ok": 0, "partial": 0, "failed": 0})
    for image in manifest.images:
        by_type[image.resource.resource_type][image.status.value] += 1
    return {
        "source_file": manifest.source_file,
        "image_count": len(manifest.images),
        "palette_count": len(manifest.palettes),
        "by_type": dict(sorted(by_type.items())),
    }


def write_contact_sheets(root: Path, manifest: Manifest) -> None:
    grouped: dict[str, list[DecodeImage]] = defaultdict(list)
    for image in manifest.images:
        if image.image_path and image.width and image.height:
            grouped[image.resource.resource_type].append(image)

    for resource_type, images in grouped.items():
        resource_type = safe_resource_type(resource_type)
        thumbs: list[tuple[DecodeImage, Image.Image]] = []
        for record in images:
            png_path = existing_image_path(root, record.image_path)
            with Image.open(png_path) as source:
                thumb = source.convert("RGBA")
            thumb.thumbnail((96, 96))
            thumbs.append((record, thumb.copy()))

        if not thumbs:
            continue
        columns = 6
        cell_w = 140
        cell_h = 128
        rows = (len(thumbs) + columns - 1) // columns
        sheet = Image.new("RGBA", (columns * cell_w, rows * cell_h), (255, 255, 255, 255))
        draw = ImageDraw.Draw(sheet)
        for index, (record, thumb) in enumerate(thumbs):
            col = index % columns
            row = index // columns
            x = col * cell_w
            y = row * cell_h
            sheet.alpha_composite(thumb, (x + (cell_w - thumb.width) // 2, y + 8))
            label = f"{record.resource.resource_id}"
            if record.frame_index is not None and record.frame_count and record.frame_count > 1:
                label += f":{record.frame_index}"
            draw.text((x + 6, y + 106), label, fill=(0, 0, 0, 255))
        sheet.save(root_child_path(root, "contact_sheets", f"{resource_type}.png"))
