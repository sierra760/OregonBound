# Macintosh CD food-system verification

The additional source under development is **Oregon Trail CD 1.2 (1993) for
Macintosh**, as identified by the supplied disk. DOS releases called Deluxe use
other formats. The broader CD implementation and acceptance work is still in
progress; these checks cover its food system.

CD journeys keep non-perishable food (capacity 2,000 pounds) and perishable food
(capacity 1,000 pounds) separately. Stores and trades exchange non-perishable
food; hunting, wild fruit, and food aid add perishable food. Consumption uses
both pools, and warm-weather spoilage affects perishable food. Fire, river, and
rafting losses include the extra inventory slot. Wagon load includes both pools
and affects overload events and river supply-loss risk.

Status lists both quantities; Conditions shows their combined total and wagon
weight. Scoring rounds each food quantity down separately after dividing by 25.
Classic Macintosh 1.1 journeys retain their single food pool and original rules.

Compatibility decisions:

- Old native CD saves keep their existing food as non-perishable because they
  contain no purchase-versus-hunting history.
- Already resolved seven-item CD crossing results retain their original losses;
  loading appends a zero perishable loss without drawing new random numbers.
- Legacy CD trade offers retain their terms. Their old classic portrait index
  has no established CD identity, so that one pending offer uses the CD
  background without a portrait. Newly generated offers use the CD portraits.

## Checks with your own prepared data

The normal macOS test suite uses synthetic data and includes the original-game
observation of a 53-pound hunt followed by two rest updates: 985 stored food
becomes 979 stored plus 29 perishable food, with one bullet used and 1,897 pounds
of wagon load for the reference inventory.

The optional driver below loads an existing **schema 7 prepared CD directory**
(the directory containing `prepared_import.json`), including its actual terrain
and hunt geometry. It runs both route choices and both endings in each color
mode, executes CD hunting, and validates inventory and random-state continuity
through native save/reload. It creates verification saves only in the output
directory you specify. It does not contain or obtain original game data.

From the repository root, using Xcode's Debug build:

```sh
xcodebuild -project OregonBound/OregonBound.xcodeproj -scheme OregonBound \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build
products="$PWD/build/DerivedData/Build/Products/Debug"
swiftc -parse-as-library -I "$products" scripts/verify_cd_food.swift \
  "$products/Oregon Bound.app/Contents/MacOS/Oregon Bound.debug.dylib" \
  -Xlinker -rpath -Xlinker "$products/Oregon Bound.app/Contents/MacOS" \
  -o build/verify-cd-food
build/verify-cd-food /path/to/prepared-cd /tmp/oregon-cd-verification
```

A successful run prints eight completed journeys. The current reference run
per color mode finishes in 176/166/215/199 days for short-road, short-raft,
long-road, and long-raft choices, with scores 2774/2787/1687/1394. Across both
modes it exercises 44 hunts and 154 save/reloads. This is an automated player
policy, not a recording of original-game input or proof of every CD feature.

## Sidebar artwork

Sidebar icons now request their `cicn` resource type explicitly. Several icon
IDs also identify unrelated `Imag` panel graphics, so numeric ID alone is not a
safe lookup. CD controls use the selected color family's oval frames and the
original pressed icon offset; disabled controls show an empty oval. The full
ribbon remains part of each button's mouse/touch target.

Synthetic tests cover colliding resource IDs, frame selection, both manifest
orders, and missing typed resources. Local checks with supplied CD data compare
all ten icons in normal, pressed, and disabled states in both color modes
(60 renders) against the imported pixels and recovered positions. This covers
sidebar artwork; monochrome presentation and complete interface acceptance
remain in progress.

## CD dust storms

CD severe-weather events can become dust storms when accumulated rain is below
5, there is no snow, and the destination index is 4 through 11 in the original
route table. The dust check precedes temperature checks and uses no additional
random draws. It delays travel by one day and records “Dust Storm.” in the
journal. The original severe-weather trigger still controls when this check runs.

The locked weather update retains dust for that update; the following weather
update chooses new conditions. Health, hunting restrictions, native save/reload,
and the Conditions artwork and label recognize the additional category. Classic
saves retain their original weather range. Local renders verify the dedicated
dust image and label with supplied CD data in both color modes.

## Conditions snapshots and warnings

CD Conditions now reads the last pane redraw's world snapshot. The model
publishes after each eligible 75-tick pulse, including stopped journeys; the
pane checks for publications every 15 ticks. Hidden panes consume publications
without drawing. Modal or inactive dispatch leaves the presentation unchanged.
These updates do not advance game time or consume random numbers themselves.

Food at 100 pounds or less, health badness at 105 or greater, and cached wagon
weight at 2,750 pounds or greater alternate between plain and bold values.
Resting and delayed wagon statuses use the opposite phase. Labels stay plain.
The original byte-versus-long revision comparison is preserved: after the 255th
publication, subsequent pane polls redraw even without a new publication.

