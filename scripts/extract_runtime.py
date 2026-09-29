"""Extract runtime animation and cursor resources from player-supplied files."""
from pathlib import Path
import macresources

def extract_runtime(source, destination):
    resources = {(r.type, r.id): bytes(r.data) for r in macresources.parse_file(Path(source).read_bytes())}
    output = Path(destination) / "runtime"
    output.mkdir(parents=True, exist_ok=True)
    for key, name in [((b"Scpt", 5310), "scpt_5310.bin"), ((b"CURS", 128), "curs_128.bin")]:
        (output / name).write_bytes(resources[key])

if __name__ == "__main__":
    extract_runtime("raw/oregon_trail.rsrc", "assets")
