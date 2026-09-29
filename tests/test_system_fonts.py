from pathlib import Path
import hashlib
import json
import unittest

from PIL import Image
from macresources.greggybits import unpack
from scripts.extract_fonts import glyph_for_code, parse_fond, parse_nfnt, render_text

ROOT = Path("assets/fonts")
HASHES = {
    5478: "36157cec9b4fc731994ca93a7b3749dc9a8e2c24e6460f9b296cf98b45405852",
    4372: "b2bbba4a4cd1e78320c6a4256bd5d08e01326349804905a1e5d577521f03c754",
    13913: "1ae070fb30e3f9912eec605f023db2ca5919624ad898570d8aa12b3e65fec916",
}


class SystemFontTests(unittest.TestCase):
    def test_system_button_resource_decompression_and_geometry_instructions(self):
        raw = Path('raw/system7/cdef_0.bin').read_bytes()
        decoded = Path('raw/system7/cdef_0_unpacked.bin').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), '27fcc23be9d09e6ef5aeb05155c949e0e7c7fc7c9911b43770a7b222989bb26f')
        self.assertEqual(unpack(raw), decoded)
        # ControlRect height / 2, duplicated into both RoundRect oval arguments.
        self.assertEqual(decoded[0x3de:0x3ee].hex(), '3828000c98680008e24c300448443800')
        self.assertEqual(decoded[0x316:0x31c].hex(), '2f0c2f04a8b0')
        app = Path('assets/code_segments/CODE_5_Display.bin').read_bytes()
        self.assertEqual(app[0x3232:0x323a].hex(), '70033f003f00a89b')
        self.assertEqual(app[0x323e:0x3246].hex(), '70fc3f003f00a8a9')
        self.assertEqual(app[0x324a:0x3252].hex(), '70103f003f00a8b0')

    def test_raw_resources_and_exported_atlas_are_lossless(self):
        for resource_id, digest in HASHES.items():
            with self.subTest(resource_id=resource_id):
                data = (ROOT / f"nfnt_{resource_id}.bin").read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
                font, atlas = parse_nfnt(data, resource_id)
                exported = json.loads((ROOT / f"nfnt_{resource_id}.json").read_text())
                self.assertEqual(exported["glyphs"], font["glyphs"])
                self.assertEqual(atlas.tobytes(), data[26:font["table_offsets"]["locations"]])
                self.assertEqual(Image.open(ROOT / f"nfnt_{resource_id}.png").tobytes(), atlas.tobytes())
                self.assertEqual(font["table_offsets"]["parsed_end"], len(data))

    def test_system_fond_associations_select_actual_resource_ids(self):
        for family_id, name, size, resource_id in ((0, "Chicago", 12, 5478), (3, "Geneva", 9, 4372), (3, "Geneva", 12, 13913)):
            family = parse_fond((ROOT / f"system7_fond_{family_id}.bin").read_bytes(), family_id, name)
            matches = [a["resource_id"] for a in family["associations"] if a["size"] == size and a["style"] == 0]
            self.assertEqual(matches, [resource_id])

    def test_chicago_control_titles_and_hand_checked_A_pixels(self):
        font, atlas = parse_nfnt((ROOT / "nfnt_5478.bin").read_bytes(), 5478)
        self.assertEqual([render_text(font, atlas, s)[1] for s in ("Move", "Stop Hunting", "Load Game", "Travel the Trail")], [36, 83, 71, 98])
        glyph = glyph_for_code(font, 65)
        self.assertEqual((glyph["advance"], glyph["bearing_x"], glyph["atlas_rect"]), (8, 1, [202, 0, 6, 15]))
        x, _, width, height = glyph["atlas_rect"]
        rows = ["".join("#" if atlas.getpixel((x + c, y)) else "." for c in range(width)) for y in range(height)]
        self.assertEqual(rows, ["......", "......", "......", ".####.", "##..##", "##..##", "##..##", "######", "##..##", "##..##", "##..##", "##..##", "......", "......", "......"])

    def test_geneva_table_ends_at_missing_glyph_without_padding(self):
        for resource_id, advance, length in ((4372, 7, 2152), (13913, 10, 2734)):
            data = (ROOT / f"nfnt_{resource_id}.bin").read_bytes()
            font, _ = parse_nfnt(data, resource_id)
            self.assertEqual(len(data), length)
            self.assertEqual(len(font["offset_width_table"]), 219)
            self.assertEqual(font["offset_width_table"][-1], advance)
            self.assertEqual(glyph_for_code(font, 255)["index"], 218)
            self.assertEqual(glyph_for_code(font, 255)["advance"], advance)


if __name__ == "__main__":
    unittest.main()
