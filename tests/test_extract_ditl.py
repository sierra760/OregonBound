import struct
import unittest
from scripts.extract_ditl import parse_ditl_resource


class DialogItemTests(unittest.TestCase):
    def test_edit_text_is_not_a_resource_reference(self):
        # Original registration DITL 9020 uses type 16 for its five name fields.
        text = b"Alice"
        item = bytes(4) + struct.pack(">hhhhBB", 1, 2, 16, 121, 16, len(text)) + text + b"\0"
        parsed = parse_ditl_resource(b"\0\0" + item, 9020)["items"][0]
        self.assertEqual(parsed["type"], "editText")
        self.assertEqual(parsed["data"], "Alice")

    def test_icon_and_picture_resource_ids(self):
        for item_type, name in [(32, "icon"), (64, "picture")]:
            item = bytes(4) + struct.pack(">hhhhBBH", 0, 0, 32, 32, item_type, 2, 2070)
            parsed = parse_ditl_resource(b"\0\0" + item, 1)["items"][0]
            self.assertEqual(parsed["type"], name)
            self.assertEqual(parsed["data"], 2070)
