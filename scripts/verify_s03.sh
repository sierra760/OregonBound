#!/usr/bin/env bash
# verify_s03.sh — Verify all S03 deliverables for Milestone M001
#
# Checks:
#   a. All 5 analysis .md files exist and are non-empty
#   b. Both JSON config files are valid JSON
#   c. game_loop_constants.json contains all required top-level keys
#   d. subsystem_constants.json contains all required top-level keys
#   e. Each JSON file has source/source_function references (per subsystem section)
#   f. Each analysis .md file contains an Overview section and a function table
#   g. STR# IDs explicitly referenced in analysis docs exist in assets/strings/
#   h. Total check count and pass/fail summary
#
# Exit code: 0 if all checks pass, 1 if any fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STRINGS_DIR="$REPO_ROOT/assets/strings"

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

echo "=== S03 Deliverable Verification ==="
echo ""

# --- Check (a): 5 analysis .md files exist and are non-empty ---
echo "[a] Analysis .md files"
ANALYSIS_FILES=(
    "GAME_LOOP_ANALYSIS.md"
    "HUNT_ANALYSIS.md"
    "RIVER_ANALYSIS.md"
    "SHOPPING_ANALYSIS.md"
    "ENDING_ANALYSIS.md"
)
for F in "${ANALYSIS_FILES[@]}"; do
    FPATH="$REPO_ROOT/$F"
    if [ -f "$FPATH" ]; then
        LINECOUNT=$(wc -l < "$FPATH" | tr -d ' ')
        check "$F exists and non-empty ($LINECOUNT lines)" \
            "$([ "$LINECOUNT" -gt 5 ] && echo 0 || echo 1)"
    else
        check "$F exists" 1 "file not found at $FPATH"
    fi
done
echo ""

# --- Check (b): JSON config files are valid JSON ---
echo "[b] JSON config files — valid JSON"
JSON_FILES=(
    "game_loop_constants.json"
    "subsystem_constants.json"
)
for J in "${JSON_FILES[@]}"; do
    JPATH="$REPO_ROOT/$J"
    if [ -f "$JPATH" ]; then
        ERR=$(python3 -c "import json,sys; json.load(open('$JPATH')); sys.exit(0)" 2>&1)
        check "$J is valid JSON" \
            "$([ -z "$ERR" ] && echo 0 || echo 1)" \
            "${ERR:-}"
    else
        check "$J exists" 1 "file not found"
    fi
done
echo ""

