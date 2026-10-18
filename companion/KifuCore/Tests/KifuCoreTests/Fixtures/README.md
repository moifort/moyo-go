# Real photos

Drop `name.jpg` (or .heic/.png) next to `name.json`, taken with the iPhone on its stand.

```json
{
  "corners": [[x, y], [x, y], [x, y], [x, y]],
  "lines": 19,
  "stoneHeight": 0,
  "expected": ["...................", "..."],
  "ignore": [[0, 18], [18, 18]]
}
```

- `corners`: pixels of the stored photo, origin top-left; order top-left, top-right,
  bottom-right, bottom-left of the grid as seen in the photo.
- `expected`: one string per row, row 0 at the top of the photo; `.` empty, `X` black, `O` white.
- `ignore` (optional): intersections not checked, for stones dropped off-grid.
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
- `rasante-pierre-seule-au-fond`: same setup. A lone white stone at (3,2), near the far edge:
  its own top covers the two cells just beyond it, which then read as bright as the stone.
