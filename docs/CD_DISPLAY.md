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
Re-import uses the existing staged installation transaction. This import work
provides the converted frames; global 16-color display selection and original
screen comparisons remain separate runtime acceptance work.