Oregon arrival sends a terminal packet before the enclosing timer pulse
completes. The receiver copies an inactive world without advancing the
Conditions revision; terminal worlds do not redraw warnings. Normal publication
counts persist across subsequent journeys.

Tests cover snapshot isolation, timer and arrival publication, visibility, reloads,
dispatch blocking, thresholds, revision behavior, and classic isolation.
Local native renders using supplied fonts match all four rows in both phases,
at warning and safe boundaries, in both color modes (32 row comparisons).
The full macOS suite passes 810 parameterized cases with 74 skipped, and the
iPad simulator target builds. Live original-game warning timing comparison
remains part of the outstanding foreground acceptance work.

## Monochrome control resources

New preparations use schema 8 and include the separate `ICON` resources used
by the original monochrome controls. Both extractors decode their fixed 32×32
bitmaps with black foreground pixels and transparent unset bits, matching the
source's `srcOr` drawing. They preserve resource type, ID, and source role.
The supplied CD contains 25 application icons and one in Graphics 2; all 26
match native, Python, and independent raw-bitmap checks. All 2,362 preexisting
CD PNGs remain byte-identical after re-preparation.

Schema 8 requires every cataloged icon to have its prepared frame. Older schema
7 color imports and classic schema 6 imports remain usable. Color presentation
excludes `ICON` entries so they cannot displace a color image with the same ID.
This prepares the controls for monochrome support; runtime artwork bindings,
layout, and display-mode selection are still in progress.

The internal monochrome session now requires schema 8 and selects explicit
mono/color artwork pairs plus typed `ICON` controls. Static pane bindings cover
setup, stores, sidebars, weather (including same-ID dust), guide, talk/trade,
maps, and endings. Local source-data checks resolve 198 selected artwork/control
frames across the three CD display modes. Save fingerprints remain independent
of display choice. Monochrome stays outside the setup selector until animated
paths, authored geometry, ink/patterns, and full journeys are verified.

## CD landmark scenes

Stopped landmarks use the CD's separate `5400`/`15400` families, with ten IDs
reserved per location. Weather categories above 1 select the cloudy variant;
accumulated snow selects the snowy variant. Snake River uses only its two
weather variants. Each selected image has one frame. The native pane draws at
authored dimensions and clips overflow instead of resizing the painting.

An open scene refreshes when Conditions displays a changed weather category.
Snow changes alone retain the existing picture until the pane is reopened.
Classic landmark strips remain unchanged. Local native renders match all 216
location/weather/snow/display-mode combinations pixel for pixel against the
supplied prepared images. Landmark ambient audio is identified separately and
remains part of the audio use-site audit.

The CD title now selects `9001`/`19001` explicitly and retains its static
494×304 crop without consuming random numbers. Travel selects `5100`/`15100`
and captures all selected frame dimensions, including monochrome frame 11's
24-pixel height. Only the 256-color mode applies the moving sky/ground palette.
Offscreen SpriteKit renders match three title crops and nine initial travel
compositions against source pixels at native Retina scale. The native suite
passes 840 parameterized cases (74 skipped), and the iPad target builds.
River, raft, hunting, and monochrome ink/layout acceptance remain outstanding.

Monochrome rivers select `5310`, retain the source's 20 logical animation slots
by clamping the last two to bitmap 17, and omit color-only snow aliases.
Hunting now captures the prepared session's monochrome family for terrain,
animals, scenery, and projectiles. Grayscale bitmaps convert to RGBA before
mask construction; enclosed white stays opaque, while exterior white clears.
The color palette substitution is skipped for monochrome artwork.

Local verification covers 36 river captures, all 60 monochrome hunting terrain
views, 86 animal/projectile compositions, and 160 completed hunt settlements.
Every compared native capture matches independent source compositing. The
full native suite passes 843 parameterized cases (74 skipped); iPad builds.
These are offscreen checks, separate from the pending original foreground
comparison and full monochrome journey acceptance.

CD rafting captures the selected display depth at scene creation. Monochrome
uses `10000`/`10001` and a 51-pixel raft; color uses `20000`/`20001` and 52 pixels.
The source intentionally advances monochrome progress once per three-tick
update, versus twice for color. Mode-specific runs therefore need not consume
the same random sequence or produce identical outcomes. Saved wagon identity
and the saved inventory snapshot are unchanged by the display selection.

Depth regressions cover complete no-collision runs in all three modes. A local
source-data verifier completed 60 raft runs and checked 244,466 draw commands
against the selected resource IDs and dimensions, including mirrored shores.
The full native suite passes 846 parameterized cases (74 skipped), and iPad
builds. Monochrome raft fill patterns and loss-panel paper remain in the styling
work before the mode is exposed.
