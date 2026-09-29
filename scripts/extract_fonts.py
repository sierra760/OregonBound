"""Extract the original Macintosh NFNT strikes and FOND associations losslessly.

Format reference: Apple, Inside Macintosh: Text (1993), pp. 4-66–4-71,
4-91–4-95. See docs/ORIGINAL_FONTS.md for sources and rendering constraints.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct

import macresources
from PIL import Image

STYLE_NAMES = ("bold", "italic", "underline", "outline", "shadow", "condensed", "extended")
HEADER_NAMES = (
    "font_type", "first_char", "last_char", "wid_max", "kern_max", "n_descent",
    "rect_width", "rect_height", "ow_t_loc", "ascent", "descent", "leading", "row_words",
)


def _words(data: bytes, offset: int, count: int) -> list[int]:
    if offset < 0 or count < 0 or offset + count * 2 > len(data):
        raise ValueError(f"Truncated font table at byte {offset} ({count} words)")
    return list(struct.unpack_from(f">{count}H", data, offset))


def parse_nfnt(data: bytes, resource_id: int) -> tuple[dict, Image.Image]:
    """Return metrics and a mode-1 atlas; set bits are ink, not background."""
    values = _words(data, 0, 13)
    header = dict(zip(HEADER_NAMES, values))
    for key in ("kern_max", "n_descent", "leading"):
        if header[key] & 0x8000:
            header[key] -= 0x10000
    first, last = header["first_char"], header["last_char"]
    height, row_words = header["rect_height"], header["row_words"]
    if not (0 <= first <= last <= 255) or not height or not row_words:
        raise ValueError("Invalid NFNT character range or bitmap dimensions")
    if header["font_type"] & 0x0c:
        raise ValueError("Only original monochrome NFNT resources are supported")
    # Header is 26 bytes. Each scanline is rowWords big-endian 16-bit words.
    row_bytes = row_words * 2
    bitmap_end = 26 + row_bytes * height
    count = last - first + 1
    locations = _words(data, bitmap_end, count + 2)
    if locations != sorted(locations) or locations[-1] > row_words * 16:
        raise ValueError("Invalid NFNT glyph boundaries")
    # owTLoc counts words from the owTLoc field at byte16, not from byte0.
    # Positive nDescent supplies its high word for large strikes.
    offset_words = header["ow_t_loc"] + (max(0, header["n_descent"]) << 16)
    width_offset = 16 + 2 * offset_words
    if width_offset < bitmap_end + (count + 2) * 2:
        raise ValueError("NFNT width table overlaps glyph locations")
    # System 7 Geneva 9/12 end immediately after the missing-glyph metric,
    # without the sentinel present in Chicago and WTTimes. Accept that exact
    # plain-table boundary, retaining the original bytes without padding.
    omitted_terminator = (header['font_type'] & 3 == 0
                          and len(data) == width_offset + (count + 1) * 2)
    width_count = count + (1 if omitted_terminator else 2)
    widths = _words(data, width_offset, width_count)
    if widths[count] == 0xffff or (not omitted_terminator and widths[-1] != 0xffff):
        raise ValueError("NFNT missing-glyph metric or table terminator is invalid")
    table_end = width_offset + width_count * 2
    fractional_widths = None
    image_heights = None
    if header["font_type"] & 2:
        fractional_widths = _words(data, table_end, count + 2)
        table_end += (count + 2) * 2
    if header["font_type"] & 1:
        image_heights = _words(data, table_end, count + 2)
        table_end += (count + 2) * 2
    atlas = Image.frombytes("1", (row_words * 16, height), data[26:bitmap_end])
    glyphs = []
    for index in range(count + 1):
        code = first + index if index < count else None
        word = widths[index]
        missing = word == 0xffff
        glyph = {
            "index": index, "code": code,
            "character": bytes([code]).decode("mac_roman") if code is not None else None,
            "missing": missing,
            "atlas_rect": [locations[index], 0, locations[index + 1] - locations[index], height],
            "offset_width_word": word,
            "bearing_x": None if missing else (word >> 8) + header["kern_max"],
            "bearing_y": -header["ascent"],
            "advance": None if missing else word & 255,
        }
        if fractional_widths is not None:
            glyph["advance_8_8"] = fractional_widths[index]
        if image_heights is not None:
            glyph["image_top"] = image_heights[index] >> 8
            glyph["image_height"] = image_heights[index] & 255
        glyphs.append(glyph)
    return {
        "schema_version": 1, "resource_type": "NFNT", "resource_id": resource_id,
        "source_sha256": hashlib.sha256(data).hexdigest(), "source_length": len(data),
        "encoding": "mac_roman", "header": header,
        "atlas": {"file": f"nfnt_{resource_id}.png", "width": atlas.width,
                  "height": atlas.height, "mode": "1", "ink_value": 255,
                  "background_value": 0, "bit_order": "MSB first"},
        "table_offsets": {"bitmap": 26, "locations": bitmap_end, "widths": width_offset,
                          "parsed_end": table_end},
        "location_table": locations, "offset_width_table": widths,
        "fractional_width_table": fractional_widths, "image_height_table": image_heights,
        "missing_glyph_index": count, "glyphs": glyphs,
        "trailing_bytes_hex": data[table_end:].hex(),
    }, atlas


def parse_fond(data: bytes, resource_id: int, name: str) -> dict:
    """Decode the 52-byte FamRec and its required font association table."""
    words = _words(data, 0, 26)
    count = _words(data, 52, 1)[0] + 1
    entries = _words(data, 54, count * 3)
    associations = []
    for i in range(count):
        size, style, font_id = entries[i * 3:i * 3 + 3]
        associations.append({
            "size": size, "style": style,
            "style_names": [label for bit, label in enumerate(STYLE_NAMES) if style & (1 << bit)] or ["plain"],
            "resource_id": font_id if font_id < 0x8000 else font_id - 0x10000,
            "depth": 1 << ((style >> 8) & 3),
        })
    return {
        "resource_type": "FOND", "resource_id": resource_id, "name": name,
        "source_sha256": hashlib.sha256(data).hexdigest(), "source_length": len(data),
        "flags": words[0], "family_id": words[1], "version": words[25],
        "first_char": words[2], "last_char": words[3],
        "width_table_offset": struct.unpack_from(">I", data, 16)[0],
        "kerning_table_offset": struct.unpack_from(">I", data, 20)[0],
        "style_table_offset": struct.unpack_from(">I", data, 24)[0],
        "style_properties_4_12": words[14:23], "associations": associations,
    }


def glyph_for_code(font: dict, code: int | None) -> dict:
    """Resolve unavailable codes to the actual missing-character glyph."""
    first, last = font["header"]["first_char"], font["header"]["last_char"]
    if code is not None and first <= code <= last:
        glyph = font["glyphs"][code - first]
        if not glyph["missing"]:
            return glyph
    return font["glyphs"][font["missing_glyph_index"]]


def render_text(font: dict, atlas: Image.Image, text: str | bytes) -> tuple[Image.Image, int]:
    """Render one unscaled line with intrinsic metrics, returning image/advance.

    Black ink on white, without system fonts, antialiasing, synthetic styling,
    or fractional positioning. Unicode unavailable in Mac Roman uses the
    original missing glyph. Text controls are raw character codes, not layout.
    """
    if isinstance(text, bytes):
        codes = list(text)
    else:
        codes = []
        for character in text:
            try:
                codes.append(character.encode("mac_roman")[0])
            except UnicodeEncodeError:
                codes.append(None)
    placements = []
    pen = 0
    left = 0
    right = 0
    for code in codes:
        glyph = glyph_for_code(font, code)
        x, y, width, height = glyph["atlas_rect"]
        draw_x = pen + glyph["bearing_x"]
        placements.append((glyph, draw_x))
        left = min(left, draw_x)
        right = max(right, draw_x + width)
        pen += glyph["advance"]
    right = max(right, pen)
    image = Image.new("1", (max(1, right - left), font["header"]["rect_height"]), 255)
    for glyph, draw_x in placements:
        x, y, width, height = glyph["atlas_rect"]
        if width:
            mask = atlas.crop((x, y, x + width, y + height))
            image.paste(0, (draw_x - left, 0), mask)
    return image, pen


def extract_fonts(input_path: Path, output_dir: Path) -> dict:
    resources = list(macresources.parse_file(input_path.read_bytes()))
    families = []
    raw_fonts = {}
    output_dir.mkdir(parents=True, exist_ok=True)
    for resource in resources:
        data = bytes(resource)
        if resource.type == b"FOND":
            name = resource.name or ""
            if isinstance(name, bytes):
                name = name.decode("mac_roman")
            families.append(parse_fond(data, resource.id, name))
            (output_dir / f"fond_{resource.id}.bin").write_bytes(data)
        elif resource.type == b"NFNT":
            raw_fonts[resource.id] = data
    fonts = []
    samples = []
    for resource_id, data in sorted(raw_fonts.items()):
        font, atlas = parse_nfnt(data, resource_id)
        font["family_associations"] = [
            {"family_id": family["family_id"], "family_name": family["name"], **association}
            for family in families for association in family["associations"]
            if association["resource_id"] == resource_id
        ]
        atlas.save(output_dir / font["atlas"]["file"])
        (output_dir / f"nfnt_{resource_id}.bin").write_bytes(data)
        (output_dir / f"nfnt_{resource_id}.json").write_text(json.dumps(font, indent=2) + "\n")
        sample_text = f"NFNT {resource_id}  The Oregon Trail  ABC xyz 0123456789"
        sample, advance = render_text(font, atlas, sample_text)
        sample.save(output_dir / f"nfnt_{resource_id}_sample.png")
        samples.append(sample)
        fonts.append({"resource_id": resource_id, "metrics_file": f"nfnt_{resource_id}.json",
                      "atlas_file": font["atlas"]["file"], "sample_advance": advance,
                      "family_associations": font["family_associations"]})
    sheet = Image.new("1", (max(image.width for image in samples) + 16,
                           sum(image.height + 12 for image in samples) + 4), 255)
    top = 8
    for sample in samples:
        sheet.paste(sample, (8, top))
        top += sample.height + 12
    sheet.save(output_dir / "font_samples.png")
    manifest = {"schema_version": 1, "source": str(input_path),
                "source_sha256": hashlib.sha256(input_path.read_bytes()).hexdigest(),
                "families": families, "fonts": fonts}
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("raw/oregon_trail.rsrc"))
    parser.add_argument("--output-dir", type=Path, default=Path("assets/fonts"))
    args = parser.parse_args()
    result = extract_fonts(args.input, args.output_dir)
    print(f"Extracted {len(result['fonts'])} NFNT fonts and {len(result['families'])} FOND families")
