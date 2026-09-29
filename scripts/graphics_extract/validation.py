from __future__ import annotations

from .models import DecodeDiagnostic, DecodeStatus, Manifest

EXPECTED_OREGON_COLOR_COUNTS = {
    "Imag": 33,
    "PICT": 1,
    "cicn": 24,
    "clut": 2,
}


def validate_manifest(manifest: Manifest, strict: bool = False) -> list[DecodeDiagnostic]:
    diagnostics: list[DecodeDiagnostic] = []
    resource_ids_by_type: dict[str, set[int]] = {}
    for image in manifest.images:
        resource_ids_by_type.setdefault(image.resource.resource_type, set()).add(image.resource.resource_id)
        if image.status is DecodeStatus.FAILED:
            diagnostics.append(
                DecodeDiagnostic(
                    "error" if strict else "warning",
                    "validation.failed_image",
                    f"{image.resource.resource_type} {image.resource.resource_id} failed to decode",
                )
            )
    for palette in manifest.palettes:
        resource_ids_by_type.setdefault(palette.resource.resource_type, set()).add(palette.resource.resource_id)

    for resource_type, expected in EXPECTED_OREGON_COLOR_COUNTS.items():
        actual = len(resource_ids_by_type.get(resource_type, set()))
        if actual != expected:
            diagnostics.append(
                DecodeDiagnostic(
                    "error" if strict else "warning",
                    "validation.count_mismatch",
                    f"{resource_type} count {actual} did not match expected {expected}",
                )
            )
    return diagnostics
