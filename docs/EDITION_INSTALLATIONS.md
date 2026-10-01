# Edition installation storage

`GameDataLibrary` prepares either supported edition under the app support
directory `OregonBound/Installations`. The historical classic `GameData` folder
is a sibling and is not moved or replaced by the library.

Each edition has `generations/<UUID>/` directories and a `current.json` record.
An import creates a new generation, decodes the source files, and opens a
validated `PreparedGameSession`. Only then does it atomically publish the
edition's current record. Preparation, validation, cancellation and publication
failures leave the previous record intact and remove only that attempt's
unpublished generation. An interrupted process can leave an unreferenced
generation; it does not make that generation current.

Published generations are retained. Re-importing cannot invalidate paths held
by an older scene or audio session. There is currently no automatic cleanup;
this trades disk space for safe session lifetimes. Two editions have independent
records. Overlapping preparations have distinct directories; the last completed
publication becomes current for that edition.

Three identities serve different purposes:

- A source fingerprint hashes the edition and sorted source-role/resource-fork
  SHA-256 pairs, including optional System data. Paths and dates do not affect it.
- A generation UUID identifies one on-disk preparation, even when the same source
  is imported again or decoded by a later version of the importer.
- A session UUID invalidates runtime caches each time prepared data is adopted.

Record schema 1 stores edition, generation UUID and source fingerprint. Loading
checks record version, edition, generation containment and fingerprint agreement
with the prepared catalog. Missing editions return no session; invalid installed
data throws an error. Symlinks in library-owned path components and paths that
resolve outside the library are rejected, including existing parents of a new
generation. These checks validate internal consistency, not authenticity against
malicious edits to every metadata file.

Importing and loading do not activate a game or change the selected edition.
The player selector and teardown of the previous scene/audio session are separate
integration work. Full CD gameplay remains under development; a validated import
does not certify every original feature.
