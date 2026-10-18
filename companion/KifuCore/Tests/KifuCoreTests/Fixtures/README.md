# Real photos

Drop `name.jpg` (or .heic/.png) next to `name.json`, taken with the iPhone on its stand.

```json
{
  "corners": [[x, y], [x, y], [x, y], [x, y]],
  "lines": 19,
  "expected": ["...................", "..."],
  "ignore": [[0, 18], [18, 18]]
}
```

- `corners`: pixels of the stored photo, origin top-left; order top-left, top-right,
  bottom-right, bottom-left of the grid as seen in the photo.
- `expected`: one string per row, row 0 at the top of the photo; `.` empty, `X` black, `O` white.
- `ignore` (optional): intersections not checked, for stones dropped off-grid.
- `stoneHeight` (optional): overrides the reader's stone thickness, in spacings (0.4 by default).
- `calibration` (optional): the corners the game was calibrated with, when the frame is one
  where the stand had moved since; `GridTrackerTests` checks the tracker closes in on `corners`.
- `taps` (optional): rough corners as a user would tap them; `GridDetectorFixtureTests` then
  checks that the detector lands within 8 px of `corners` starting from them. The app saves
  each calibration attempt under Documents/Calibrage with exactly these fields; copy the pair here.
- To find the corners precisely, point four visible intersections (hoshi are ideal) and run
  `swift run -c release kifu-tool read photo.jpg --anchors "col,row,x,y;..." --overlay out.png`,
  then check the overlay.

`FixtureTests` reads every pair; it is skipped when the folder is empty.
Recommended set: empty board, a few stones, a dense position, a hand over the board.

- `rasante-coin-serre`: iPhone 15 Pro on the stand, 18 October 2026. Two white stones side by
  side behind two black ones in the far right corner: the white stone at (16,2) is hidden by
  its neighbours from the four adjacent cells, so the wood reference must come from further out.
- `rasante-pierre-seule-au-fond`: same setup. A lone white stone on the hoshi at (3,3), the
  same stone and pixels as `rasante-blanche-hoshi`: its own top covers the two cells just
  beyond it, which then read as bright as the stone. (First labelled (3,2), from the app's own
  reading: the stone's body seen from this low sits a third of a cell beyond its intersection.)
- `rasante-blanche-hoshi`, `rasante-blanche-hoshi-tard`: same setup, ten minutes apart. A lone
  white stone on the hoshi at (3,3): its top covers (3,2), which read as a second lone white stone
  and left the recorder lost for the rest of the trial.
- `rasante-blanches-au-fond-perdues`: same setup, the 16:09 trial, 10 s after calibration.
  Four white stones on the far rows read as empty although the frame looks the same as the
  calibration one: the disk on the intersection only caught each stone's near rim, and a few
  pixels of drift tipped it. The reader now lifts the disk onto the stone's body.
- `rasante-support-decale`: same trial, four minutes later. The stand had shifted the grid by
  up to 20 px since calibration (`calibration`); `corners` are refitted on this frame.
- `rasante-coin-gauche-lointain`: the 18:24 trial, with the near-left corner of the grid at the
  edge of the frame. Two ghosts the app had recorded as moves: a white at (1,3), where every
  wood cell around the intersection touches a stone and the reference fell back to a cell under
  a stone, and a black at (5,0) under the body of the black stone at (5,1), which leans over the
  far line. (5,0) is left unreadable, not read as empty.
- `rasante-blanche-au-bord-droit`: the frame of `rasante-blanches-au-fond-perdues` with the
  corners the tracker fitted on it. The white stone at (17,5) leans right, over the last line;
  with the disk of (18,5) held on the line, it read that stone's rim as a second white.