# --- Check (c): game_loop_constants.json required top-level keys ---
echo "[c] game_loop_constants.json — required top-level keys"
GLC_REQUIRED=(
    "game_initialization"
    "game_state_block_layout"
    "weather_system"
    "event_probabilities"
    "illness_system"
    "death_system"
    "supply_capacity_limits"
    "random_number_system"
)
for KEY in "${GLC_REQUIRED[@]}"; do
    PRESENT=$(python3 -c "
import json, sys
d = json.load(open('$REPO_ROOT/game_loop_constants.json'))
sys.exit(0 if '$KEY' in d else 1)
" 2>&1; echo $?)
    check "game_loop_constants.$KEY present" \
        "$([ "$PRESENT" = "0" ] && echo 0 || echo 1)"
done
echo ""

# --- Check (d): subsystem_constants.json required top-level keys ---
echo "[d] subsystem_constants.json — required top-level keys"
SC_REQUIRED=(
    "hunt_minigame"
    "river_crossing"
    "raft_crossing"
    "shopping"
    "ending_scoring"
)
for KEY in "${SC_REQUIRED[@]}"; do
    PRESENT=$(python3 -c "
import json, sys
d = json.load(open('$REPO_ROOT/subsystem_constants.json'))
sys.exit(0 if '$KEY' in d else 1)
" 2>&1; echo $?)
    check "subsystem_constants.$KEY present" \
        "$([ "$PRESENT" = "0" ] && echo 0 || echo 1)"
done
echo ""

# --- Check (e): JSON files have source references ---
echo "[e] Source references in JSON subsystem sections"

# game_loop_constants.json: check each required section has 'source' or 'source_function'
python3 - <<'PYEOF'
import json, sys
path = "game_loop_constants.json"
d = json.load(open(path))
sections = [
    "game_initialization", "game_state_block_layout", "weather_system",
    "event_probabilities", "illness_system", "death_system",
    "supply_capacity_limits", "random_number_system"
]
raw = open(path).read()
# Check that 'source' or 'source_function' keys appear anywhere in the file
has_source = '"source"' in raw or '"source_function"' in raw
print(f"  {'PASS' if has_source else 'FAIL'}: game_loop_constants.json contains source references")
sys.exit(0 if has_source else 1)
PYEOF
GLC_SRC=$?
if [ "$GLC_SRC" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

python3 - <<'PYEOF'
import json, sys
path = "subsystem_constants.json"
d = json.load(open(path))
raw = open(path).read()
has_source = '"source"' in raw or '"source_function"' in raw
print(f"  {'PASS' if has_source else 'FAIL'}: subsystem_constants.json contains source references")
sys.exit(0 if has_source else 1)
PYEOF
SC_SRC=$?
if [ "$SC_SRC" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi

# Verify each required subsystem section in both JSONs has a source somewhere inside it
python3 - <<'PYEOF'
import json, sys
fails = 0
glc = json.load(open("game_loop_constants.json"))
sc  = json.load(open("subsystem_constants.json"))

def has_source_ref(obj, depth=0):
    """Recursively check if any key 'source' or 'source_function' exists."""
    if depth > 6:
        return False
    if isinstance(obj, dict):
        if "source" in obj or "source_function" in obj:
            return True
        return any(has_source_ref(v, depth+1) for v in obj.values())
    if isinstance(obj, list):
        return any(has_source_ref(i, depth+1) for i in obj)
    return False

checks = [
    ("game_loop_constants", glc, [
        "game_initialization", "game_state_block_layout", "weather_system",
        "event_probabilities", "illness_system", "death_system",
        "supply_capacity_limits", "random_number_system"
    ]),
    ("subsystem_constants", sc, [
        "hunt_minigame", "river_crossing", "raft_crossing", "shopping", "ending_scoring"
    ]),
]
for fname, data, sections in checks:
    for section in sections:
        sec_data = data.get(section, {})
        ok = has_source_ref(sec_data)
        marker = "PASS" if ok else "FAIL"
        print(f"  {marker}: {fname}.{section} has source reference")
        if not ok:
            fails += 1

sys.exit(0 if fails == 0 else 1)
PYEOF
SEC_SRC=$?
if [ "$SEC_SRC" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
echo ""

# --- Check (f): Analysis .md files have Overview section and function table ---
echo "[f] Analysis .md files — Overview section and function table"
for F in "${ANALYSIS_FILES[@]}"; do
    FPATH="$REPO_ROOT/$F"
    if [ ! -f "$FPATH" ]; then
        check "$F — Overview section" 1 "file missing"
        check "$F — function table" 1 "file missing"
        continue
    fi

    # Overview: look for a heading line containing 'Overview'
    OVERVIEW_COUNT=$(grep -c "^## .*[Oo]verview" "$FPATH" 2>/dev/null || true)
    check "$F — has Overview section" \
        "$([ "${OVERVIEW_COUNT:-0}" -gt 0 ] && echo 0 || echo 1)" \
        "found $OVERVIEW_COUNT overview heading(s)"

    # Function table: any table row with a hex address or a FUN_ reference
    FUNC_TABLE=$(grep -c "^| 0x\|^| \`FUN_\|^| FUN_\|Function Catalogue\|Function Catalog" "$FPATH" 2>/dev/null || true)
    check "$F — has function table or catalogue" \
        "$([ "${FUNC_TABLE:-0}" -gt 0 ] && echo 0 || echo 1)" \
        "found $FUNC_TABLE matching lines"
done
echo ""

# --- Check (g): STR# IDs explicitly referenced in analysis docs exist in assets/strings/ ---
echo "[g] STR# cross-references — file references exist in assets/strings/"

# Extract all str_XXXX.json references from analysis files
ALL_STR_REFS=$(grep -oh "str_[0-9]*\.json" \
    "$REPO_ROOT/GAME_LOOP_ANALYSIS.md" \
    "$REPO_ROOT/HUNT_ANALYSIS.md" \
    "$REPO_ROOT/RIVER_ANALYSIS.md" \
    "$REPO_ROOT/SHOPPING_ANALYSIS.md" \
    "$REPO_ROOT/ENDING_ANALYSIS.md" 2>/dev/null | sort -u)

if [ -z "$ALL_STR_REFS" ]; then
    check "No explicit str_XXXX.json references found in analysis docs" 1 \
        "expected at least str_3014.json reference"
else
    STR_FAIL=0
    while IFS= read -r STR_FILE; do
        STR_PATH="$STRINGS_DIR/$STR_FILE"
        if [ -f "$STR_PATH" ]; then
            check "$STR_FILE referenced in analysis docs exists in assets/strings/" 0
        else
            check "$STR_FILE referenced in analysis docs exists in assets/strings/" 1 \
                "not found at $STR_PATH"
            STR_FAIL=$((STR_FAIL + 1))
        fi
    done <<< "$ALL_STR_REFS"
fi

# Specifically confirm str_3014.json (month names, used by ENDING_ANALYSIS.md + scoring)
check "str_3014.json (month names — required by ending/scoring) exists" \
    "$([ -f "$STRINGS_DIR/str_3014.json" ] && echo 0 || echo 1)"
echo ""

# --- Summary ---
TOTAL_CHECKS=$((PASS + FAIL))
echo "=== Summary ==="
echo "  Passed: $PASS / $TOTAL_CHECKS"
echo "  Failed: $FAIL / $TOTAL_CHECKS"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "ALL CHECKS PASSED — S03 deliverables verified."
    exit 0
else
    echo "SOME CHECKS FAILED — review output above."
    exit 1
fi
