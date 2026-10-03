# Oregon Bound for macOS and iPad

Oregon Bound is an independent Swift recreation of MECC's 1991 Macintosh color release of *The Oregon Trail* (version 1.1), inspired by the original program's logic, dialog layouts, bitmap fonts, animation frames and sounds.

Macintosh **Oregon Trail CD 1.2 (1993)** support is also under development. It
accepts the CD disk image or the “Oregon Trail CD” application with its “Oregon
Data” folder, and offers the original 256-color, 16-color, and black-and-white
artwork. See [CD development and verification](CD_DEVELOPMENT.md) for supported
paths, checks using your own data, and remaining acceptance work. DOS Deluxe
releases use different formats.

**This repository contains no MECC or Apple files.** This repository provides the app that you need to run the game on modern hardware, but you must provide the original game files.  The graphics, text, fonts and sounds belong to the original game and to Apple's System 7.0, so the app decodes them from your own copies the first time it runs. Nothing is downloaded and nothing leaves your machine.

## What you need

Supply your own copy of either supported Macintosh edition:

| Edition | Required files |
| --- | --- |
| The Oregon Trail, color version 1.1 | `Oregon Trail` application and `Oregon Color` |
| Oregon Trail CD, version 1.2 (1993) | `Oregon Trail CD` application and the complete `Oregon Data` folder: `Graphics 1–4`, `Guide Book 1–3`, and `Oregon Sound 1–5` |

For CD, supplying the whole disk image is convenient and includes the optional
**On-line User’s Guide**. If supplying individual files, add that application too
to read the separate manual. The 73-entry in-game guidebook and its narration
come from the required game files and remain available without the manual.

Both editions accept these source forms:

- the original folder, on a Mac where the files still carry their resource forks;
- an HFS disk image (`.dsk`, `.img`, `.image`, Disk Copy 4.2 or raw);
- MacBinary (`.bin`), BinHex (`.hqx`) or AppleDouble (`._name`) encodings;
- raw resource-fork dumps (`.rsrc`).

Expand StuffIt (`.sit`) archives first. Files are recognized by contents, so
renamed files work. Import one edition at a time; mixed editions, missing
companions, or conflicting copies produce an error naming the problem.
DOS releases called Deluxe are not supported by this importer.

**Recommended: a System 7.0 disk image.** The Chicago and Geneva screen fonts,
alert icons, scroll-bar artwork, and CD manual's original fonts come from the
System file. The importer validates the supported resources. Without it, the
game and manual use substitute text rendering and controls where needed.

## Build and play

With Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed:

```sh
./scripts/play.sh
```

Or run `xcodegen generate --spec OregonBound/project.yml`, open `OregonBound/OregonBound.xcodeproj`, choose the **OregonBound** scheme and Run. The **OregonBound_iOS** scheme builds the iPad version; simulator builds need no signing.

On first launch, choose **Add Files or Folders…**, add one edition's files or disk
image (plus System 7.0 if available), and choose **Import**. Select the imported
edition under **Choose your game**, then press **Play**. CD also offers an
**Artwork** selector for 256 colors, 16 colors, or black and white.

To import another edition or replace an import, return to the title/menu with no
journey active and choose **Game Data…** from the Mac File menu or the iPad bar
above the game. Re-import all the desired files together, including optional
System and manual files. A failed or cancelled import preserves the previous
installation. Both editions can stay installed; choose the edition and artwork
before playing. Saves and preferences are kept separately by edition.

New imports live under `~/Library/Application Support/OregonBound/Installations/`
(inside the app container on iPad). Existing classic imports in the sibling
`GameData` folder remain selectable when they use layout 3. Older layouts need
to be re-imported through **Game Data…**. Removing the old `GameData` folder does
not remove the new installations.

The legacy **classic 1.1** importer can also run from a terminal. This command
does not prepare CD data; use the app's import screen for CD:

```sh
"build/DerivedData/Build/Products/Debug/Oregon Bound.app/Contents/MacOS/Oregon Bound" --import "/path/to/Oregon Trail" "/path/to/System 7.0 HD.dsk" --output /tmp/oregon-data
```

