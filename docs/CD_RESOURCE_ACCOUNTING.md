# CD resource-family accounting

This table describes the 58 resource families in the supported CD application's
required companions and optional On-line User’s Guide. It separates decoded
game content from the original Macintosh application machinery and unresolved
ancillary material. It is a family-level map, not a claim of full visual or
interactive equivalence. The source-qualified catalog also records every
individual resource's identity, size, and hash.

| Families | Treatment in Oregon Bound |
| --- | --- |
| `Imag`, `Ima4` | Frames decoded in all three supported display modes; explicit source/ID selection and six declared empty placeholders. Additional frames with no recovered load site remain in the prepared data. |
| `cicn`, `ICON` | Game control and scene icons decoded; manual application chrome is implemented with native controls. |
| `PICT` | Game raster/text pictures and manual page, caption, and paper pictures decoded through their respective paths. Legacy reader dialog artwork is not a new game scene. |
| `clut` | Original color tables feed the graphics decoders and CD 16-color conversion. |
| `snd ` | All 175 game/guide recordings decoded with original sample-rate metadata; explicit playback mappings are documented in CD development notes. |
| `STR#`, `WST#`, `HVof`, `DITL` | Game strings, guide text, map viewports, and dialog contents decoded. The manual's section labels come from its own string table; its application chrome is implemented natively. |
| `TEXT`, `styl` | Game About credits decoded as text and style runs. The manual application's own About text is application metadata, separate from its PICT document pages. |
| `FOND`, `NFNT` | Game font associations and bitmap strikes decoded; selected optional System fonts supply classic controls and manual typography. |
| `CONF` | Edition-specific preference and initial Legends data decoded; changes persist in native edition-specific storage. |
| `TERR`, `Scpt` | Hunting terrain and the river animation program decoded for native simulation/presentation. |
| `PMAP`, `SCNM`, `RECT` | Manual page order, section ranges, and link/caption regions decoded. The empty unreferenced RECT record is inventoried, not a fabricated extra page. |
| `OTCD`, `OTSG`, `vers`, `Hypp` | Source/version identity and publisher markers. OTCD text is extracted as metadata; the source classifier uses the relevant markers. These are not additional playable scenes. |
| `MECC` | Original publisher contact/registration bookkeeping. Native application identity, information, and local persistence replace this application infrastructure; original publisher contact services are not recreated. |
| `CODE`, `CDEF`, `LDEF`, `WDEF` | Original executable, control, list, and window implementations. Native Swift code implements the recovered behavior; original executable resources are not run. |
| `CNTL`, `DLOG`, `ALRT`, `WIND`, `MBAR`, `MENU` | Classic control/window/menu definitions. Native views and commands implement the game and manual controls; these definitions are not treated as standalone graphics. |
| `CURS`, `acur` | The game's hunting cursor is extracted. Manual pointer/busy-cursor presentation uses native interaction; its cursor resources remain inventoried. |
| `pltt`, `cctb`, `wctb`, `dctb` | Classic palette and control/window/dialog color-table metadata. Prepared scene pixels use decoded graphics palettes; native chrome supplies the platform presentation. |
| `BNDL`, `FREF`, `ICN#`, `icl4`, `icl8`, `ics#`, `ics4`, `ics8` | Finder application/document associations and icon variants. Oregon Bound uses its own bundle identity and app icon. These are not in-game `ICON` resources. |
| `SIZE`, `TMPL` | Classic application memory configuration and resource-editor templates. Inventoried; native memory management and decoders replace those roles. |
| `DLGX` | Resorcerer dialog-editor metadata, including editing grids and margins. Inventoried; no game runtime decoder is required. This uppercase type is distinct from Apple's lowercase `dlgx` dialog extension. |
| `hfdr`, `hmnu` | Classic Finder/menu Balloon Help metadata. Native help commands and accessibility are the intended treatment; exact text/interaction equivalence has not been certified. |
| `PTHN`, `MNTY` | A second credits text/style pair. Structurally identified and inventoried; not decoded into a native screen. No explicit program load site was found. |
| `Crul` | Ancillary reader metadata, with full semantics still unresolved. Inventoried; no explicit program load site was found and no native feature is inferred from its presence. |

## Dialog-editor metadata

The resource editor publisher's [Resorcerer demo](https://www.mathemaesthetics.com/DemoPage.html)
contains separate type labels for uppercase `DLGX` editor extensions and lowercase
`dlgx` dialog extensions. Its editor preferences and help describe `DLGX` storage
for per-dialog editing information, including grids and margins.

A local comparison of the [publisher's archive](https://www.mathemaesthetics.com/download/Res24OSXDemo.sit)
finds the same structure in its 11 uppercase records and the game's three records:
an 82-byte header followed by 12 bytes per item. The game records' counts match
their corresponding dialog item lists. Together with the publisher's identified
role and the loader audit below, this accounts for `DLGX` as editing metadata.
Individual editor flags need not be decoded into game features. This finding
does not resolve `Crul` or the alternate credits, or close foreground acceptance.

## Explicit loader audit

A local audit of the supplied game and manual examines all 40 `CODE`, `CDEF`,
`LDEF`, and `WDEF` resources, including their jump tables. It checks aligned raw
trap words against instruction boundaries, then verifies each type push and the
remaining argument-stack width. It finds 97 explicit resource fetch sites and
three resource-add sites; all use fixed type arguments. None selects `PTHN`,
`MNTY`, `DLGX`, or `Crul`. The original About code explicitly selects `TEXT` and
`styl`. The only indexed fetches in this scan select `alis`, not arbitrary types.

The audit covers GetResource, Get1Resource, their named/indexed variants,
RGetResource, and AddResource. It does not emulate implicit Toolbox loading,
calls through fetched trap addresses, or computed jump-table destinations.
Consequently, “no explicit load site” is a bounded result, not a proof that every
possible original execution ignores a resource. The earlier whole-payload and
initialized-game-global scans also found no literals for the four ancillary
types. Inventory presence and an empty `pendingResources` list do not establish
decoded coverage.

## Optional System resources and remaining acceptance

The optional System file is a separate source. Only selected original fonts and
control artwork are decoded for the native presentation; its operating-system
code, drivers, and other resources are not game features or a bundled Mac OS.

The unresolved ancillary rows remain explicit acceptance work. Native help,
controls, and cursors also need their outstanding foreground mouse, touch, and
VoiceOver checks. Decoder parity and source traces do not replace those checks.
See [CD development and verification](../CD_DEVELOPMENT.md) for completed
feature-specific evidence and remaining whole-edition checks.
