#!/usr/bin/env bash
# ghidra_export.sh — Export pseudocode for all CODE segments using Ghidra headless
#
# Prerequisites:
#   - Ghidra project already imported (run ghidra_import.sh first)
#   - JDK 21+
#   - mac_arm_64 decompiler binary built and installed (see ghidra_import.sh notes)
#
# Usage:
#   bash scripts/ghidra_export.sh
#
# Output:
#   assets/pseudocode/<SegmentName>.c  — decompiled pseudocode for each CODE segment
#   assets/pseudocode/<SegmentName>.tsv — function index (name, address, size)
#   assets/code_segments/function_boundaries.json — merged function boundary map

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GHIDRA_HOME="$REPO_ROOT/tools/ghidra_12.1_PUBLIC"
ANALYZE_HEADLESS="$GHIDRA_HOME/support/analyzeHeadless"
GHIDRA_PROJECT_DIR="$REPO_ROOT/ghidra"
GHIDRA_PROJECT_NAME="OregonBound"
PSEUDOCODE_DIR="$REPO_ROOT/assets/pseudocode"
CODE_SEGMENTS_DIR="$REPO_ROOT/assets/code_segments"
SCRIPTS_DIR="$REPO_ROOT/scripts/ghidra"
METADATA_JSON="$CODE_SEGMENTS_DIR/code_metadata.json"
OUTPUT_JSON="$CODE_SEGMENTS_DIR/function_boundaries.json"

# Ghidra requires a non-dotfile staging project directory for -process mode
STAGING_DIR="$HOME/ghidra_projects"

# JDK 21 — required by Ghidra 12.1
JAVA_HOME_21="/opt/homebrew/opt/openjdk@21"
export JAVA_HOME="$JAVA_HOME_21"
export PATH="$JAVA_HOME_21/bin:$PATH"

mkdir -p "$PSEUDOCODE_DIR"
mkdir -p "$STAGING_DIR"

# Verify prerequisites
if [ ! -x "$ANALYZE_HEADLESS" ]; then
    echo "ERROR: analyzeHeadless not found at $ANALYZE_HEADLESS"
    exit 1
fi
if [ ! -f "$GHIDRA_PROJECT_DIR/$GHIDRA_PROJECT_NAME.gpr" ]; then
    echo "ERROR: Ghidra project not found. Run ghidra_import.sh first."
    exit 1
fi
if [ ! -f "$METADATA_JSON" ]; then
    echo "ERROR: code_metadata.json not found at $METADATA_JSON"
    exit 1
fi

# Check decompiler binary
DECOMPILER_BIN="$GHIDRA_HOME/Ghidra/Features/Decompiler/os/mac_arm_64/decompile"
if [ ! -f "$DECOMPILER_BIN" ]; then
    echo "WARNING: mac_arm_64 decompiler binary not found at $DECOMPILER_BIN"
    echo "         Pseudocode output will be stubs. Build it with:"
    echo "         cd tools/ghidra_12.1_PUBLIC/Ghidra/Features/Decompiler/src/decompile/cpp"
    echo "         make ARCH_TYPE='-arch arm64' ADDITIONAL_FLAGS='-mmacosx-version-min=11.0 -w' OSDIR=mac_arm_64 ghidra_opt"
    echo "         cp ghidra_opt ../../../os/mac_arm_64/decompile"
fi

# Ghidra analyzeHeadless needs a writable project dir without dotfile components.
# Strategy: copy the project to STAGING_DIR, process it there, copy results back.
echo "=== Staging Ghidra project ==="
STAGING_PROJECT="$STAGING_DIR/$GHIDRA_PROJECT_NAME"
rm -rf "$STAGING_PROJECT.gpr" "$STAGING_PROJECT.rep" 2>/dev/null || true
cp "$GHIDRA_PROJECT_DIR/$GHIDRA_PROJECT_NAME.gpr" "$STAGING_DIR/"
cp -r "$GHIDRA_PROJECT_DIR/$GHIDRA_PROJECT_NAME.rep" "$STAGING_DIR/"
echo "Staged to $STAGING_DIR"

