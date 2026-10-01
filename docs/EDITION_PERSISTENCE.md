# Edition identity and persistent state

`JourneyStore` captures one `GameEdition` when constructed. It never follows a
later change to the active resource session. Controllers create new journeys for
that captured edition; loading or saving a journey from another edition fails.

The classic edition retains its historical `OregonBound` support directory.
Macintosh CD 1.2 stores its state under `editions/macintosh-cd-1.2` below that
base. An injected test directory is the shared base, with the same separation.
Each edition owns `journey.json`, `preferences.json` and `hall-of-fame.json`.
Existing classic files are not moved or deleted.

Native save envelope version 2 includes an explicit edition, which must agree
with both its journey body and the receiving store. Version 1 without envelope
edition metadata is classic only. Missing journey edition metadata also means
classic. Unknown versions or editions, and inconsistent envelope/body identities,
are rejected before state migration. A successful legacy load is stamped classic
in memory and uses version 2 when next saved; the load itself does not rewrite
its source.

Preferences use `OregonBoundPreferences` version 1 with an edition and
configuration. Legends use `OregonBoundLegends` version 3 with an edition, player
records and the actual displayed table. Untagged preferences, version 2 legend
tables and historical score arrays are classic only. Writes use the current
format. The classic malformed-preference fallback is retained; a recognized
versioned envelope with invalid metadata is an error, not a legacy fallback.

The supplied classic and CD CONF1000 resources have byte-identical legends tables
from offset 0x1c8 through the end of the resource. Their preference defaults differ.
The CD store therefore requires explicit profile defaults when no preferences
have been saved. CONF/profile integration must supply those defaults before
normal CD play is enabled. Persistence identity does not establish that the CD
simulation, scoring or management behavior has been fully implemented.

This is native-port persistence. It does not claim compatibility with original
Macintosh CD save files. Resource-session UUIDs invalidate caches and are never
used as durable save identities.
