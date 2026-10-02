# Macintosh CD development and verification

The additional source under development is **Oregon Trail CD 1.2 (1993) for
Macintosh**, as identified by the supplied disk. DOS releases called Deluxe use
other formats. The broader CD implementation and acceptance work is still in
progress. The CD source now supports its three display modes, separate food
pools, additional artwork, and CD-specific runtime paths. Remaining whole-edition
acceptance work is listed below.

## CD food system

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

The optional driver below loads an existing **schema 9 prepared CD directory**
(the directory containing `prepared_import.json`), including its actual terrain
and hunt geometry. It runs both route choices and both endings in all three
display modes, executes CD hunting, and validates inventory and random-state continuity
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

A successful run prints twelve completed journeys plus the cross-mode overland
and save checks. The current reference run finishes in 176/166/215/199 days for
short-road, short-raft, long-road, and long-raft choices in each mode. Color scores
are 2774/2787/1687/1394; monochrome scores are 2774/2787/1687/973. Its longer rafting
run can produce different losses, as in the original. The twelve journeys
exercise 66 hunts and 231 save/reloads. Another 56 complete overland snapshots
match across modes, and each mode loads the same native saves in four seasons.
This is an automated player policy, not a recording of original-game input or
proof of every CD feature.

## Display modes and controls

Choose **256 colors**, **16 colors**, or **Black and white** in the CD edition's
Artwork selector before pressing Play. The choice is captured for that session;
it does not change a running journey or the saved source identity. Older CD
imports remain playable in color. Selecting black and white with an older import
shows a re-import instruction; import the same original files again to include
the monochrome control resources. Classic Macintosh 1.1 stays in its existing mode.

Artwork uses explicit source pairs, since a universal resource-number offset
would select incorrect images. Icon lookups specify `cicn` in color or `ICON` in
black and white, avoiding collisions with unrelated images sharing an ID.
Monochrome images keep their authored dimensions and top-left placement.
Paper is white, map and thermometer ink is black, and pane outlines use the
original port-aligned checker pattern. Optional System 7 inputs supply the
scrollbar images; modal borders and active/disabled track drawing follow the
recovered monochrome branches.

CD sidebar, route, pace, ration, river, and Help controls share original oval
frames and pressed icon positioning. Disabled controls hide the icon and erase
alternate label pixels. The sidebar retains its wider ribbon mouse/touch target.
Local checks compare 432 labeled control states and 90 sidebar states exactly
against source images, font metrics, and patterns across all three modes.
Another 40 System-control states match their recovered drawing rules and bitmaps.

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
Live original-game warning timing comparison
remains part of the outstanding foreground acceptance work.

## Monochrome control resources

Schema 8 introduced the separate `ICON` resources used
by the original monochrome controls. Both extractors decode their fixed 32×32
bitmaps with black foreground pixels and transparent unset bits, matching the
source's `srcOr` drawing. They preserve resource type, ID, and source role.
The supplied CD contains 25 application icons and one in Graphics 2; all 26
match native, Python, and independent raw-bitmap checks. All 2,362 preexisting
CD PNGs remain byte-identical after re-preparation.

Schema 8 and later require every cataloged icon to have its prepared frame.
Current CD imports require schema 9 for credits; classic schema 6–9 imports
remain usable. Color presentation
excludes `ICON` entries so they cannot displace a color image with the same ID.
The setup selector exposes monochrome after these resources and the runtime
artwork paths are available.

The monochrome session uses the schema 8 icon inventory and selects explicit
mono/color artwork pairs plus typed `ICON` controls. Static pane bindings cover
setup, stores, sidebars, weather (including same-ID dust), guide, talk/trade,
maps, and endings. Local source-data checks resolve 198 selected artwork/control
frames across the three CD display modes. Save fingerprints remain independent
of display choice.

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
compositions against source pixels at native Retina scale.

Monochrome rivers select `5310`, retain the source's 20 logical animation slots
by clamping the last two to bitmap 17, and omit color-only snow aliases.
Hunting now captures the prepared session's monochrome family for terrain,
animals, scenery, and projectiles. Grayscale bitmaps convert to RGBA before
mask construction; enclosed white stays opaque, while exterior white clears.
The color palette substitution is skipped for monochrome artwork.

Local verification covers 36 river captures, all 60 monochrome hunting terrain
views, 86 animal/projectile compositions, and 160 completed hunt settlements.
Every compared native capture matches independent source compositing. The
checks are offscreen, separate from the pending original foreground comparison.

CD rafting captures the selected display depth at scene creation. Monochrome
uses `10000`/`10001` and a 51-pixel raft; color uses `20000`/`20001` and 52 pixels.
The source intentionally advances monochrome progress once per three-tick
update, versus twice for color. Mode-specific runs therefore need not consume
the same random sequence or produce identical outcomes. Saved wagon identity
and the saved inventory snapshot are unchanged by the display selection.

