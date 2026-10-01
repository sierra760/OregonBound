# Macintosh CD 1.2 conversations

CD CODE4:398a–3ae0 retains the same STR# tables, pair indexes and dialog bounds.
Its entry callback at3ae2–3b2e increments the session cursor at A5−c72 and
closes/reopens the pane on each explicit Talk action. CODE23's initialized data
sets that cursor to1, so the first quote remains2. Native Selection captures the
journey's edition along with table and pair. Rendering never advances it.

The CD portrait prefix is a letter A–W. CODE4:3a14–3a5e subtracts64 and selects
Imag16180+portrait in color (6180+portrait in monochrome). These are23 separate,
single-frame portraits. Imag16180 is the shared108×199 background. The classic
edition still uses digit-selected frames of Imag16080. The native color pane
uses the imported edition's original artwork and104-pixel quote layout.

CODE4:3a96–3abe requests sound3100+10*(table−3100)+pair automatically when the
pane is created. This covers54 recordings,3101–3273 in groups of three. The
request uses the shared sound channel and respects its enabled state. Event5
at3ace clears that channel; another Talk action stops the old quote before
requesting the next. No replay button or click-to-advance control is added.

GameController owns CD Guide/Talk close ordering. Closing audio synchronously
before initializing the next pane prevents a delayed SwiftUI disappearance
callback from stopping the incoming conversation. Guide page turns and its
index/narration controls still act through the same injected audio instance.
Classic Talk does not request or stop audio.

Synthetic tests cover all54 sound IDs, all23 portrait codes, edition rejection,
cursor order and controller transition/mute behavior. Optional private checks
compare all54 pairs in each original edition, CD PCM/rates and artwork, render
every pane, and exercise native controller playback. Full original visual/audio
comparison and iPad touch verification remain part of the broader CD audit.
