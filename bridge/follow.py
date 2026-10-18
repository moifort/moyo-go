"""Following a game played on a real board: what the phone sees, turned into moves.

The phone only ever reports positions. Which moves lead there is a question for the
rules, so every guess made here is checked by playing it through the KaTrain core
and comparing the board it produces. This module only proposes: the positions are
read, the candidate sequences listed, the setup of a game joined halfway written
down. The session plays them.
"""

from typing import Dict, List, Optional, Tuple

from pysgf import Move

from protocol import CommandError, to_engine_coords

#: How many moves back a correction may reach: the phone misread a stone, then saw
#: it right. Beyond that, a position that is neither ahead nor behind is not followed.
CORRECTION_DEPTH = 3

Position = Dict[Tuple[int, int], str]


def read_rows(rows: List[str], size: int) -> Position:
    """The phone's rows — X, O and dots, row 0 at the top — as a stone map."""
    if len(rows) != size or any(len(row) != size for row in rows):
        raise CommandError("bad_board", f"le plateau reçu n'est pas un {size}×{size}")
    position: Position = {}
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == "X":
                position[(r, c)] = "B"
            elif ch == "O":
                position[(r, c)] = "W"
    return position


def candidates(
    before: Position, after: Position, to_play: str, turn_unknown: bool = False
) -> List[List[Optional[Tuple[str, Tuple[int, int]]]]]:
    """The move sequences worth trying from `before`, most likely first.

    Each sequence lists (colour, point), None standing for a pass. Stones that
    disappeared are not listed: they are captures, and only playing the moves can
    say whether they are. A stone of the wrong colour is the other player's move
    after a pass the phone could not see — unless nobody knows yet whose turn it
    is, at the start of a game joined halfway; two new stones are two moves, one each.
    """
    added = [(color, point) for point, color in after.items() if before.get(point) != color]
    if len(added) == 1:
        color, point = added[0]
        if color == to_play:
            return [[(color, point)]]
        if turn_unknown:
            return [[(color, point)], [None, (color, point)]]
        return [[None, (color, point)]]
    if len(added) == 2 and added[0][0] != added[1][0]:
        first = next(stone for stone in added if stone[0] == to_play)
        second = next(stone for stone in added if stone[0] != to_play)
        return [[first, second]]
    return []


def setup_properties(position: Position, size: int) -> Dict[str, List[str]]:
    """Root properties placing the stones of a game joined halfway through.

    The order the stones were played in is lost, so they are placed as a setup. Who
    is to move is a guess from the count — Black moves when the colours are even —
    and the first move seen settles it.
    """
    properties: Dict[str, List[str]] = {}
    for color, key in (("B", "AB"), ("W", "AW")):
        points = sorted(point for point, stone in position.items() if stone == color)
        if points:
            properties[key] = [
                Move(coords=to_engine_coords(r, c, size), player=color).sgf((size, size)) for r, c in points
            ]
    black = len(properties.get("AB", []))
    white = len(properties.get("AW", []))
    properties["PL"] = ["B" if black <= white else "W"]
    return properties