Depth regressions cover complete no-collision runs in all three modes. A local
source-data verifier completed 60 raft runs and checked 244,466 draw commands
against the selected resource IDs and dimensions, including mirrored shores.
The integration driver captures this same selected depth for each complete journey.

Monochrome rafting now paints the source's white sky, window-anchored `AA55`
water pattern, white map separator, and white loss-panel paper. Pattern textures
are cached per rendering profile. Three complete offscreen raft compositions
match independent source compositing at Retina scale, and 33 loss-frame/paper
regions match across the display modes.


## CD river audio

Crossing animations play the original start, success, tipped-wagon and swamped-wagon
cues. Water ambience starts only when the shared channel is idle and the crossing
is within its source-defined interval. The scene preserves separate failure kinds,
pauses updates during inactive/modal states, and clears crossing audio before the
result pane opens. Classic crossing behavior is unchanged.

Verification compares 906 decisions with the original CODE19 branch block and
completes 54 source-backed native crossing scenes across all methods, failure
kinds, snow settings and display modes. All 175 prepared CD sounds still match
independent source PCM hashes and exact sample rates. These checks verify scheduling
and data; original audible playback comparison remains pending.

## CD rafting audio

Rafting uses its original water ambience, collision cue, and drowning recording.
Ambience checks the shared channel before the movement deadline; drowning audio
starts at the first loss-panel redraw after impact. Explicit redraws can replay
that recording, while ordinary rendering does not. Modal/inactive scenes suspend
new requests. Completion releases rafting audio before the landing pane opens,
and cancelled scenes cannot deliver an old completion callback. Temporary view
disappearance suspends the retained scene; the controller cancels it only when
the owning journey ends or changes.

The controller's audio instance flows through the preparation pane and scene.
Classic collision sounds retain their existing behavior. Sixty complete local
source-data runs across the three display modes matched 176,032 simulation and
random-state snapshots, including 178 collisions, 127 drowning cues and 219
ambient starts. This verifies data and scheduling; audible original comparison
and interactive platform acceptance remain pending.

## CD setup narration

The welcome screen, departure-month chooser and Matt's buying advice play their
CD recordings once per dialog opening. Their controller closes outgoing audio
before navigation, including cancelled setup and replacement journeys. View actions
capture the opening identity, so callbacks from retired dialogs cannot dismiss a
reopened dialog or change a replacement journey’s month. Redraws,
temporary inactivity and modal overlays preserve the current recording. The
existing shared queue and mute behavior apply; classic setup remains silent.

Verification covers the complete controller flow, repeated Help visits, stale
close actions, cancellation, queue ordering, mute and both editions. A private
source-data check completes all six departure months in all three display modes
and verifies each recording against original PCM hashes and exact sample rates.
Original foreground listening remains part of the final acceptance work.

## CD landmark audio

Landmarks request their recordings after the original 60-tick delay and four-tick
poll interval. Ordinary sidebar panes replace the landmark and clear its audio;
higher-priority river overlays preserve the pending recording while hidden.
Weather changes redraw an existing landmark and restart its delay without stopping
current playback. Snow changes alone and temporary coverage preserve its image.
The controller owns artwork and audio together, keeps both tied to the journey,
and retires the pane before an incoming terminal death recording is queued.

Native tests cover source timing, all 18 sound IDs, pane replacement and coverage,
weather draws, mute, busy playback, terminal ordering and classic compatibility.
A private verifier matches 972 original branch decisions and exercises 54 bindings
and reopenings across the display modes. All 18 recordings match source PCM/rates;
54 offscreen landmark artwork regions match their selected source pixels exactly.
These are data and scheduling checks; foreground listening remains pending.

## CD About audio

About clears the previous recording and starts the CD theme on opening. While
credits are shown, it makes the original requests every three ticks through the
shared bounded queue. Opening with Option held on macOS selects the alternate
recording for those subsequent requests. System Information suppresses new
requests; closing clears the queue. Callbacks capture the dialog opening so an
old view cannot stop or schedule audio in a reopened dialog. Classic About
behavior is unchanged.

Tests cover timing including clock wrap, mute, the eight-entry FIFO, temporary
inactivity, information display, close ordering and stale callbacks. Private
verification matches 144 original branch decisions and 60 source-data dialog
cycles across three display modes, with exact PCM/rates for both recordings.
CD credits text/scroll rendering and access to the alternate gesture on iPad
remain outstanding; this phase verifies audio scheduling, not complete About
fidelity or foreground listening.

## CD title and Legends sequence

The initial sound is requested once before the first title page opens. CD title
and Legends pages request the theme only when the channel is idle. Sound-enabled
pages check every 300 distinct host ticks and wait for current playback before
advancing; muted title and Legends openings use 600 and 3600 ticks respectively.
Changing Sound On preserves the interval captured by the current opening.

