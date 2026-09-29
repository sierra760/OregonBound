#!/usr/bin/env bash
# verify_s02.sh — Verify all S02 deliverables for Milestone M001
#
# Checks:
#   1. 22 .bin files in assets/code_segments/
#   2. code_metadata.json exists with 22 entries
#   3. Ghidra project exists (OregonBound.gpr and OregonBound.rep)
#   4. Pseudocode files exist for all 22 CODE segments
#   5. Pseudocode files exist for key modules: Main, Game, Hunt, Raft, River, Buy, Model, Display, Ending
#   6. function_boundaries.json exists with entries for key modules
#   7. WST# JSON files (21 entries), HVof JSON files (8 entries), ORGN JSON (1 entry) still present
#
# Exit code: 0 if all checks pass, 1 if any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CODE_SEGMENTS_DIR="$REPO_ROOT/assets/code_segments"
PSEUDOCODE_DIR="$REPO_ROOT/assets/pseudocode"
GHIDRA_DIR="$REPO_ROOT/ghidra"
GUIDEBOOK_DIR="$REPO_ROOT/assets/guidebook"
MAP_VIEWPORTS_DIR="$REPO_ROOT/assets/map_viewports"
METADATA_DIR="$REPO_ROOT/assets/metadata"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"  # 0=pass, 1=fail
    local detail="${3:-}"
    if [ "$result" -eq 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc${detail:+ — $detail}"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== S02 Deliverable Verification ==="
echo ""

# --- Check 1: 22 .bin files in assets/code_segments/ ---
echo "[1] CODE segment binaries"
BIN_COUNT=$(find "$CODE_SEGMENTS_DIR" -name "*.bin" 2>/dev/null | wc -l | tr -d ' ')
check "22 .bin files in assets/code_segments/" \
    "$([ "$BIN_COUNT" -eq 22 ] && echo 0 || echo 1)" \
    "found $BIN_COUNT"

# Check specific key bins
for SEG in CODE_0_JumpTable CODE_1_Main CODE_12_Game CODE_13_Hunt CODE_17_Raft CODE_18_River CODE_7_Buy CODE_16_Model; do
    BIN="$CODE_SEGMENTS_DIR/${SEG}.bin"
    check "$SEG.bin exists" "$([ -f "$BIN" ] && echo 0 || echo 1)"
done
echo ""

# --- Check 2: code_metadata.json with 22 entries ---
echo "[2] code_metadata.json"
METADATA="$CODE_SEGMENTS_DIR/code_metadata.json"
if [ -f "$METADATA" ]; then
    META_COUNT=$(python3 -c "import json; data=json.load(open('$METADATA')); print(len(data))" 2>/dev/null)
    check "code_metadata.json exists" 0
    check "code_metadata.json has 22 entries" \
        "$([ "$META_COUNT" = "22" ] && echo 0 || echo 1)" \
        "found $META_COUNT"
else
    check "code_metadata.json exists" 1
    check "code_metadata.json has 22 entries" 1 "file missing"
fi
echo ""

# --- Check 3: Ghidra project ---
echo "[3] Ghidra project"
check "ghidra/OregonBound.gpr exists" \
    "$([ -f "$GHIDRA_DIR/OregonBound.gpr" ] && echo 0 || echo 1)"
check "ghidra/OregonBound.rep directory exists" \
    "$([ -d "$GHIDRA_DIR/OregonBound.rep" ] && echo 0 || echo 1)"
echo ""

# --- Check 4: Pseudocode for all 22 segments ---
echo "[4] Pseudocode files (all 22 segments)"
ALL_SEGS=(JumpTable Main About Main2 Attract Display Main3 Buy Config Init Ending Export Game Hunt Message Management Model Raft River Startup UnPack A5Init)
for SEG in "${ALL_SEGS[@]}"; do
    F="$PSEUDOCODE_DIR/${SEG}.c"
    check "${SEG}.c exists" "$([ -f "$F" ] && echo 0 || echo 1)"
done
echo ""

# --- Check 5: Key module pseudocode ---
echo "[5] Key module pseudocode"
KEY_MODULES=(Main Game Hunt Raft River Buy Model Display Ending)
for MOD in "${KEY_MODULES[@]}"; do
    F="$PSEUDOCODE_DIR/${MOD}.c"
    if [ -f "$F" ]; then
        LINE_COUNT=$(wc -l < "$F" | tr -d ' ')
        check "$MOD.c exists and non-empty ($LINE_COUNT lines)" \
            "$([ "$LINE_COUNT" -gt 1 ] && echo 0 || echo 1)"
    else
        check "$MOD.c exists" 1
    fi
done
echo ""

# --- Check 6: function_boundaries.json ---
echo "[6] function_boundaries.json"
FB_JSON="$CODE_SEGMENTS_DIR/function_boundaries.json"
if [ -f "$FB_JSON" ]; then
    check "function_boundaries.json exists" 0
    # Check key modules have entries
    for MOD in Main Game Hunt Raft River Buy Model Display Ending; do
        COUNT=$(python3 -c "
import json
data=json.load(open('$FB_JSON'))
segs=data.get('segments', {})
print(len(segs.get('$MOD', [])))
" 2>/dev/null)
        check "function_boundaries.json.$MOD has functions" \
            "$([ -n "$COUNT" ] && [ "$COUNT" -gt 0 ] && echo 0 || echo 1)" \
            "$COUNT functions"
    done
    # Check total
    TOTAL=$(python3 -c "import json; d=json.load(open('$FB_JSON')); print(d.get('summary',{}).get('total_functions',0))" 2>/dev/null)
    check "function_boundaries.json total_functions > 100" \
        "$([ -n "$TOTAL" ] && [ "$TOTAL" -gt 100 ] && echo 0 || echo 1)" \
        "total=$TOTAL"
else
    check "function_boundaries.json exists" 1
fi
echo ""

# --- Check 7: Prior work (WST#, HVof, ORGN) ---
echo "[7] Prior resource JSON files"
WST_COUNT=$(find "$GUIDEBOOK_DIR" -name "wst_*.json" 2>/dev/null | wc -l | tr -d ' ')
HVOF_COUNT=$(find "$MAP_VIEWPORTS_DIR" -name "hvof_*.json" 2>/dev/null | wc -l | tr -d ' ')
ORGN_COUNT=$(find "$METADATA_DIR" -name "orgn.json" 2>/dev/null | wc -l | tr -d ' ')
check "WST# JSON files present in assets/guidebook/ (expect 21)" \
    "$([ "$WST_COUNT" -eq 21 ] && echo 0 || echo 1)" \
    "found $WST_COUNT"
check "HVof JSON files present in assets/map_viewports/ (expect 8)" \
    "$([ "$HVOF_COUNT" -eq 8 ] && echo 0 || echo 1)" \
    "found $HVOF_COUNT"
check "ORGN JSON file present in assets/metadata/ (expect 1)" \
    "$([ "$ORGN_COUNT" -ge 1 ] && echo 0 || echo 1)" \
    "found $ORGN_COUNT"
echo ""

# --- Summary ---
TOTAL_CHECKS=$((PASS + FAIL))
echo "=== Summary ==="
echo "  Passed: $PASS / $TOTAL_CHECKS"
echo "  Failed: $FAIL / $TOTAL_CHECKS"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "ALL CHECKS PASSED — S02 deliverables verified."
    exit 0
else
    echo "SOME CHECKS FAILED — review output above."
    exit 1
fi
