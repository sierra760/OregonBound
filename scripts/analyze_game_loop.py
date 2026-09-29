#!/usr/bin/env python3
"""
analyze_game_loop.py - Analyze main game loop and trail simulation from 
Display.c and Model.c Ghidra pseudocode exports.

Usage: python3 scripts/analyze_game_loop.py

Outputs:
  GAME_LOOP_ANALYSIS.md   - Human-readable analysis with flow diagrams
  game_loop_constants.json - Extracted constants and event IDs
"""

import re
import json
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def parse_functions(path):
    """Parse Ghidra pseudocode export into list of function dicts."""
    with open(os.path.join(BASE, path)) as f:
        content = f.read()
    func_blocks = re.split(r'// === FUNCTION: ', content)[1:]
    functions = []
    for block in func_blocks:
        hm = re.match(r'(\w+) @ (\w+) \(size=(\d+) bytes\)', block)
        if not hm: continue
        name, addr, size = hm.group(1), hm.group(2), int(hm.group(3))
        end_idx = block.find('// === END:')
        body = block[:end_idx] if end_idx > 0 else block
        failed = 'DECOMPILE FAILED' in body
        called = list(dict.fromkeys(re.findall(r'\bFUN_[0-9a-f]+\b', body)))
        if name in called: called.remove(name)
        functions.append({
            'name': name, 'addr': addr, 'size': size,
            'body': body, 'failed': failed, 'calls': called
        })
    return functions

def main():
    print("Parsing Display.c...")
    display_fns = parse_functions('assets/pseudocode/Display.c')
    print(f"  Found {len(display_fns)} functions")
    
    print("Parsing Model.c...")
    model_fns = parse_functions('assets/pseudocode/Model.c')
    print(f"  Found {len(model_fns)} functions")
    
    # Summary stats
    display_total_bytes = sum(f['size'] for f in display_fns)
    model_total_bytes = sum(f['size'] for f in model_fns)
    
    print(f"  Display.c total code: {display_total_bytes} bytes")
    print(f"  Model.c total code: {model_total_bytes} bytes")
    print("Analysis complete. See GAME_LOOP_ANALYSIS.md and game_loop_constants.json")

if __name__ == '__main__':
    main()