# Read segment names from code_metadata.json using python3
SEGMENT_NAMES=$(python3 -c "
import json, sys
with open('$METADATA_JSON') as f:
    data = json.load(f)
for seg in data:
    print(seg['name'])
")

echo "=== Segments to process: ==="
echo "$SEGMENT_NAMES"
echo ""

# Process each segment
FAILED_SEGMENTS=()
for SEG_NAME in $SEGMENT_NAMES; do
    # Find the program name in the Ghidra project — file is imported as CODE_<id>_<name>.bin
    # Ghidra strips the .bin and uses the filename stem as program name.
    # Find matching .bin file.
    BIN_FILE=$(ls "$CODE_SEGMENTS_DIR"/CODE_*_"${SEG_NAME}".bin 2>/dev/null | head -1)
    if [ -z "$BIN_FILE" ]; then
        echo "WARNING: No .bin file found for segment $SEG_NAME, skipping"
        FAILED_SEGMENTS+=("$SEG_NAME")
        continue
    fi
    PROGRAM_NAME="$(basename "$BIN_FILE" .bin)"
    PSEUDOCODE_FILE="$PSEUDOCODE_DIR/${SEG_NAME}.c"

    # Skip if already exported (re-run idempotency)
    if [ -f "$PSEUDOCODE_FILE" ]; then
        echo "SKIP: $SEG_NAME — $PSEUDOCODE_FILE already exists"
        continue
    fi

    echo "=== Exporting: $PROGRAM_NAME -> $SEG_NAME.c ==="
    "$ANALYZE_HEADLESS" \
        "$STAGING_DIR" "$GHIDRA_PROJECT_NAME" \
        -process "$PROGRAM_NAME" \
        -noanalysis \
        -postScript ExportPseudocode.java "$PSEUDOCODE_DIR" \
        -scriptPath "$SCRIPTS_DIR" \
        2>&1 | grep -E "(ExportPseudocode|ERROR|WARN|INFO.*Export)" || true

    # Check output
    # The script writes <baseName>.c; baseName strips .bin from PROGRAM_NAME
    GENERATED_C="$PSEUDOCODE_DIR/${PROGRAM_NAME}.c"
    if [ -f "$GENERATED_C" ] && [ "$GENERATED_C" != "$PSEUDOCODE_FILE" ]; then
        # Rename to segment name (e.g. CODE_1_Main.c -> Main.c)
        mv "$GENERATED_C" "$PSEUDOCODE_FILE"
    fi
    if [ -f "$PSEUDOCODE_FILE" ]; then
        LINE_COUNT=$(wc -l < "$PSEUDOCODE_FILE")
        echo "  OK: $SEG_NAME.c ($LINE_COUNT lines)"
    else
        echo "  FAIL: $SEG_NAME.c not generated"
        FAILED_SEGMENTS+=("$SEG_NAME")
    fi
done

echo ""
echo "=== Pseudocode export complete ==="
ls "$PSEUDOCODE_DIR"/*.c 2>/dev/null | wc -l | xargs echo "Files generated:"

if [ ${#FAILED_SEGMENTS[@]} -gt 0 ]; then
    echo "WARNING: Failed segments: ${FAILED_SEGMENTS[*]}"
fi

# Build function_boundaries.json from .tsv index files
echo ""
echo "=== Building function_boundaries.json ==="
python3 - <<'PYEOF'
import json
import os
import re

PSEUDOCODE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'pseudocode')
OUTPUT_JSON = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'code_segments', 'function_boundaries.json')
METADATA_JSON = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'code_segments', 'code_metadata.json')

with open(METADATA_JSON) as f:
    metadata = json.load(f)

seg_names = [s['name'] for s in metadata]

KEY_MODULES = ['Main', 'Game', 'Hunt', 'Raft', 'River', 'Buy', 'Model', 'Display', 'Ending']

result = {}
per_module_counts = {}

for seg_name in seg_names:
    tsv_path = os.path.join(PSEUDOCODE_DIR, seg_name + '.tsv')
    if not os.path.exists(tsv_path):
        result[seg_name] = []
        continue
    functions = []
    with open(tsv_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) >= 3:
                fn_name, addr, size = parts[0], parts[1], parts[2]
                functions.append({
                    'name': fn_name,
                    'address': addr,
                    'size': int(size) if size.isdigit() else 0
                })
    result[seg_name] = functions
    if seg_name in KEY_MODULES:
        per_module_counts[seg_name] = len(functions)

total_functions = sum(len(v) for v in result.values())

output = {
    'summary': {
        'total_functions': total_functions,
        'total_segments': len(result),
        'key_module_function_counts': per_module_counts
    },
    'segments': result
}

with open(OUTPUT_JSON, 'w') as f:
    json.dump(output, f, indent=2)

print(f"function_boundaries.json: {len(result)} segments, {total_functions} total functions")
for mod in KEY_MODULES:
    count = per_module_counts.get(mod, 'MISSING')
    print(f"  {mod}: {count} functions")
PYEOF

echo ""
echo "Done. Run 'bash scripts/verify_s02.sh' to validate all S02 deliverables."