Set `OREGON_BOUND_DATA=/path/to/folder` to run the app or its tests against a
specific **legacy classic** data folder. This override expects a top-level
`graphics_manifest.json`; it does not activate prepared CD data. Use the edition
selector to play CD. Developer checks taking a prepared CD directory explicitly
are described in [CD development](CD_DEVELOPMENT.md).

The game window keeps the original 512×322 proportions and scales the artwork to fill it.

## Playing

[Back on the trail](#back-on-the-trail) takes a closer look at hunting scarcity, illnesses, random events, and the other rules you might remember arguing about at the school computer.

Choose **Travel the Trail**, enter your party and occupation, buy supplies, then choose a starting month. **Continue** starts travel; **Time Out** stops movement while preserving queued rest. The trail controls provide fort stores, trading, hunting, rest, pace/rations, status, map, conversations, and the original guidebook.

- Hunt: click/tap to aim and fire. Projectiles travel to the target; scenery can block them. Default duration is 45 seconds. A party carries 200 pounds back, or 100 for a lone survivor. **Stop Hunting** returns early; **Move** changes the hunting scene.
- Rivers: ford, caulk, take a ferry where available, or hire a guide at the Snake River. The original crossing animation precedes settlement of losses.
- Route forks: choose Fort Bridger or the shortcut, and Fort Walla Walla or the direct route to The Dalles.
- At The Dalles: pay for the Barlow Road or raft the Columbia. Steer the raft with the pointer/touch position and avoid rocks.
- Saves: actions autosave locally. **Load Game** opens a file picker; **Save Game** writes a chosen JSON file during a time out, and **Export Trail Log** writes the original MacRoman text format. Saves live in `~/Library/Application Support/OregonBound/`.
- Arrival leads to the original score breakdown and qualifying name entry. The **List of Legends** alternates with the title.

The trail sidebar accepts clicks on both each icon and its ribbon label, a deliberate usability adjustment; the original only accepted clicks inside the icon rectangle.

In the CD edition, **Help → On-line User’s Guide…** opens the optional manual;
on iPad, use the **Help** button above the game. It includes page navigation,
linked illustrations, zoom, readable text, and print/PDF export. If the manual
was not imported, re-import the CD image or include the manual application with
the other game files. The trail sidebar's **Guide** opens the in-game guidebook.

CD journeys also track perishable food separately from stored food and use the
CD artwork, conversations, narration, and game rules. The rules discussed below
describe classic 1.1; see [CD development](CD_DEVELOPMENT.md) for CD differences
and the remaining visual, audio, and interaction acceptance checks.

## Back on the trail

You shot enough meat to feed the wagon for weeks. You could carry back 200 pounds. Then somebody got sick.

If that sounds familiar, this is for you. Oregon Bound recreates the 1991 Macintosh color release of *The Oregon Trail*, version 1.1. These are the rules recovered from that game's program and used in the recreation. If you remember an Apple II, DOS, or later edition, some of the details will differ.

There are spoilers here, including a few answers to arguments you may have had around a school computer.

### That warning about hunting in the same area

Yes, game really does become scarce.

The game remembers the trail mileage of your last hunt that produced meat. Hunt again at that exact mileage and the animal-arrival check slows down: it looks for one particular result out of 150 possible results, instead of one out of 50. Roughly speaking, that's a third as many opportunities for an animal to appear. A short hunt can still be unusually busy or completely dead.

Traveling farther down the trail gets you out of that penalty. Resting in place doesn't. Neither does pressing **Move** while hunting: that changes the hunting scene, but the wagon hasn't gone anywhere.

There is also depletion within a hunt. Shooting one of the larger species roughly halves its weight in the selection of the next animal. The two small-game species are exempt. Move keeps those reduced weights, along with the meat you've collected, ammunition you've used, and time remaining.

The game doesn't keep a permanent wildlife census for every place you've visited. Each new hunt rebuilds its species weights from the location, month, and whether you're repeating the last successful spot. A third hunt at the same mileage gets the same slower-arrival rule as the second; there isn't another cumulative penalty for every outing.

And the warning itself? It appears after every hunt, even when you shot nothing. An empty hunt doesn't record a new successful spot. A hunt that produces meat does, even if your wagon is so full that none of it fits.

### Where did all the animals go?

A hunt has just two available species, chosen at the start from a pool that depends on location and season. There can be only two live animals on screen at once. After four kills, that scene stops producing arrivals altogether. That's when Move is useful: it clears the scene and resets the four-kill limit. The clock keeps running.

You get at most 20 shots per hunt, however much ammunition you own, and only one bullet can be in flight at a time. Bullets take time to reach the spot you clicked. An animal can move before the shot arrives, and scenery can block it. No new animals enter during the last three seconds.

Then you have to carry the meat home. With two or more survivors, the limit is 200 pounds. Alone, it's 100. The wagon's remaining food capacity can cut that down further. Once you've shot enough to fill your allowance, more shooting may only use up bullets.

### Stretching the food, pushing the oxen

The ration settings are quite literal:

| Rations | Pounds per person each day | Pounds for five people |
|---|---:|---:|
| Filling | 3 | 15 |
| Meager | 2 | 10 |
| Bare Bones | 1 | 5 |

Bare Bones makes the food last three times as long as Filling, but adds more strain to the party's health every day. Running out is worse. Rest days still require food.

There is a small mercy in the arithmetic: if you have even one pound left when the daily health calculation runs, it uses the fed rule for that update. Food is consumed afterward. The starvation penalty starts on a later update if you're still empty.

Pace buys speed at another health cost. With eight individual oxen, no active illnesses or injuries, and no accumulated snow, the ordinary early-trail distances are 20 miles at Steady, 30 at Strenuous, and 40 at Grueling. Starting with the leg toward Independence Rock, they drop to 12, 18, and 24. Arrival can adjust the last day's mileage.

Eight oxen, or four yoke, is the limit for the speed benefit. More can give you replacements after losses. Fewer will slow you down. Active illnesses and injuries reduce mileage too, as does accumulated snow, so a party pushed hard enough to get sick starts losing some of the speed you were trying to gain.

### What Good, Fair, Poor, and Very Poor mean

Everyone in the wagon shares an underlying health value. Individual people can also have a named illness or injury. That's why several travelers can show the same general health while another shows a condition such as a broken leg.

Internally, the shared value measures how badly things are going: zero is best, and higher is worse. The labels cover these ranges:

| Shared health value | Status |
|---|---|
| 0–34 | Good |
| 35–69 | Fair |
| 70–104 | Poor |
| 105–139 | Very Poor |

Each day carries forward about 90% of the previous value, rounded down, then adds the day's strain. Faster travel, smaller rations, uncomfortable temperatures, wet or snowy weather, inadequate clothing, and active illnesses all contribute. Some trail events add a further penalty.

That gradual carryover explains why a party can take time to recover after you improve its food or pace. It also means Good covers a range: two parties can both look fine on the status screen while one is closer to trouble.

Clothing is counted per surviving person, with more needed in colder conditions. Buying clothes really can help, but there's a limit to that benefit. Once everyone has enough for the current temperature, extra sets don't keep improving health.

### Dysentery, broken legs, and the next bad roll

On an ordinary travel day, the game checks whether to run an illness event. The chance rises with the shared health value, from roughly 1% at its best to roughly 10% at its worst. Good health reduces the danger; it never eliminates it. These are approximate odds because the original random-number generator doesn't divide every range perfectly evenly.

The event picks a traveler. If that person has no active condition, it assigns one of six: Exhaustion, Typhoid, Cholera, Measles, Dysentery, or A Fever. All six use the same initial 9–11-day timer in this routine. Dysentery's memorable name doesn't give it a separate, uniquely lethal set of rules here.

If the chosen traveler is already sick or injured, the same event can kill them. Without a Doctor, it does. This is why someone can seem to be getting through an illness and then suddenly die: they were selected again before recovering.

A Doctor gets a rescue roll at that point. It's roughly a one-in-two chance for a broken arm or leg, and one in three for the other conditions, including snakebite. A successful rescue prevents that death; the existing condition remains.

Injuries come from separate events:

| Condition | Timer assigned by the event |
|---|---|
| Snakebite | 9–11 days |
| Broken arm or leg | 28–32 days |

Those events keep an existing longer timer rather than shortening it. The daily update counts timers down, including on rest days, and clears a condition when its timer reaches zero. A condition assigned before that day's health update has its timer decremented the same day, so these numbers aren't a promise of that many full days remaining after the message appears.

The party leader usually escapes these selections while companions are alive. The selection routine normally chooses from the other names, then selects the leader when only one survivor remains. Being first on the list is an advantage, though it doesn't make the leader immune to every danger in the game.

There is another route to an illness event: if the daily health calculation pushes the shared value above 139, it calls the illness/death routine directly. A party in terrible condition can therefore face more than the ordinary daily roll.

### Rest helps, but the wagon still needs dinner

Rest removes the health strain caused by your chosen pace. It also skips the ordinary trail-event checks on days that begin with rest active. Existing delay days skip those checks as well.

Weather, food consumption, condition timers, and shared health still update. If everyone is cold and hungry, sitting still may not be enough to turn things around. The health-threshold illness check still applies, so a traveler can die while you're resting.

One oddity in the recovered rules is the extra update at the end of rest. A request for three days counts through those three resting updates, then advances the date once more to clear the rest state. That final update also consumes food and updates health. Depending on whether travel is still enabled, the wagon can move on that update. Budgeting exactly three days' food for a three-day rest can leave you short.

### Some days really are that unlucky

The game runs a series of event checks, in order. It doesn't choose one misfortune and call the day finished. You can have a breakdown, lose the trail, and suffer another event on the same day. Even an early event that stops the wagon doesn't cancel the remaining checks for that day.

Some checks depend on circumstances. Snakebite requires warm enough weather. Wild fruit is available from May through September. The combined check for a broken wagon part, sick ox, or broken limb becomes more likely later on the trail. Heavy accumulated snow can trigger a snowbound delay without an extra chance roll to decide whether it happens.

The messages also differ in what they actually do:

| Event | What changes |
|---|---|
| Lost or wrong trail | Sets a delay of 1–5 days. |
| Lost person | Sets a delay of 1–5 days; the event doesn't remove that person from the party. |
| Wandering oxen | Sets a delay of 1–3 days; no oxen are deducted. |
| Snowbound or impassable trail | Sets a delay of 1–10 days. |
| Rough trail | Adds a penalty to the day's shared-health calculation. |
| Bad water or no water | Adds a shared-health penalty, with bad water carrying the larger one. |
| No grass | Records a warning; this event itself doesn't deduct oxen or change health. |
| Wild fruit | Adds 20 pounds of food, up to the wagon's 2,000-pound food capacity. |
| Food aid | Can add 30 pounds when your food is at zero. |

The delay numbers are the counters assigned by the events; they use the same extra cleanup update described for rest. If several events request delays, the game keeps the longest remaining delay rather than adding them together.

Not all health penalties stack, either. Rough trail, illness, and water events write to a shared pending-penalty slot. A later event can replace an earlier value. The journal can sound even worse than the day's final arithmetic.

Fire checks clothing, ammunition, spare parts, and food separately. Each has roughly a one-in-two chance of being selected for a loss, and the amount can be anything from nothing to the entire quantity. That fire routine leaves cash and oxen alone. Finding abandoned supplies checks clothing, bullets, and spare parts; food and oxen aren't in that particular windfall.

### Your occupation can do more than change the score

A Blacksmith or Carpenter gets an extra opportunity to repair a broken wagon part. Everyone also gets a general repair chance. Successful repairs at this stage don't consume a spare; if repair fails, the game uses the matching spare if you have one. Fail both ways and the wagon is left with unrepaired damage that stops travel. Buying one of each spare wasn't just something the storekeeper talked you into.

A Farmer gets roughly a one-in-two chance to prevent the loss from an ox-sickness event. Otherwise that event deducts one individual ox. Because the game often displays oxen in pairs, a loss can leave the displayed number unchanged. The alternating sickness and death messages reflect that pair bookkeeping.

The Doctor's benefit is the rescue roll for an already sick or injured traveler. Choosing Doctor doesn't prevent the initial illness, shorten every recovery, or protect anyone from drowning.

### The river was sometimes decided before you crossed

Fording at a displayed depth of 3 feet or more always swamps the wagon in this version. Exactly 2.5 feet produces a wet crossing without invoking the failed-crossing loss routine. Below that, the outcome depends on which river you're crossing.

Caulking has its own risk calculation. Ferries are available at the Kansas and Green rivers for $5 when the water is deep enough. At the Snake River, a guide costs three sets of clothing. Paying for help still leaves some circumstances in which an accident can happen.

The displayed width and depth are recorded when you arrive. Waiting changes the weather and accumulated rain, which can affect the current calculation, but those displayed dimensions stay fixed. You can wait for different conditions without seeing the depth on screen change.

### Arriving with something left

Surviving people are worth a lot of points. Before the occupation multiplier, each earns 500 at Good health, 400 at Fair, 300 at Poor, or 200 at Very Poor. Five people arriving in Good health contribute 2,500 points.

Food earns one point per complete 25 pounds, bullets one per complete 50, and money one per complete $5. The wagon, oxen, clothing, and spare parts also count. Your occupation multiplies the subtotal: a Banker starts with $1,600 and scores ×1; a Farmer starts with $400 and scores ×3; a Teacher starts with $400 and scores ×3.5.

There is still a decision to make at The Dalles. The Barlow Toll Road costs $5 and leaves 100 miles of ordinary overland travel, including its daily risks and food use. Rafting the Columbia gives you the rock-dodging finish instead. The toll doesn't buy an instant arrival.

## Verify

```sh
xcodebuild -project OregonBound/OregonBound.xcodeproj -scheme OregonBound \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/oregon-bound-build \
  test CODE_SIGNING_ALLOWED=NO
python3 -m pip install -r requirements-dev.txt
python3 -m pytest -q
```

To test with a separate import, append `OREGON_BOUND_DATA=/path/to/import` to the `xcodebuild` command.

The Swift tests read the same imported data as the app and skip the pixel comparisons whose original screen captures are not distributed. The Python suite exercises the reference extraction pipeline in `scripts/`; its tests skip unless you have produced `raw/` and `assets/` locally (below).

## Reference extraction pipeline

The Swift importer (`OregonBound/OregonBound/Data/`) is a port of the Python scripts in `scripts/`, which remain the reference: the Swift output is checked to be pixel- and byte-identical to theirs. To run them yourself you need Pillow, `macresources` and `machfs`:

```sh
python3 scripts/dump_resource_forks.py "/path/to/Oregon Trail folder or disk image"   # writes raw/*.rsrc
python3 scripts/extract_graphics.py            # assets/graphics/oregon_color
python3 scripts/extract_fonts.py               # assets/fonts
python3 scripts/extract_snd.py scripts/extract_str.py scripts/extract_wst.py scripts/extract_ditl.py scripts/extract_hvof.py scripts/extract_pict_text.py
python3 scripts/extract_system_fonts.py --disk "/path/to/System 7.0 HD.dsk" --controls-output-dir raw/system7
python3 scripts/extract_system_scrollbar.py --disk "/path/to/System 7.0 HD.dsk" && python3 scripts/render_system_scrollbar.py
python3 scripts/extract_system_alerts.py --disk "/path/to/System 7.0 HD.dsk"
```

`raw/`, `assets/` and `Original/` are ignored by git so that derived material is never committed.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the ground rules and development workflow.

## Fidelity status

The implementation uses decoded original Imag frames, the four WTTimes bitmap strikes, original dialog layouts, and rules recovered from the executable's instructions: setup, daily travel/weather/health/events, trading, river crossing animations and loss rules, hunting, rafting, stores, Talk, Guide, route choices, scoring, and sound sequencing. Exact-fidelity work remains open in places: original save-file interoperability, some timing/presentation details, and systematic visual comparisons.

## License

The reimplementation is released under the MIT license (see `LICENSE`). *The Oregon Trail* is a trademark and copyright of its owners; this project is not affiliated with or endorsed by them.

The app icon is newly generated artwork made with OpenAI image generation; no original game artwork was supplied as a reference.

## Publication and compatibility

GitHub Actions builds both platforms, runs tests without proprietary fixtures and checks tracked files for accidental data inclusion.

The current prepared import format is schema 10. Earlier prepared formats remain
readable where supported; features needing newly decoded resources show a
re-import instruction. Re-import the same source files to add those resources.
The legacy classic importer uses layout 3. Native saves carry their edition;
loading a save with another edition reports an error. Source hashes identify
imported installations and their resources; saves are not tied to those hashes.

The Python extraction pipeline also needs `python3 scripts/extract_runtime.py` to produce these runtime files.
