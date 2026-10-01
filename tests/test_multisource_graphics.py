"""Synthetic source-qualified graphics output."""
import struct
from pathlib import Path
import macresources
import pytest
from scripts import extract_graphics


def bitmap():
    return struct.pack('>HI IHhhhh', 1, 20, 0, 1, 3, 5, 4, 6) + bytes([1, 0x80])


def resource_file(path, records):
    path.write_bytes(macresources.make_file([macresources.Resource(type=t, id=i, name='Synthetic', data=p) for t, i, p in records]))


def test_alternatives_keep_identity_and_bounds(tmp_path):
    source = tmp_path / 'input'
    resource_file(source, [(b'Imag', 7, bitmap()), (b'Ima4', 7, bitmap())])
    manifest = extract_graphics.extract(source, tmp_path / 'out', strict=True, source_name='graphics3', expected_counts={})
    assert len(manifest.images) == 2
    assert len({i.image_path for i in manifest.images}) == 2
    assert all(i.resource.source_file == 'graphics3' for i in manifest.images)
    assert all(i.to_dict()['bounds'] == [3, 5, 4, 6] for i in manifest.images)


def test_strict_extraction_rejects_failed_frames(tmp_path):
    source = tmp_path / 'input'
    resource_file(source, [(b'Imag', 7, b'\x00\x01\x00')])
    with pytest.raises(ValueError):
        extract_graphics.extract(source, tmp_path / 'out', strict=True, expected_counts={})


def test_cataloged_empty_placeholder_is_skipped(tmp_path):
    source = tmp_path / 'input'
    resource_file(source, [(b'Imag', 15522, b'\x00\x00'), (b'Imag', 7, bitmap())])
    manifest = extract_graphics.extract(source, tmp_path / 'out', strict=True, expected_counts={}, empty_placeholders={('Imag', 15522)})
    assert [i.resource.resource_id for i in manifest.images] == [7]


def test_oversized_color_backing_store_is_rejected_before_cropping():
    from scripts.graphics_extract.imag import decode_imag
    from scripts.graphics_extract.models import DecodeStatus, ResourceInfo
    pixmap = bytearray(50)
    struct.pack_into('>H', pixmap, 4, 0x8000 | 16000)
    struct.pack_into('>hhhh', pixmap, 6, 0, 0, 4200, 1)
    struct.pack_into('>H', pixmap, 32, 8)
    struct.pack_into('>I', pixmap, 42, 0xffffffff)
    payload = struct.pack('>HI', 1, 59) + pixmap + bytes(5)
    records = decode_imag(ResourceInfo('synthetic', 'Imag', 7, '', len(payload)), payload, bytes(768), 'synthetic')
    assert records[0].status == DecodeStatus.FAILED
    assert records[0].image is None
    assert any('backing store' in d.message for d in records[0].diagnostics)


@pytest.mark.parametrize('opcode', [0xE8, 0xE9, 0xEF, 0x89, 0x8F, 0x09, 0x0F, 0x49, 0x4F])
def test_truncated_compressed_color_rows_fail_strict_import(tmp_path, opcode):
    pixmap = bytearray(50)
    struct.pack_into('>H', pixmap, 4, 0x8003)
    struct.pack_into('>hhhh', pixmap, 6, 0, 0, 1, 3)
    struct.pack_into('>H', pixmap, 32, 8)
    struct.pack_into('>I', pixmap, 42, 0xffffffff)
    row = bytes([opcode]) + (bytes([3, 0]) if opcode < 0x80 else b'')
    stream = struct.pack('<HHB', 3, 1, 1) + row
    payload = struct.pack('>HI', 1, 54 + len(stream)) + pixmap + stream
    source = tmp_path / 'input'
    resource_file(source, [(b'Imag', 7, payload)])
    with pytest.raises(ValueError):
        extract_graphics.extract(source, tmp_path / 'out', strict=True, expected_counts={})
    assert not (tmp_path / 'out' / 'graphics_manifest.json').exists()
