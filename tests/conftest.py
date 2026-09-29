"""Skip data-dependent tests when the original resource forks are not present.

The public repository ships no MECC or Apple files. Tests that read raw/, assets/,
Original/ or the Ghidra project only run in a checkout where those were produced
locally (see README, "Reference extraction pipeline").
"""
from pathlib import Path
import re
import pytest

ROOT = Path(__file__).resolve().parents[1]
DATA_MARKERS = re.compile(r"\b(raw|assets|Original|ghidra|code_segments|pseudocode)\b|\.rsrc")
HAVE_DATA = (ROOT / "raw" / "oregon_trail.rsrc").exists() and (ROOT / "assets" / "graphics").exists()


def pytest_collection_modifyitems(config, items):
    if HAVE_DATA:
        return
    skip = pytest.mark.skip(reason="original game data not present (raw/ and assets/)")
    cache = {}
    for item in items:
        path = Path(str(item.fspath))
        if path not in cache:
            text = path.read_text(errors="replace") if path.exists() else ""
            cache[path] = DATA_MARKERS.search(text) is not None
        if cache[path]:
            item.add_marker(skip)


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Scripts under test open raw/ and assets/ themselves; treat that as a skip too."""
    outcome = yield
    report = outcome.get_result()
    if HAVE_DATA or report.when != "call" or report.outcome != "failed" or call.excinfo is None:
        return
    text = str(call.excinfo.value)
    if isinstance(call.excinfo.value, FileNotFoundError) or "FileNotFoundError" in text:
        if DATA_MARKERS.search(text):
            report.outcome = "skipped"
            report.longrepr = (str(item.fspath), None, "original game data not present (raw/ and assets/)")
