"""Following a game played on a real board: what the phone sees, turned into moves.

The phone only ever reports positions. Which moves lead there is a question for the
rules, so every guess made here is checked by playing it through the KaTrain core
and comparing the board it produces. This module only proposes: the positions are
read, the candidate sequences listed, the setup of a game joined halfway written
down. The session plays them.
"""

from itertools import permutations
from typing import Dict, List, Optional, Tuple

from pysgf import Move

from protocol import CommandError, to_engine_coords

#: How many moves back a correction may reach: the phone misread a stone, then saw
#: it right. Beyond that, a position that is neither ahead nor behind is not followed.
CORRECTION_DEPTH = 3

#: How many moves one board may add: the phone sends the board late when its reading
#: hesitated over a few moves. Every order of each colour's stones is tried, so this
#: stays small — six moves are 36 orders at most.
MAX_MOVES = 6

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
    say whether they are. New stones alternate colours, one move each, up to
    MAX_MOVES of them when the phone sent the board late; the order within a colour
    is unknown, so every order is listed. A first stone of the wrong colour is the
    other player's move after a pass the phone could not see — unless nobody knows
    yet whose turn it is, at the start of a game joined halfway.
    """
    added = sorted((point, color) for point, color in after.items() if before.get(point) != color)
    if not added or len(added) > MAX_MOVES:
        return []
    by_color = {color: [point for point, stone in added if stone == color] for color in ("B", "W")}
    if abs(len(by_color["B"]) - len(by_color["W"])) > 1:
        return []
    if len(by_color["B"]) == len(by_color["W"]):
        first = to_play
    else:
        first = "B" if len(by_color["B"]) > len(by_color["W"]) else "W"
    second = "W" if first == "B" else "B"
    sequences = []
    for firsts in permutations(by_color[first]):
        for seconds in permutations(by_color[second]):
            sequence = []
            for n in range(len(added)):
                sequence.append((first, firsts[n // 2]) if n % 2 == 0 else (second, seconds[n // 2]))
            sequences.append(sequence)
    if first == to_play:
        return sequences
    passed = [[None, *sequence] for sequence in sequences]
    return [*sequences, *passed] if turn_unknown else passed


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


def history_properties(history: Dict, size: int) -> Dict[str, List[str]]:
    """Root properties for the record the phone sent at connection: its setup, and
    who moved first — the first move says, the count guesses when there is none.

    The app hands it over as `setup_black`, `setup_white` and `moves`, points as
    [row, col] in the board's display orientation.
    """
    position: Position = {}
    for color, key in (("B", "setup_black"), ("W", "setup_white")):
        for row, col in history.get(key) or []:
            position[(row, col)] = color
    properties = setup_properties(position, size)
    moves = history.get("moves") or []
    if moves:
        properties["PL"] = [moves[0]["color"]]
    return properties
