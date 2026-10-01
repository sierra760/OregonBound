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
