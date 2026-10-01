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

Importing and loading do not activate a game or change the persisted selection.
The app lists installed editions and the existing classic import at startup.
Import adds or replaces one edition; Play reloads its current generation, records
the selection in `selection.json`, then adopts it before creating a controller.
Record schema 1 distinguishes installed editions from the historical classic
folder. The last choice is highlighted at the next ordinary startup. An explicit
`OREGON_BOUND_DATA` override retains direct classic launch for existing tooling.

Game Data in the macOS File menu returns to the selector from the title screen.
iPad also has a title-screen Game Data button outside the original canvas.
Active journeys, setup and dialogs disable switching; exit the journey through
the existing save flow first. Returning stops the old controller and audio;
adoption recreates the controller and resource views. Audio reset discards old
waiters, completion callbacks and scheduled queue pumps. macOS uses a single
game window because resource adoption is process-wide.

Full CD gameplay remains under development; import, selection and title-screen
adoption do not certify every original feature.

The native guide uses the selected edition's 61 or 73 pages, title/text indexes
and landmark entry pages. CD pages include the original narration control. It
uses the shared sound queue, respects Sound On/Off, stops on page changes,
index entry and guide close, and can replay after completion. Turning past a
book end leaves narration playing. Text and narration come from the imported
resources; the repository includes neither. Other CD features still require
verification and implementation before full CD support can be claimed.
