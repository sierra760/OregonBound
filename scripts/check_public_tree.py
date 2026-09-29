"""Check tracked publication files for excluded data and common credential formats.

This is a guard against accidental inclusion, not a legal or exhaustive security audit.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {"Original", "raw", "assets", "ghidra", "tools", "build", ".planning"}
SYNTHETIC = "OregonBound/OregonBoundTests/Fixtures/tiny-hfs.dsk"
SECRETS = re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[0-9A-Z]{16}")
ENCODED = re.compile(r'"[A-Za-z0-9+/=]{180,}"')

def main():
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    problems = []
    for name in filter(None, names):
        p = Path(name)
        if p.parts[0] in EXCLUDED or name.startswith("docs/reference/"):
            problems.append((name, "excluded data directory"))
        if p.suffix.lower() in {".dsk", ".img", ".rsrc", ".bin", ".hqx", ".sit", ".pem", ".p12", ".mobileprovision"} and name != SYNTHETIC:
            problems.append((name, "restricted file type"))
        try:
            text = (ROOT / p).read_text()
        except UnicodeError:
            continue
        except FileNotFoundError:
            problems.append((name, "tracked file missing"))
            continue
        if SECRETS.search(text):
            problems.append((name, "possible credential"))
        if p.suffix == ".swift" and ENCODED.search(text):
            problems.append((name, "large encoded literal needs review"))
    for name, reason in problems:
        print(f"{name}: {reason}")
    if not problems:
        print(f"Publication checks passed for {len(list(filter(None, names)))} tracked files.")
    return bool(problems)

if __name__ == "__main__":
    sys.exit(main())