The controller owns these pages, their timers and callback identities. Modal
coverage suspends dispatch; ordinary background clicks advance immediately.
Setup, a loaded journey and game-data selection retire the old audio before
incoming content can play. The Legends Load button clears its recording before
the chooser, including cancellation. Actual window deactivation clears CD audio;
covering the game with an in-canvas modal does not synthesize that event.
Initial launch opens the title; returning from setup, a journey or an ending
opens Legends. Cancelling Load on the title also opens Legends, while an existing
Legends page retains its timer. Failed loads return after error acknowledgment.
Classic title/Legends timing is unchanged.

Native tests cover busy boundaries, mute changes, modal coverage, cancelled load,
stale callbacks, window activation, setup/load/data transitions and both editions.
Private checks match 32 source creation-interval/timer cases and 60 source-data
transitions across three display modes and sound settings. Startup/theme PCM and
rates match the source. Twelve offscreen native captures verify the selected
pages render; original screen equivalence and foreground listening remain open.

## CD ending audio

Arrival starts recording 1017 once and preserves it when Continue opens the score
page. Score submission clears it before returning to Legends. The loss page
clears and starts sound 9001 on its initial draw and logical redraws, and clears
on exit. Terminal death no longer queues a duplicate CD sound before that page.
Each ending stage owns its callbacks, so an outgoing page cannot affect a new
journey or setup narration. Classic ending audio remains unchanged.

Logical redraws include modal reveal, activation and display changes. A screen
update alone does not restart playback. Reactivation waits for both native window
and scene eligibility, regardless of notification order, without duplicate starts.
Window observers follow their attached
window and unregister when detached. Tests cover both editions, all ending
stages, cancellation/teardown, mute and stale callbacks. Private verification
checks seven original audio branches and 60 source-data flows across three
display modes, exact sample bytes/rates, and unchanged RNG. Eighteen offscreen
captures cover arrival, score and loss with both sound settings. Foreground
interaction and listening remain separate acceptance work.

## CD illustrated event notices

New CD model events select their illustrated notice using the source's priority,
weather/snow variants, destination guards, guide topic and sound rules. Typed
journal metadata preserves event order and parameters without parsing message
text. Old saves remain readable; loading a save never replays its historical
notices, and classic entries remain unchanged.

The native pane uses the imported 10200/20200 artwork family at authored size,
clipped to its original bounds. It expires at the eight-second source deadline,
checks on four distinct timer ticks, and refreshes its deadline on logical
redraw without repeating audio. Travel continues while it is open. Replacement,
arrival, guide navigation and dismissal retire its audio synchronously; callbacks
retained by an old view cannot affect a later opening. The guide icon and its
source hit rectangle are preserved. In 256-color mode, two nine-color palette
rings animate eligible notices; monochrome and 16-color artwork stays static.

Private checks match 7,560 original selector cases, 20,000 stateful selection
steps, and 38 original palette timing steps. They also cover 330 source-data
controller flows, exact bytes/rates for all eight notice recordings, unchanged
model/RNG results over 15 days, and 567 pixel-exact artwork renders across the
three display modes. Three additional native panes were captured in windows
that were never shown. Original foreground interaction and listening remain
separate acceptance work.

## Current acceptance boundary

Local verification includes 201 offscreen AppKit-hosted pane renders across the
three modes, 186 exact artwork-region comparisons, and neutral ink throughout
all 67 monochrome panes. Native controls are hosted in hidden windows for these
checks; no original-game foreground interaction is implied. The latest native run has 967 parameterized passes and 74 skips; Python has
125 passes and 403 skips. The iPad simulator target builds. Tests requiring
unbundled originals or reference captures skip when those inputs are absent.
The fresh review of the complete monochrome phase found no required fixes.

The broader CD effort still requires the remaining ambient/effect audio use-site
audit, standalone On-line User's Guide treatment, remaining feature audit,
interactive original/macOS/iPad acceptance, and final public delivery review.
Original resources, private renders, and disk images are not included here.


## CD credits import (rendering in progress)

Schema 9 preparations preserve the CD application's `TEXT` 200 and `styl` 200
as player-owned runtime data. The bounded parser preserves Mac Roman byte
offsets, carriage returns and style runs, validates their lengths, ordering and
fields, and rechecks both resource hashes against the catalog when loading.
Older CD preparations report a re-import error; installed generations and saved
journeys are retained. Classic schema 6–9 preparations remain supported.

When a System file is supplied with CD data, the importer also extracts its
verified Helvetica 12 bitmap strike. Classic System imports retain their three
existing font selections. No original credits or font payloads are included in
the repository. Scrolling and styled native rendering remain in progress.
