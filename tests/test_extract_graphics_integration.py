import json
import shutil
import subprocess
import tempfile
import unittest
from io import StringIO
from unittest import mock
from pathlib import Path

from scripts import extract_graphics
from scripts.graphics_extract.models import (
    DecodeDiagnostic,
    Manifest,
    PaletteInfo,
    PaletteRecord,
    ResourceInfo,
)


ROOT = Path(__file__).resolve().parent.parent


class ExtractGraphicsIntegrationTests(unittest.TestCase):
    def test_cli_writes_manifest_and_research_tree(self):
        output_dir = Path(tempfile.mkdtemp(prefix="oregon-graphics-test-"))
        try:
            result = subprocess.run(
                [
                    "python3",
                    str(ROOT / "scripts" / "extract_graphics.py"),
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            manifest_path = output_dir / "manifests" / "graphics_manifest.json"
            self.assertTrue(manifest_path.exists())
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            images = manifest["images"]
            self.assertGreaterEqual(len(images), 58)
            self.assertEqual(
                len(
                    {
                        item["resource"]["id"]
                        for item in images
                        if item["resource"]["type"] == "cicn"
                    }
                ),
                24,
            )
            self.assertEqual(
                len(
                    {
                        item["resource"]["id"]
                        for item in images
                        if item["resource"]["type"] == "PICT"
                    }
                ),
                1,
            )
            self.assertEqual(
                len(
                    {
                        item["resource"]["id"]
                        for item in images
                        if item["resource"]["type"] == "Imag"
                    }
                ),
                33,
            )
            self.assertTrue((output_dir / "diagnostics" / "summary.json").exists())
        finally:
            shutil.rmtree(output_dir)

    def test_strict_mode_returns_nonzero_for_nested_palette_errors(self):
        manifest = Manifest(
            source_file="oregon_color",
            palettes=[
                PaletteRecord(
                    resource=ResourceInfo("oregon_color", "clut", 128, "", 12),
                    palette=PaletteInfo(source="clut", entry_count=0, resource_id=128),
                    colors=[],
                    diagnostics=[
                        DecodeDiagnostic("error", "clut.decode_failed", "truncated color table")
                    ],
                )
            ],
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            with mock.patch.object(extract_graphics, "extract", return_value=manifest):
                with mock.patch("sys.stderr", new_callable=StringIO):
                    with mock.patch("sys.stdout", new_callable=StringIO):
                        self.assertEqual(
                            extract_graphics.main(["--strict", "--output-dir", temp_dir]),
                            1,
                        )


if __name__ == "__main__":
    unittest.main()
