# Macintosh CD alternate-color artwork

CD `Ima4` resources store eight-bit indexed pixels even though the original
selects them for a 16-color display. Treating their indices as ordinary 256-color
artwork gives the wrong colors. `CD16Palette` derives the authored 256-entry
index map from the supplied application's CODE23 initializer, then applies it
with Graphics 2's 16-entry `clut1004`. No original lookup table is bundled.

The initializer parser checks the CODE segment envelope, PC-relative header,
version, offsets, termination and compressed-operation bounds. Input and expanded
memory are limited to 1 MiB, nested numbers to eight levels, and each repeated
operation must fit both its literal input and destination. Pointer relocations
are not applied to the byte lookup table. Palette input must be a complete
16-entry table using ordinal entries; every mapped index must be 0–15.

Conversion preserves source identity, frame geometry and input byte ranges. PNGs
remain indexed eight-bit files with 16 used palette entries, so odd visible widths
do not inherit the original packed backing-store stride. Ordinary `Imag` frames
and classic artwork retain their existing decoding. The reference extractor
accepts an explicit `cd16_palette` context; native CD preparation derives it from
the selected application and Graphics 2 sources.

Preparation schema 7 records the corrected artwork. CD installations prepared
with schema 6 require re-import; classic schema 6 installations remain compatible.
Re-import uses the existing staged installation transaction. In the game-data library, choose CD artwork in 256 or 16 colors before pressing
Play. The choice belongs to that session and does not alter imports or saved
journeys. It defaults to 256 colors when the app starts; return to the library
from an inactive title screen to choose again.

Static artwork and title, travel, crossing, hunting and rafting scenes use the
selected resource family, retaining its type and source. Missing alternate frames
never fall back to the other family. Travel strip placement and wrapping use the
selected bitmap width; the 16-color upper strip is narrower. Hunting takes its
frame geometry from the selected family. The fixed 16-color palette bypasses the
256-color weather/season substitutions.

Monochrome presentation, original-screen comparisons and complete journey/platform
acceptance remain open requirements of the broader CD support work.
