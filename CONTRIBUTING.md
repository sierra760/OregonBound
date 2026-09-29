# Contributing

## Ground rules

- **Never commit original material.** No files from *The Oregon Trail*, no extracted graphics, text, fonts or sounds, no System 7 resources, no screen captures of the original, and no disassembly or pseudocode. `.gitignore` blocks the usual locations; `scripts/export_public_repo.py` documents what the public tree may contain. Test fixtures must be synthetic.
- **Rules need evidence.** A gameplay or rendering change should cite where the behavior comes from: an offset in the original code, a resource, or a capture, recorded in the change description. Document deliberate behavior changes there and in the relevant code comment.
- **Keep Python and Swift decoders in lockstep.** The Python scripts in `scripts/` are the reference; the Swift importer in `OregonBound/OregonBound/Data/` must reproduce their output exactly. Change both, then run `scripts/verify_swift_import.py`.

## Workflow

1. `xcodegen generate --spec OregonBound/project.yml` after adding or removing files.
2. Run the Swift tests on macOS and build the iPad scheme; run `python3 -m pytest -q`.
3. For decoder changes: build, `"Oregon Bound" --import … --output /tmp/oregon-data`, then `python3 scripts/verify_swift_import.py /tmp/oregon-data` in a checkout where the Python pipeline has produced `assets/`.
4. For rendering changes: add or update an `ImageRenderer`-based comparison in `OregonBoundTests/` and describe the measured regions in the change description.

## Style

- Swift 5.9, Foundation-only in `Data/` and `Engine/` (no AppKit/UIKit) so the code builds for both platforms and can be tested without a window.
- Integer arithmetic where the original used it; cite the offset that justifies each constant.
- Types implementing recovered behavior are prefixed `Original`; infrastructure types are not.
- Short, factual comments about format facts and evidence; no narrative.
