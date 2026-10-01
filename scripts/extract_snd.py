#!/usr/bin/env python3
"""
extract_snd.py — Extract Mac snd resources from Oregon Trail resource fork to WAV.

Mac snd resource format reference:
  - Format 1: 2-byte format id (0x0001), synth list, command list, then sound data
  - soundCmd/bufferCmd (0x0050/0x0051 | 0x8000): param2 = SoundHeader offset
  - SoundHeader (stdSH, encode=0): 4B samplePtr, 4B length, 4B sampleRate (Fixed 16.16),
    4B loopStart, 4B loopEnd, 1B encode, 1B baseFrequency, then inline 8-bit unsigned PCM

All 6 snd resources in Oregon Trail (IDs 9001-9004, 9006, 9007) use Format 1 / stdSH.
Audio is 8-bit unsigned mono PCM; sample rates are submultiples of Mac 22254.5 Hz.
"""

import json
import os
import struct
import wave
import macresources

RAW_FILE = "raw/oregon_trail.rsrc"
INVENTORY_FILE = "assets/resource_inventory.json"
OUTPUT_DIR = "assets/sounds"


def parse_snd_format1(data: bytes) -> tuple[int, int, bytes]:
    """Parse a Format 1 Mac snd resource.

    Returns:
        (sample_rate_hz, bits_per_sample, pcm_data)

    Raises:
        ValueError if the resource cannot be parsed or is not stdSH.
    """
    if len(data) < 6:
        raise ValueError("snd resource too short")

    fmt = struct.unpack_from(">H", data, 0)[0]
    if fmt != 1:
        raise ValueError(f"Unsupported snd format: {fmt:#06x} (only Format 1 supported)")

    num_synths = struct.unpack_from(">H", data, 2)[0]
    # Each synth entry: 2-byte id + 4-byte initOption = 6 bytes
    offset = 4 + num_synths * 6

    if offset + 2 > len(data):
        raise ValueError("snd command count is truncated")
    num_cmds = struct.unpack_from(">H", data, offset)[0]
    offset += 2
    if offset + num_cmds * 8 > len(data):
        raise ValueError("snd command list is truncated")

    hdr_offset = None
    for _ in range(num_cmds):
        cmd, _p1, p2 = struct.unpack_from(">HHI", data, offset)
        offset += 8
        # CD 1.2 includes both standard sampled-sound command forms.
        if (cmd & 0x7FFF) in (0x0050, 0x0051):
            if not cmd & 0x8000:
                raise ValueError("snd sample command must use a resource offset, not a pointer")
            hdr_offset = p2
            break

    if hdr_offset is None:
        raise ValueError("No sampled-sound command found in snd resource")

    # SoundHeader layout at hdr_offset:
    #   0: samplePtr  (4B) — pointer; 0 means samples follow inline
    #   4: length     (4B) — sample count (bytes for 8-bit)
    #   8: sampleRate (4B) — Fixed 16.16 unsigned
    #  12: loopStart  (4B)
    #  16: loopEnd    (4B)
    #  20: encode     (1B) — 0=stdSH, 0xFF=extSH, 0xFE=cmpSH
    #  21: baseFreq   (1B)
    #  22: sampleArea (length bytes) if samplePtr == 0
    if hdr_offset + 22 > len(data):
        raise ValueError(f"SoundHeader at {hdr_offset} truncated (resource length={len(data)})")

    sample_ptr, length, sr_fixed, loop_start, loop_end = struct.unpack_from(
        ">IIIII", data, hdr_offset
    )
    encode = data[hdr_offset + 20]

    if encode != 0x00:
        raise ValueError(
            f"Unsupported SoundHeader encoding: {encode:#04x} (only stdSH=0x00 supported)"
        )

    # Convert Fixed 16.16 to Hz (round to nearest integer for WAV header)
    sample_rate_hz = round(sr_fixed / 65536.0)

    # Extract inline PCM samples
    samples_start = hdr_offset + 22
    samples_end = samples_start + length
    if samples_end > len(data):
        print(
            f"  Warning: declared length {length} exceeds resource bounds "
            f"({len(data) - samples_start} bytes available); truncating"
        )
        samples_end = len(data)
    pcm_data = data[samples_start:samples_end]

    return sample_rate_hz, 8, pcm_data


def write_wav(path: str, sample_rate: int, bits: int, pcm: bytes) -> None:
    """Write a WAV file with 8-bit mono PCM."""
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)          # mono
        wf.setsampwidth(bits // 8)  # bytes per sample (1 for 8-bit)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm)


def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Load resource fork
    with open(RAW_FILE, "rb") as f:
        raw = f.read()
    resources = macresources.parse_file(raw)
    snd_resources = sorted(
        [r for r in resources if r.type == b"snd "], key=lambda r: r.id
    )

    print(f"Found {len(snd_resources)} snd resources")

    output_paths: dict[int, str] = {}
    for r in snd_resources:
        data = bytes(r)
        out_path = os.path.join(OUTPUT_DIR, f"snd_{r.id}.wav")
        print(f"  Extracting ID={r.id} name={r.name!r} ({len(data)} bytes) -> {out_path}")
        try:
            sample_rate, bits, pcm = parse_snd_format1(data)
            write_wav(out_path, sample_rate, bits, pcm)
            size = os.path.getsize(out_path)
            print(
                f"    OK: {len(pcm)} samples @ {sample_rate} Hz, {bits}-bit mono "
                f"-> {size} bytes WAV"
            )
            output_paths[r.id] = out_path
        except ValueError as e:
            print(f"    ERROR: {e}")
            raise

    # Update resource inventory output_path fields
    with open(INVENTORY_FILE) as f:
        inventory = json.load(f)

    updated = 0
    for entry in inventory:
        if entry.get("type") == "snd " and entry.get("id") in output_paths:
            entry["output_path"] = output_paths[entry["id"]]
            updated += 1

    with open(INVENTORY_FILE, "w") as f:
        json.dump(inventory, f, indent=2)
    print(f"\nUpdated {updated} inventory entries with output_path")

    # Final summary
    wavs = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".wav")]
    print(f"\nTotal WAV files in {OUTPUT_DIR}: {len(wavs)}")
    for name in sorted(wavs):
        size = os.path.getsize(os.path.join(OUTPUT_DIR, name))
        print(f"  {name}: {size} bytes")


if __name__ == "__main__":
    main()
