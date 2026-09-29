#!/usr/bin/env bash
# ghidra_import.sh — Import all 22 CODE segments into Ghidra as MC68000 and run auto-analysis
#
# Prerequisites:
#   - JDK 21+  (installed via: brew install openjdk@21)
#   - Ghidra   (extracted to tools/ghidra_12.1_PUBLIC from GitHub release zip)
#
# Installation steps (one-time):
#   brew install openjdk@21
#
#   # Ghidra is not in homebrew cask; download directly from GitHub releases:
#   curl -L -o tools/ghidra.zip \
#     "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1_build/ghidra_12.1_PUBLIC_20260513.zip"
#   unzip -q tools/ghidra.zip -d tools/
#
# IMPORTANT — dotfile path workaround:
#   Ghidra (analyzeHeadless) rejects project paths containing path components that start with '.'
#   (e.g. a temporary worktree path). The project is created in ~/ghidra_projects/ (clean path)
#   then moved to ghidra/ in the repo. The .gpr marker file is empty; only .rep contains data.
#
# Usage:
#   bash scripts/ghidra_import.sh
#
# Output:
#   ghidra/OregonBound.gpr   — Ghidra project marker file (empty, used by Ghidra to locate project)
#   ghidra/OregonBound.rep/  — Ghidra project repository with all 22 imported programs
#
# Notes on the decompiler binary:
#   Ghidra 12.1 ships with the decompiler pre-built for linux_x86_64 and win_x86_64 only.
#   The mac_arm_64 decompiler binary is missing from the release zip. This causes a harmless
#   "decompile does not exist" warning during auto-analysis (which only affects pseudocode
#   generation, not disassembly/function-identification analysis). Workaround for T03:
#   build the decompiler from source (tools/ghidra_12.1_PUBLIC/Ghidra/Features/Decompiler/src/decompile)
#   or use PyGhidra / Ghidra's Java decompiler API directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Paths
GHIDRA_HOME="$REPO_ROOT/tools/ghidra_12.1_PUBLIC"
ANALYZE_HEADLESS="$GHIDRA_HOME/support/analyzeHeadless"
# Staging dir: must not contain any path component starting with '.' (Ghidra restriction)
STAGING_DIR="$HOME/ghidra_projects"
GHIDRA_PROJECT_NAME="OregonBound"
# Final destination in repo
GHIDRA_DEST_DIR="$REPO_ROOT/ghidra"
CODE_SEGMENTS_DIR="$REPO_ROOT/assets/code_segments"

# MC68000, big-endian, 32-bit — standard for Classic Mac OS 68k apps
LANG_ID="68000:BE:32:default"
COMPILER_ID="default"

# JDK 21 — required by Ghidra 11+
JAVA_HOME_21="/opt/homebrew/opt/openjdk@21"
export JAVA_HOME="$JAVA_HOME_21"
export PATH="$JAVA_HOME_21/bin:$PATH"

# Verify Java 21
JAVA_VER=$(java -version 2>&1 | head -1)
echo "Java: $JAVA_VER"
if ! echo "$JAVA_VER" | grep -qE '"(21|22|23|24|25)'; then
    echo "ERROR: JDK 21+ required. Found: $JAVA_VER"
    echo "Install with: brew install openjdk@21"
    exit 1
fi

# Verify analyzeHeadless
if [ ! -x "$ANALYZE_HEADLESS" ]; then
    echo "ERROR: analyzeHeadless not found at $ANALYZE_HEADLESS"
    echo "Download Ghidra from: https://github.com/NationalSecurityAgency/ghidra/releases"
    exit 1
fi

echo "=== Ghidra: $GHIDRA_HOME ==="
echo "=== Staging: $STAGING_DIR/$GHIDRA_PROJECT_NAME ==="
echo "=== Final dest: $GHIDRA_DEST_DIR ==="
echo ""

# Clean up any existing staging project
rm -rf "$STAGING_DIR/$GHIDRA_PROJECT_NAME.gpr" "$STAGING_DIR/$GHIDRA_PROJECT_NAME.rep" 2>/dev/null || true
mkdir -p "$STAGING_DIR"

