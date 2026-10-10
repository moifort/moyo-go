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

## Design

- **A record under review is read-only.** Clicking the board does nothing, not even
  on the green marker. Playing the marked move with a click would be the obvious
  gesture, but it collides with the arrow keys owning navigation, and it wants a
  decision about what happens to the branch afterwards.

- **Revisit the icon at 16 px.** Generated with Gemini 3 Pro Image, then masked to
  the macOS squircle by `app/Scripts/make-icon.py`. The wood grain and the grid
  turn to mush at the smallest sizes; a hand-drawn 16 and 32 px variant, with the
  grid dropped entirely, would sharpen the Finder list view.

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

## Out of scope

- **Intel and universal builds.** Apple Silicon only, by design.
- **iOS and iPadOS.** macOS only, by design.
