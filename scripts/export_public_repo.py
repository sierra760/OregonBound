#!/usr/bin/env python3
"""Export the publishable subset of this checkout into a fresh repository.

Everything derived from MECC's Oregon Trail files or Apple's System 7.0 stays
behind: the original files and raw resource forks, every extracted asset, the
Ghidra project and decompilation exports, reference screenshots, and the
pseudocode-based analysis notes. What is exported is original work: the Swift
app (which decodes the player's own files at runtime), the extraction scripts,
tests, and recovery notes.

    python3 scripts/export_public_repo.py ../OregonBound-public [--init-git]
"""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EXCLUDED_PREFIXES = (
    "Original/", "raw/", "assets/", "ghidra/", "tools/", "build/", "docs/",
)
# Root-level analysis notes derived from pseudocode exports.
EXCLUDED_FILES = {
    "skills-lock.json", "GAME_LOOP_ANALYSIS.md", "HUNT_ANALYSIS.md",
    "RIVER_ANALYSIS.md", "SHOPPING_ANALYSIS.md", "ENDING_ANALYSIS.md",
}
# Test resources that are original screen captures; the tests skip without them.
PROJECT_YML_DROP = re.compile(
    r"      - path: \.\./docs/reference/[^\n]+\n        buildPhase: resources\n        type: file\n")

PUBLIC_GITIGNORE = """\
# Player-supplied and derived original data: never commit these.
/Original/
/raw/
/assets/
/ghidra/
/tools/
/docs/reference/
*.rsrc
*.dsk
*.img
*.image
*.toast
*.hqx
*.sit
*.bin
# Synthetic test fixture (dummy data only)
!/OregonBound/OregonBoundTests/Fixtures/tiny-hfs.dsk

.DS_Store
build/
DerivedData/
xcuserdata/
*.xcuserstate
__pycache__/
*.pyc
.pytest_cache/
.venv/
.idea/
.vscode/
"""


def tracked_files() -> list[str]:
    output = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True).stdout
    return [entry.decode("utf-8", "surrogateescape") for entry in output.split(b"\0") if entry]


def is_public(path: str) -> bool:
    """Original work only: no derived data, no local tool state, no planning scratch."""
    if path in EXCLUDED_FILES or path.startswith(EXCLUDED_PREFIXES):
        return False
    if path.startswith(".github/workflows/") and path.endswith((".yml", ".yaml")):
        return True
    if path.startswith(".") and path != ".gitignore":
        return False  # editor, tool and cache state
    if any(part.startswith(".") for part in path.split("/")):
        return False
    return True


def excluded_hashes() -> set[str]:
    digests: set[str] = set()
    for path in tracked_files():
        if not is_public(path):
            file = ROOT / path
            if file.is_file():
                digests.add(hashlib.sha256(file.read_bytes()).hexdigest())
    return digests


def export(destination: Path, init_git: bool) -> int:
    if destination.exists() and any(destination.iterdir()):
        print(f"{destination} is not empty", file=sys.stderr)
        return 1
    destination.mkdir(parents=True, exist_ok=True)
    banned = excluded_hashes()
    copied = 0
    for path in tracked_files():
        if not is_public(path):
            continue
        source = ROOT / path
        if not source.is_file():
            continue
        if hashlib.sha256(source.read_bytes()).hexdigest() in banned:
            print(f"refusing to export {path}: identical to an excluded file", file=sys.stderr)
            return 1
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied += 1
    project = destination / "OregonBound" / "project.yml"
    project.write_text(PROJECT_YML_DROP.sub("", project.read_text()))
    (destination / ".gitignore").write_text(PUBLIC_GITIGNORE)
    generated = destination / "OregonBound" / "OregonBound.xcodeproj"
    if shutil.which("xcodegen"):
        subprocess.run(["xcodegen", "generate", "--spec", str(project)], check=True, capture_output=True)
    elif generated.exists():
        shutil.rmtree(generated)
        print("xcodegen not found: removed the stale Xcode project; run `xcodegen generate` in the export")
    print(f"exported {copied} files to {destination}")
    if init_git:
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=destination, check=True)
        subprocess.run(["git", "add", "-A"], cwd=destination, check=True)
        print("initialized a git repository; commit when ready")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--init-git", action="store_true", help="git init and stage the export")
    args = parser.parse_args()
    raise SystemExit(export(args.destination.resolve(), args.init_git))
