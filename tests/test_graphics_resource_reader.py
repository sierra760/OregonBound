from pathlib import Path
import unittest

from scripts.graphics_extract.resource_reader import graphical_resources, read_resources


class ResourceReaderTests(unittest.TestCase):
    def test_read_resources_returns_oregon_color_resource_records(self):
        records = read_resources(Path("raw/oregon_color.rsrc"))

        self.assertEqual(len(records), 62)
        self.assertEqual(sum(1 for record in records if record.type_code == b"Imag"), 33)
        self.assertEqual(sum(1 for record in records if record.type_code == b"cicn"), 24)
        self.assertEqual(sum(1 for record in records if record.type_code == b"PICT"), 1)
        self.assertEqual(sum(1 for record in records if record.type_code == b"clut"), 2)
        self.assertEqual(sum(1 for record in records if record.type_code == b"vers"), 2)

    def test_graphical_resources_filters_to_supported_graphical_types(self):
        records = read_resources(Path("raw/oregon_color.rsrc"))

        filtered = graphical_resources(records)

        self.assertEqual(len(filtered), 60)
        self.assertTrue(all(record.type_code in {b"Imag", b"cicn", b"PICT", b"clut"} for record in filtered))
        self.assertFalse(any(record.type_code == b"vers" for record in filtered))


if __name__ == "__main__":
    unittest.main()
