from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class DecodeStatus(str, Enum):
    OK = "ok"
    PARTIAL = "partial"
    FAILED = "failed"

    @property
    def is_error(self) -> bool:
        return self is DecodeStatus.FAILED


@dataclass(frozen=True)
class DecodeDiagnostic:
    severity: str
    code: str
    message: str

    def to_dict(self) -> dict[str, str]:
        return {
            "severity": self.severity,
            "code": self.code,
            "message": self.message,
        }


@dataclass(frozen=True)
class ResourceInfo:
    source_file: str
    resource_type: str
    resource_id: int
    name: str
    raw_length: int

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_file": self.source_file,
            "type": self.resource_type,
            "id": self.resource_id,
            "name": self.name,
            "raw_length": self.raw_length,
        }


@dataclass(frozen=True)
class PaletteInfo:
    source: str
    entry_count: int
    resource_id: int | None = None

    def to_dict(self) -> dict[str, Any]:
        data: dict[str, Any] = {
            "source": self.source,
            "entry_count": self.entry_count,
        }
        if self.resource_id is not None:
            data["resource_id"] = self.resource_id
        return data


@dataclass
class DecodeImage:
    resource: ResourceInfo
    status: DecodeStatus
    image_path: str | None
    width: int | None
    height: int | None
    mode: str | None
    frame_index: int | None = None
    frame_count: int | None = None
    palette: PaletteInfo | None = None
    byte_ranges: dict[str, list[int]] = field(default_factory=dict)
    diagnostics: list[DecodeDiagnostic] = field(default_factory=list)
    image: Any = field(default=None, repr=False, compare=False)

    def to_dict(self) -> dict[str, Any]:
        return {
            "resource": self.resource.to_dict(),
            "status": self.status.value,
            "image_path": self.image_path,
            "width": self.width,
            "height": self.height,
            "mode": self.mode,
            "frame_index": self.frame_index,
            "frame_count": self.frame_count,
            "palette": self.palette.to_dict() if self.palette else None,
            "byte_ranges": self.byte_ranges,
            "diagnostics": [diag.to_dict() for diag in self.diagnostics],
        }


@dataclass
class PaletteRecord:
    resource: ResourceInfo
    palette: PaletteInfo
    colors: list[tuple[int, int, int]]
    diagnostics: list[DecodeDiagnostic] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "resource": self.resource.to_dict(),
            "palette": self.palette.to_dict(),
            "colors": self.colors,
            "diagnostics": [diag.to_dict() for diag in self.diagnostics],
        }


@dataclass
class Manifest:
    source_file: str
    images: list[DecodeImage] = field(default_factory=list)
    palettes: list[PaletteRecord] = field(default_factory=list)
    diagnostics: list[DecodeDiagnostic] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "source_file": self.source_file,
            "images": [image.to_dict() for image in self.images],
            "palettes": [palette.to_dict() for palette in self.palettes],
            "diagnostics": [diag.to_dict() for diag in self.diagnostics],
        }
