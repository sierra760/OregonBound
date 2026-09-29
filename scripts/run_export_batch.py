#!/usr/bin/env python3
"""
run_export_batch.py — Batch pseudocode export for all CODE segments.
Runs analyzeHeadless -process for each segment not yet exported.
"""
import subprocess
import json
import os
import sys
import shutil

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GHIDRA_HOME = os.path.join(BASE, "tools", "ghidra_12.1_PUBLIC")
ANALYZE_HEADLESS = os.path.join(GHIDRA_HOME, "support", "analyzeHeadless")
STAGING_DIR = os.path.expanduser("~/ghidra_projects")
PROJECT_NAME = "OregonBound"
PSEUDOCODE_DIR = os.path.join(BASE, "assets", "pseudocode")
CODE_SEGMENTS_DIR = os.path.join(BASE, "assets", "code_segments")
SCRIPTS_DIR = os.path.join(BASE, "scripts", "ghidra")
METADATA_JSON = os.path.join(CODE_SEGMENTS_DIR, "code_metadata.json")

JAVA_HOME = "/opt/homebrew/opt/openjdk@21"

env = os.environ.copy()
env["JAVA_HOME"] = JAVA_HOME
env["PATH"] = f"{JAVA_HOME}/bin:{env.get('PATH', '')}"

os.makedirs(PSEUDOCODE_DIR, exist_ok=True)

with open(METADATA_JSON) as f:
    metadata = json.load(f)

# Find all .bin files
bin_files = {os.path.basename(p): p for p in
             [os.path.join(CODE_SEGMENTS_DIR, x) for x in os.listdir(CODE_SEGMENTS_DIR) if x.endswith('.bin')]}

results = {}

for seg in metadata:
    seg_name = seg['name']
    seg_id = seg['id']

    output_c = os.path.join(PSEUDOCODE_DIR, f"{seg_name}.c")

    if os.path.exists(output_c):
        print(f"SKIP: {seg_name}.c already exists")
        results[seg_name] = 'skipped'
        continue

    # Find the .bin file for this segment
    bin_key = None
    for k in bin_files:
        # e.g. CODE_1_Main.bin
        if f"CODE_{seg_id}_{seg_name}.bin" == k:
            bin_key = k
            break

    if bin_key is None:
        print(f"FAIL: No .bin found for CODE_{seg_id}_{seg_name}")
        results[seg_name] = 'no_bin'
        continue

    # Run analyzeHeadless -process
    program_name = bin_key  # e.g. CODE_1_Main.bin (with extension as stored in project)
    print(f"Processing: {seg_name} ({program_name})...")

    cmd = [
        ANALYZE_HEADLESS,
        STAGING_DIR, PROJECT_NAME,
        "-process", program_name,
        "-noanalysis",
        "-postScript", "ExportPseudocode.java", PSEUDOCODE_DIR,
        "-scriptPath", SCRIPTS_DIR,
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=90, env=env)
        combined = result.stdout + result.stderr

        # The script writes <stem>.c (strips extension from program_name)
        stem = program_name
        if stem.endswith('.bin'):
            stem = stem[:-4]
        generated_c = os.path.join(PSEUDOCODE_DIR, f"{stem}.c")
        generated_tsv = os.path.join(PSEUDOCODE_DIR, f"{stem}.tsv")

        if os.path.exists(generated_c):
            # Rename to segment name
            os.rename(generated_c, output_c)
            target_tsv = os.path.join(PSEUDOCODE_DIR, f"{seg_name}.tsv")
            if os.path.exists(generated_tsv):
                os.rename(generated_tsv, target_tsv)
            line_count = sum(1 for _ in open(output_c))
            print(f"  OK: {seg_name}.c ({line_count} lines)")
            results[seg_name] = 'ok'
        else:
            # Check log for errors
            relevant = [l for l in combined.split('\n') if 'ERROR' in l or 'ExportPseudocode' in l]
            print(f"  FAIL: {seg_name}.c not generated")
            for l in relevant[-5:]:
                print(f"    {l}")
            results[seg_name] = 'fail'
    except subprocess.TimeoutExpired:
        print(f"  TIMEOUT: {seg_name}")
        results[seg_name] = 'timeout'
    except Exception as e:
        print(f"  EXCEPTION: {seg_name}: {e}")
        results[seg_name] = 'exception'

print("\n=== Results ===")
for k, v in results.items():
    print(f"  {k}: {v}")

ok_count = sum(1 for v in results.values() if v in ('ok', 'skipped'))
total = len(results)
print(f"\nTotal: {ok_count}/{total} exported successfully")
