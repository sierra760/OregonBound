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
Preparation schema 6 extracts the recovered hint, password, speed and hunt-time
fields into an application-qualified preference profile. The session validates
its edition, application role and CONF1000 digest against the catalog. A store
captures defaults from a matching prepared session when constructed; an explicit
configuration override takes precedence. Existing saved preferences take
precedence over either source. A CD store without a profile or saved preferences
reports missing defaults; classic retains its legacy fallback.

The supported CONF1000 layout is 1108 bytes. Hint and password are MacRoman
Pascal strings at 0x26 and 0x126; password length is 1–10 bytes. Speed at 0x135
accepts 2, 4 or 8; hunt time at 0x136 accepts selectors 1–6. Both source parsing
and prepared-profile decoding validate these settings. Other configuration
fields are outside this decoder. Original data and extracted profiles stay local.

Normal CD import/selection and full gameplay remain under development.
Persistence identity and preference defaults do not establish that the CD
simulation, scoring or management behavior has been fully implemented.

This is native-port persistence. It does not claim compatibility with original
Macintosh CD save files. Resource-session UUIDs invalidate caches and are never
used as durable save identities.
