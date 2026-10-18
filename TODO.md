# TODO

Things deliberately left out of the first Mac App Store release of Moyo Go.
Each entry says what it is and why it was deferred, so the reasoning survives.

## Product

- **Nerd mode.** A toggle that surfaces what the engine is actually doing: visit
  count, playouts, raw win rate, thread count, time per move. The first release
  ships a frozen engine configuration and no settings at all, because the AI mode
  already governs playing strength and every extra knob is a way to degrade the
  experience.

- **Localisation.** The interface is hardcoded French (`Button("Nouvelle partie…")`
  and friends). The App Store listing is worldwide, so the strings should move to a
  String Catalog with English alongside French.

- **Autosave.** A game is saved only when the player asks, through the save panel.
  The panel is what grants a sandboxed app a place to write; saving on its own would
  mean a folder inside the container nobody browses, or a security-scoped bookmark
  and a preference to choose it. A game lost to a quit is the price until then.

- **Only one variation survives a save.** Leaving a variation prunes it, so a saved
  review carries the record plus the continuation on screen at that moment. Keeping
  every reading walked would need the bridge to stop pruning, and the review to tell
  the record's own branches from ours.

- **Variations in an imported record.** A review follows `children[0]` throughout and
  ignores every branch the file carries. Records from a server have none; records
  from a teaching session are mostly branches. Showing them means a tree in the
  sidebar, which is a screen of its own.

- **SGF comments.** `C[]` is kept as KaTrain's node note and written back on save,
  but never shown. A review that showed the commentary would be worth more than one
  that only shows the engine.

- **`CA[]` is ignored on import.** The app decodes the file with the system's own
  encoding detection and sends text to the bridge, so the record's declared charset
  never gets a say. It can only disagree about names and comments — moves are ASCII
  — and honouring it would mean parsing bytes in the bridge and a real charset
  library in place of `shims/chardet`.

- **Teaching mode.** KaTrain's per-move feedback on mistakes and better options. The
  bridge already sends `points_lost` with the best move and nothing displays it.

- **Teaching mode.** KaTrain's per-move feedback on mistakes and better options.

- **Replaying the AI's old answer after an undo.** A move replayed after an undo
  lands on the node KaTrain kept, with the AI's former reply still below it. The
  bridge now has the AI think afresh, so the reply may differ and the tree grows a
  sibling. Walking into the old reply instead would be KaTrain's own redo, but Moyo
  has no redo during a game, and an AI that answers instantly with a move the
  player already saw reads as a replay, not a game. Worth revisiting if a redo
  button ever appears.

- **A drawn zone for each position.** A zone dragged on the board stays put while
  the record is walked, until Escape gives the inferred one back: a fight is read
  over several moves, and redrawing it at each one would be a chore. The flip side
  is that it also follows the player into a part of the game where it means
  nothing. Remembering one zone per position, or dropping the drawn zone once the
  fight leaves it, both need a rule nobody has asked for yet.

- **The drawn zone is not saved.** It lives in the bridge for the review at hand and
  goes with the next record opened. SGF has no property for it short of a private
  one, and a file read in Sabaki would not know what to do with it.

- **Local reading during a game against the AI.** The zone, the blue marker and the
  local sequence exist in a review only, because that is where the best move is shown
  at all. Bringing them into a game means showing a hint while the player is still
  to move, which is a teaching mode, and is waiting on the same decision.

- **One zone at a time.** A board with two fights gets the one around the last move.
  Reading several would mean one more KataGo query per zone and a way to tell their
  markers apart.

- **The first local reading of a record can be slow.** It is asked for only when
  Option is held, at a priority above the whole-board analyses, but KataGo finishes
  the queries already running first. Just after a record is opened, while every
  position is being analysed, the loader can stay up for ten to twenty seconds.
  Pausing the background analysis while a local reading is waited on would cut
  that, at the cost of a gauge that stalls; not done until the wait is felt again.

