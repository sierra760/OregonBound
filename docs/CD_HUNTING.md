# Macintosh CD hunting

The CD edition has different hunting rules from Macintosh 1.1. Work on its
session and renderer is in progress. `CDHuntRules` supplies the recovered
initialization rules; it is not yet connected to `OriginalHuntScene`.

The CD chooses one of ten habitats using destination, accumulated rain, and a
random stream seeded from unsigned 16-bit mileage. It then reseeds the shared
stream from TickCount before selecting populations. These two seed changes must
remain visible to the rest of the game.

Population has eleven sprite slots: seven ground animals, three flying animals,
and a tumbleweed slot whose initial weight is zero. First visits begin with
small-animal weights of 20 each; repeated visits use 40 each. The first visit
removes one of those two classes. Seasonal and location-dependent rules supply
the other weights, and random removal leaves three populated classes.

The first-visit removal guard protects the last counted large ground class. The
original counts only slots 0, 1, 4 and 5, but applies its large-class removal guard
to slot 6 as well. `CDHuntRules` preserves this asymmetry and random draw order.

`PreparedTerrainLibrary` captures validated, effective `TERR` records when a
prepared session loads. It resolves source precedence first, checks resource
identity, source length, and signed 16-bit rectangle bounds, and rejects missing
or escaping files. A terrain ID cannot fall back to a lower-priority source or a
different installation. The three views per habitat use IDs
`19200 + habitat * 10 + view`; snow adds three to the background image ID but
retains the same terrain record.

The rules were recovered from CD CODE14:019e–06d0. Public tests use synthetic
inputs. Private acceptance executed the original population instruction block
for 4,560 combinations and compared initial/final weights, totals, every random
call, and final seed with production Swift. All matched. A separate acceptance
check loaded all 30 supplied terrain records through the runtime library and
compared every entry permission and obstacle with the extracted data. Original
resource bytes and those private fixtures are not part of this repository.

Remaining hunting work includes the session, depth-dependent animal art and
animation, terrain collision, projectile handling, carrying-limit settlement,
and rendering/audio acceptance. Presence of extracted artwork is not proof that
the corresponding gameplay has been implemented.
