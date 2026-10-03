# Macintosh CD hunting

The CD edition has different hunting rules from Macintosh 1.1. The hunting
pane selects `CDHuntRules`, `CDHuntAnimal`, and `CDHuntSession` for CD journeys.
`CDHuntAssets` binds prepared terrain and frame geometry; `HuntingSession` shares
the presentation contract while preserving each edition's mechanics.

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

The engine implements five-live/four-kill spawn checks, entry-side permissions,
depth selection, terrain foot-strip collisions, stopped poses and shared timers,
shot-startle behavior, projectile impact order, falling birds, Move, timeout,
and 125/250-pound carrying limits. It retains the original repeated live-counter
decrements during bird falls and frame-phase behavior. Native lifecycle pauses
freeze the session; skipped modal updates do not catch up.

Private simulations using the supplied assets completed 400 hunts across all ten
habitats and huntable species, normal/snow terrain and color/monochrome artwork.
Across 161,384 updates and 540 hits, every emitted image/frame reference resolved,
draw dimensions fit the corresponding bitmap, and every session completed. This
is engine and asset validation, not a rendered comparison with the original game.

This work also corrected a shared RNG mismatch: `Random(1)` returns zero but must
consume one QuickDraw draw. Both original wrappers take that path (classic CODE1
jump table at075a selects0774 for one; CD CODE1:069e–06b8 sends one through the
normal random call). Only zero skips the draw for the supported nonnegative
bounds. A regression test first demonstrated the unchanged seed; shared-stream
and full-suite tests now pass with the source-correct sequence.

The scene receives the journey's edition and accumulated rain, uses its shared
random stream, and defers scenery initialization until preparation completes.
The pane reports unavailable hunting assets and offers a return to the trail
without charging ammunition or a resting day. CD settlement accepts 125/250-pound
limits, while classic journeys retain 100/200; the carrying limit captured at
hunt startup survives interleaved changes to the party.

CD CODE14 clips drawing to (9,9)–(503,268), with a black border at y267.
The input user item extends to y271. The renderer preserves the three paper rows
below the clip and positions odd-height crop masks on half-pixel centers.
Native host visibility pauses the hunt; a separate frame-dispatch routine allows
offscreen acceptance without weakening that visibility policy.

Hunting uses preparation/fire/hit/dry-fire sound IDs 9007/9002/9003/9004 through
the controller's audio queue. Private acceptance played all four supplied effects
through `OriginalPCMPlayback` and received each completion callback. Native scene
checks also exercise input, modal suppression, completion, and inventory settlement.

A native synthetic regression found that SpriteKit's CGImage upload could lose
the last transparent pixel with the host display profile. `TextureLoader` now
uploads the already color-converted RGBA bytes with explicit row orientation.
The regression checks transparent corners and asymmetric pixel placement.

Private offscreen native acceptance completed 160 CD hunts. Sixty terrain captures
and 86 animal/projectile captures matched independently composited decoded artwork
pixel for pixel, covering all ten huntable species and 29 of 30 depth resource IDs.
All 160 results returned through the scene callback and settled journey inventory,
phase, and resting time correctly. These are native component checks, not a claim
of screenshot equivalence to the original running game or foreground UI E2E coverage.