- **The local sequence stops where KataGo leaves the zone.** Both colours are kept
  inside for twelve moves; past that, or at the first pass, the walk ends. A fight
  that needs a ko threat elsewhere is therefore cut at the threat. Following the
  reading out of the zone would need a rule for when it is still "local".

## Design

- **A record under review is read-only.** Clicking the board does nothing, not even
  on the green marker; dragging across it draws the zone of the local reading.
  Playing the marked move with a click would be the obvious gesture, but it
  collides with the arrow keys owning navigation, and it wants a decision about
  what happens to the branch afterwards.

- **Revisit the icon at 16 px.** Generated with Gemini 3 Pro Image, then masked to
  the macOS squircle by `app/Scripts/make-icon.py`. The wood grain and the grid
  turn to mush at the smallest sizes; a hand-drawn 16 and 32 px variant, with the
  grid dropped entirely, would sharpen the Finder list view.

- **One window, and it can be closed.** Moyo moved to a single `Window` so that a
  record opened from the Finder reaches the game already running instead of a new
  window with its own KataGo. Closing that window leaves the engine running and the
  game intact; a record opened from the Finder while it is closed waits in
  `RecordInbox` until the window comes back. Whether macOS brings it back on its own
  for a document has not been checked.

- **The new-game sheet is the only way out of a finished game.** After a
  resignation or an accepted count, undo is refused by the bridge as well as by the
  app. Taking back the last moves of a lost game to try again would be a gift to the
  player, but it means reopening a result already written into the record.

- **An unexplained crash in the macOS 27 menu bar.** On 10 October 2026, opening
  records from the Finder crashed Moyo five times on the main thread, inside
  `MenuBarClientCore` checking the main executor — no frame of Moyo above the run
  loop. A minimal SwiftUI app with the same delegate, menus and focused value did
  not reproduce it, and neither did Moyo itself afterwards, before or after the
  window and session fixes. If it returns, the crash reports in
  `~/Library/Logs/DiagnosticReports` are the place to start.

## Release

- **Nothing past the gate has ever run.** `release.sh` is exercised up to and
  including the gate; the signing, the upload and the submission have not, because
  there has been no release. `MOYO_SMOKE_ONLY=1` and `MOYO_SKIP_UPLOAD=1` walk the
  chain in stages, and both should be used before a real one.

- **The release is not reproducible off this Mac.** It wants KataGo compiled, the
  certificates in the login keychain and a real GPU. That is a deliberate trade: a
  GitHub runner has a paravirtualised GPU and cannot prove a game is played, which
  is the whole point of the gate. If the release ever has to leave this machine, the
  gate is what has to be solved first, not the build.

- **Release notes come from the tag annotation, in French only.** Every App Store
  locale gets the same text. That is honest while the interface is hardcoded French;
  it stops being honest the day the String Catalog lands.

## Marketing

- **Landing page.** A page advertising the app and linking to its App Store listing.

## Packaging

- **Adaptive thread count.** Derive KataGo's thread count from the core count at
  launch, so entry-level Macs and Ultras both behave sensibly.

- **Optional model download.** The two KataGo models are ~190 MB of the ~270 MB
  bundle. Downloading them on first launch would shrink the app, at the cost of a
  network entitlement, a progress UI, and a dependency on a third-party URL.

- **Track upstream KaTrain.** `katrain.core` is vendored into the bundle. New KaTrain
  releases need to be pulled in deliberately, and the Kivy shim re-checked against
  them.

- **Trim the embedded Python further.** Pruning python-build-standalone takes it from
  67 MB to 53 MB, still the second largest item in the bundle after the models. Freezing
  the standard library into a zip, or dropping unused encodings and `lib-dynload`
  modules, should claw back more.

- **The development install is not a build.** `install-dev-app.sh` puts a Moyo in
  `~/Applications` that runs the repository's bridge and Homebrew's KataGo, with no
  sandbox. It is what opens SGF files on this Mac until a real bundle is built; it
  proves nothing about the sandbox, which only `build-app.sh` and the gate do.

## Out of scope

- **Intel and universal builds.** Apple Silicon only, by design.
- **iOS and iPadOS.** macOS only, by design.
