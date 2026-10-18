# Moyo

Play Go against KataGo on your Mac.

![Moyo](docs/images/moyo-go.png)

## Sixteen opponents, not one

Some are calibrated to a rank, from beginner up to dan level. One is trained on
human games and plays the shapes a person would play, mistakes included. Others
are deliberately lopsided: they chase influence, hoard territory, or answer your
move somewhere else entirely.

Change the mode in the middle of a game and your opponent changes character on
its next move.

## See the game turn

A live score graph tracks the lead from your side of the board. You do not have
to ask for an analysis to notice the move where things slipped.

## End the game properly

Two passes and the counting begins. Dead stones are proposed from KataGo's own
reading of the position, then you correct them by clicking. Japanese or Chinese
scoring.

## Read a game record

Double-click an SGF, drop it on the board, or open it from the File menu, and walk
it with the arrow keys or the buttons under the sidebar. At any position you can see
the move KataGo would have played, and hold Option with the arrows to unroll the
engine's whole continuation before stepping back into the real game.

## Keep a game

⌘S saves to SGF. A game against the AI goes out as it was played, signed with
your name and the opponent's mode; a record under review goes out as it came in,
along with the engine's continuation you are walking. The file opens in KaTrain,
Sabaki or OGS.

## Native, and nothing else

Real menus, keyboard shortcuts, a collapsible sidebar, Liquid Glass. The board
redraws cleanly at any window size.

No account, no network, no telemetry. The engine and its neural networks live
inside the app, so a game never leaves your Mac — and works with no connection at
all.

## Follow a game played on a real board

Kifu, Moyo's iPhone companion, watches a real goban from the side of the table and
records the game to SGF. While it records, Moyo can follow along move by move, with
KataGo's reading and the score curve, and opens the game for review when it ends.
The two talk over the local network only. Kifu lives in [companion/](companion/).

## Requirements

macOS 26 or later, on Apple Silicon. Nothing else to install: the engine, its
models and everything they need ship inside the app.

## Limits

A review follows the main line and does not show a record's branches or comments,
though saving the record keeps both. There is no teaching mode yet.

## License

MIT, same as KaTrain. KataGo ships separately under its own licence.

Moyo stands on [KaTrain](https://github.com/sanderland/katrain) by Sander Land and
[KataGo](https://github.com/lightvector/KataGo) by David Wu.

---

Building from source and cutting a release: [docs/development.md](docs/development.md).
