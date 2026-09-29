import unittest

from scripts.graphics_extract.models import (
    DecodeDiagnostic,
    DecodeImage,
    DecodeStatus,
    Manifest,
    PaletteInfo,
    ResourceInfo,
)


class GraphicsModelTests(unittest.TestCase):
    def test_manifest_serializes_nested_records(self):
        resource = ResourceInfo(
            source_file="oregon_color",
            resource_type="Imag",
            resource_id=19000,
            name="",
            raw_length=1234,
        )
        image = DecodeImage(
            resource=resource,
            status=DecodeStatus.OK,
            image_path="images/Imag/imag_19000.png",
            width=320,
            height=200,
            mode="P",
            frame_index=0,
            frame_count=1,
            palette=PaletteInfo(source="inline_ctable", entry_count=256),
            byte_ranges={"resource": [0, 1234], "pixels": [56, 1234]},
            diagnostics=[
                DecodeDiagnostic(
                    severity="info",
                    code="palette.inline",
                    message="Using inline color table",
                )
            ],
        )
        manifest = Manifest(source_file="oregon_color", images=[image])

        as_dict = manifest.to_dict()

        self.assertEqual(as_dict["source_file"], "oregon_color")
        self.assertEqual(as_dict["images"][0]["resource"]["type"], "Imag")
        self.assertEqual(as_dict["images"][0]["status"], "ok")
        self.assertEqual(as_dict["images"][0]["palette"]["source"], "inline_ctable")
        self.assertEqual(as_dict["images"][0]["diagnostics"][0]["code"], "palette.inline")

    def test_status_order_supports_strict_validation(self):
        self.assertTrue(DecodeStatus.FAILED.is_error)
        self.assertFalse(DecodeStatus.PARTIAL.is_error)
        self.assertFalse(DecodeStatus.OK.is_error)


if __name__ == "__main__":
    unittest.main()
