from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import macresources

from .models import ResourceInfo

GRAPHICAL_TYPES = {b"Imag", b"Ima4", b"cicn", b"PICT", b"clut"}


@dataclass(frozen=True)
class ResourceRecord:
    info: ResourceInfo
    type_code: bytes
    data: bytes


def _decode_name(name: object) -> str:
    if name is None:
        return ""
    if isinstance(name, bytes):
        return name.decode("mac_roman", errors="replace")
    return str(name)


def read_resources(path: Path, source_file: str = "oregon_color") -> list[ResourceRecord]:
    raw = path.read_bytes()
    resources = []
    for resource in macresources.parse_file(raw):
        type_code = resource.type if isinstance(resource.type, bytes) else bytes(resource.type)
        data = bytes(resource)
        resources.append(
            ResourceRecord(
                info=ResourceInfo(
                    source_file=source_file,
                    resource_type=type_code.decode("mac_roman", errors="replace"),
                    resource_id=resource.id,
                    name=_decode_name(resource.name),
                    raw_length=len(data),
                ),
                type_code=type_code,
                data=data,
            )
        )
    return resources


def graphical_resources(records: list[ResourceRecord]) -> list[ResourceRecord]:
    return [record for record in records if record.type_code in GRAPHICAL_TYPES]
