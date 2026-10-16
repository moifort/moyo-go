# Real photos

Drop `name.jpg` (or .heic/.png) next to `name.json`, taken with the iPhone on its stand.

```json
{
  "corners": [[x, y], [x, y], [x, y], [x, y]],
  "lines": 19,
  "stoneLift": 0.3,
  "expected": ["...................", "..."]
}
```

- `corners`: pixels of the stored photo, origin top-left; order top-left, top-right,
  bottom-right, bottom-left of the grid as seen in the photo.
- `expected`: one string per row, row 0 at the top of the photo; `.` empty, `X` black, `O` white.

`FixtureTests` reads every pair; it is skipped when the folder is empty.
Recommended set: empty board, a few stones, a dense position, a hand over the board.