# Also clear any existing destination so we get a fresh import
rm -rf "$GHIDRA_DEST_DIR/$GHIDRA_PROJECT_NAME.gpr" "$GHIDRA_DEST_DIR/$GHIDRA_PROJECT_NAME.rep" 2>/dev/null || true
mkdir -p "$GHIDRA_DEST_DIR"

# --- Pass 1: CODE 0 (JumpTable) — import as MC68000 raw binary, no auto-analysis ---
# CODE 0 is the 68k jump table, not executable code. Import with processor set so
# instructions display correctly but skip analysis to avoid misidentifying data as code.
JUMP_TABLE="$CODE_SEGMENTS_DIR/CODE_0_JumpTable.bin"
echo "=== [1/2] Importing CODE 0 (JumpTable) — no analysis ==="
"$ANALYZE_HEADLESS" \
    "$STAGING_DIR" "$GHIDRA_PROJECT_NAME" \
    -import "$JUMP_TABLE" \
    -processor "$LANG_ID" \
    -cspec "$COMPILER_ID" \
    -noanalysis \
    -overwrite \
    2>&1
echo ""

# --- Pass 2: CODE 1-21 — import as MC68000 with full auto-analysis ---
# Build list of all CODE segment bins excluding CODE 0
CODE_BINS=()
for f in "$CODE_SEGMENTS_DIR"/CODE_*.bin; do
    basename_f="$(basename "$f")"
    # Exclude CODE_0_JumpTable.bin
    if [[ "$basename_f" != CODE_0_* ]]; then
        CODE_BINS+=("$f")
    fi
done

echo "=== [2/2] Importing ${#CODE_BINS[@]} CODE segments (1-21) with MC68000 auto-analysis ==="
echo "    (Warning: 'decompile does not exist' for mac_arm_64 is expected — decompiler binary"
echo "     is not included in the Ghidra release zip for macOS ARM. Analysis still succeeds.)"
echo ""
"$ANALYZE_HEADLESS" \
    "$STAGING_DIR" "$GHIDRA_PROJECT_NAME" \
    -import "${CODE_BINS[@]}" \
    -processor "$LANG_ID" \
    -cspec "$COMPILER_ID" \
    -overwrite \
    2>&1
echo ""

# --- Move staging project to repo ---
echo "=== Moving project to repo ==="
mv "$STAGING_DIR/$GHIDRA_PROJECT_NAME.gpr" "$GHIDRA_DEST_DIR/"
mv "$STAGING_DIR/$GHIDRA_PROJECT_NAME.rep" "$GHIDRA_DEST_DIR/"
echo "Moved to: $GHIDRA_DEST_DIR/"
echo ""

# --- Verify ---
echo "=== Verification ==="
if [ -f "$GHIDRA_DEST_DIR/$GHIDRA_PROJECT_NAME.gpr" ]; then
    echo "PASS: $GHIDRA_PROJECT_NAME.gpr exists"
else
    echo "FAIL: $GHIDRA_PROJECT_NAME.gpr not found"
    exit 1
fi

if [ -d "$GHIDRA_DEST_DIR/$GHIDRA_PROJECT_NAME.rep" ]; then
    PROGRAM_COUNT=$(find "$GHIDRA_DEST_DIR/$GHIDRA_PROJECT_NAME.rep" -name "*.db" 2>/dev/null | wc -l | tr -d ' ')
    echo "PASS: $GHIDRA_PROJECT_NAME.rep exists ($PROGRAM_COUNT program databases)"
else
    echo "FAIL: $GHIDRA_PROJECT_NAME.rep directory not found"
    exit 1
fi

echo ""
echo "=== Import complete ==="
echo "Project: $GHIDRA_DEST_DIR/$GHIDRA_PROJECT_NAME.gpr"
echo "Open in Ghidra GUI: File > Open Project > $GHIDRA_DEST_DIR/$GHIDRA_PROJECT_NAME.gpr"
