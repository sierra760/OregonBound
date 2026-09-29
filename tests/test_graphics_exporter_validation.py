from pathlib import Path
import json
import tempfile
import unittest

from PIL import Image

from scripts.graphics_extract.exporter import image_output_path, status_summary, write_outputs
from scripts.graphics_extract.models import (
    DecodeImage,
    DecodeStatus,
    Manifest,
    PaletteInfo,
    PaletteRecord,
    ResourceInfo,
)
from scripts.graphics_extract.validation import validate_manifest


def resource(resource_type: str, resource_id: int) -> ResourceInfo:
    return ResourceInfo(
        source_file="oregon_color",
        resource_type=resource_type,
        resource_id=resource_id,
        name="",
        raw_length=12,
    )


class GraphicsExporterValidationTests(unittest.TestCase):
    def test_image_output_path_includes_resource_type_and_multi_frame_index(self):
        image = DecodeImage(
            resource=resource("Imag", 19000),
            status=DecodeStatus.OK,
            image_path=None,
            width=4,
            height=3,
            mode="RGBA",
            frame_index=2,
            frame_count=5,
        )

        path = image_output_path(Path("out"), image)

        self.assertEqual(path, Path("out/images/Imag/imag_19000_02.png"))

    def test_image_output_path_rejects_path_traversal_resource_type(self):
        image = DecodeImage(
            resource=resource("../..", 19000),
            status=DecodeStatus.OK,
            image_path=None,
            width=4,
            height=3,
            mode="RGBA",
        )

        with self.assertRaisesRegex(ValueError, "Invalid resource type"):
            image_output_path(Path("out"), image)

    def test_write_outputs_saves_png_manifest_summary_and_contact_sheet(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            image = DecodeImage(
                resource=resource("PICT", 128),
                status=DecodeStatus.OK,
                image_path=None,
                width=2,
                height=2,
                mode="RGBA",
                image=Image.new("RGBA", (2, 2), (255, 0, 0, 255)),
            )
            manifest = Manifest(source_file="raw/oregon_color.rsrc", images=[image])

            returned = write_outputs(root, manifest)

            self.assertIs(returned, manifest)
            self.assertEqual(image.image_path, "images/PICT/pict_128.png")
            self.assertTrue((root / image.image_path).is_file())
            self.assertTrue((root / "contact_sheets" / "PICT.png").is_file())

            manifest_json = json.loads((root / "manifests" / "graphics_manifest.json").read_text())
            summary_json = json.loads((root / "diagnostics" / "summary.json").read_text())
            self.assertEqual(manifest_json["images"][0]["image_path"], "images/PICT/pict_128.png")
            self.assertEqual(summary_json["by_type"], {"PICT": {"ok": 1, "partial": 0, "failed": 0}})

    def test_write_outputs_rejects_malicious_resource_type_before_writing_outside_root(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "export"
            outside = Path(temp_dir) / "pict_128.png"
            image = DecodeImage(
                resource=resource("../..", 128),
                status=DecodeStatus.OK,
                image_path=None,
                width=2,
                height=2,
                mode="RGBA",
                image=Image.new("RGBA", (2, 2), (255, 0, 0, 255)),
            )
            manifest = Manifest(source_file="raw/oregon_color.rsrc", images=[image])

            with self.assertRaisesRegex(ValueError, "Invalid resource type"):
                write_outputs(root, manifest)

            self.assertFalse(outside.exists())
            self.assertIsNone(image.image_path)

    def test_write_outputs_rejects_contact_sheet_image_path_outside_root(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "export"
            outside = Path(temp_dir) / "outside.png"
            Image.new("RGBA", (2, 2), (0, 255, 0, 255)).save(outside)
            image = DecodeImage(
                resource=resource("PICT", 128),
                status=DecodeStatus.OK,
                image_path="../outside.png",
                width=2,
                height=2,
                mode="RGBA",
            )
            manifest = Manifest(source_file="raw/oregon_color.rsrc", images=[image])

            with self.assertRaisesRegex(ValueError, "Invalid image path"):
                write_outputs(root, manifest)

            self.assertFalse((root / "contact_sheets" / "PICT.png").exists())

    def test_status_summary_counts_images_and_palettes(self):
        manifest = Manifest(
            source_file="raw/oregon_color.rsrc",
            images=[
                DecodeImage(resource("Imag", 1), DecodeStatus.OK, None, 1, 1, "RGBA"),
                DecodeImage(resource("Imag", 2), DecodeStatus.PARTIAL, None, 1, 1, "RGBA"),
                DecodeImage(resource("cicn", 3), DecodeStatus.FAILED, None, None, None, None),
            ],
            palettes=[
                PaletteRecord(
                    resource=resource("clut", 129),
                    palette=PaletteInfo(source="clut", entry_count=16, resource_id=129),
                    colors=[(0, 0, 0)],
                )
            ],
        )

        summary = status_summary(manifest)

        self.assertEqual(summary["image_count"], 3)
        self.assertEqual(summary["palette_count"], 1)
        self.assertEqual(summary["by_type"]["Imag"], {"ok": 1, "partial": 1, "failed": 0})
        self.assertEqual(summary["by_type"]["cicn"], {"ok": 0, "partial": 0, "failed": 1})

    def test_validate_manifest_reports_failed_images_and_count_mismatches(self):
        manifest = Manifest(
            source_file="raw/oregon_color.rsrc",
            images=[
                DecodeImage(resource("Imag", 1), DecodeStatus.FAILED, None, None, None, None),
                DecodeImage(resource("PICT", 128), DecodeStatus.OK, None, 1, 1, "RGBA"),
            ],
        )

        loose = validate_manifest(manifest)
        strict = validate_manifest(manifest, strict=True)

        self.assertEqual(loose[0].severity, "warning")
        self.assertEqual(loose[0].code, "validation.failed_image")
        self.assertTrue(any(diag.code == "validation.count_mismatch" for diag in loose))
        self.assertTrue(all(diag.severity == "error" for diag in strict))


if __name__ == "__main__":
    unittest.main()
