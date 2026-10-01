# Macintosh CD raster pictures

The importer decodes the CD application's monochrome picture 256 and indexed
pictures 501 and 10256 into source-qualified PNGs. Resource provenance, original
lengths, and byte ranges continue to refer to the supplied input.

The supplied CD About picture contains a duplicated 16-byte prefix at the start
of its legacy version-2 HeaderOp. The decoder removes that prefix only when both
copies match and the remaining complete 24-byte header contains the legacy
version marker, fixed-point bounds matching the picture frame, and a zero reserved
field. It records `pict.duplicate_legacy_header` as an informational diagnostic.
The rest of the picture must still pass the complete opcode, rectangle, palette,
PackBits-row and end-marker checks. It never searches for a bitmap opcode to
skip unknown drawing commands.

This is a compatibility repair for the supplied source format. It does not claim
to reproduce QuickDraw's undocumented tolerance of the original malformed header.
The recovered logo was compared visually with the running CD application's About
screen. Python and Swift pixel equality is checked separately using private
user-supplied input; no original resource or screenshot is distributed here.

Re-import a CD installation prepared by an older decoder to obtain this picture.
Existing installations with the explicitly preserved pending picture remain
loadable; that compatibility does not turn their pending bytes into decoded art.
