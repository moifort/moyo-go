"""Territory scoring for the end of a game.

This is the one place in the project where a rule of go is written rather than
borrowed: KaTrain derives its final score from KataGo's ownership map and has no
notion of a stone the player has marked dead, so counting a position with a chosen
set of dead stones has to be done here.

Coordinates are display coordinates — (row, col) with row 0 at the top — because
this module only ever talks to the protocol layer.
"""

from typing import Dict, Iterable, List, Optional, Set, Tuple

Point = Tuple[int, int]
Board = Dict[Point, str]

NEIGHBOURS = ((-1, 0), (1, 0), (0, -1), (0, 1))


def neighbours(point: Point, size: int) -> Iterable[Point]:
    row, col = point
    for d_row, d_col in NEIGHBOURS:
        r, c = row + d_row, col + d_col
        if 0 <= r < size and 0 <= c < size:
            yield (r, c)


def group_at(board: Board, size: int, point: Point) -> Set[Point]:
    """The maximal set of same-coloured stones connected to `point`."""
    colour = board.get(point)
    if colour is None:
        return set()
    seen = {point}
    stack = [point]
    while stack:
        current = stack.pop()
        for neighbour in neighbours(current, size):
            if neighbour not in seen and board.get(neighbour) == colour:
                seen.add(neighbour)
                stack.append(neighbour)
    return seen


def all_groups(board: Board, size: int) -> List[Set[Point]]:
    groups: List[Set[Point]] = []
    seen: Set[Point] = set()
    for point in board:
        if point in seen:
            continue
        group = group_at(board, size, point)
        seen |= group
        groups.append(group)
    return groups


def empty_regions(board: Board, size: int) -> List[Tuple[Set[Point], Set[str]]]:
    """Connected empty regions, each with the set of colours bordering it."""
    regions = []
    seen: Set[Point] = set()
    for row in range(size):
        for col in range(size):
            point = (row, col)
            if point in board or point in seen:
                continue
            region = {point}
            borders: Set[str] = set()
            stack = [point]
            seen.add(point)
            while stack:
                current = stack.pop()
                for neighbour in neighbours(current, size):
                    colour = board.get(neighbour)
                    if colour is not None:
                        borders.add(colour)
                    elif neighbour not in seen:
                        seen.add(neighbour)
                        region.add(neighbour)
                        stack.append(neighbour)
            regions.append((region, borders))
    return regions


def territory(board: Board, size: int) -> Dict[Point, str]:
    """Empty points enclosed by a single colour.

    A region touching both colours is dame and belongs to neither. A region touching
    nothing at all — an empty board — is nobody's either.
    """
    owned: Dict[Point, str] = {}
    for region, borders in empty_regions(board, size):
        if len(borders) == 1:
            colour = next(iter(borders))
            for point in region:
                owned[point] = colour
    return owned


def score(
    size: int,
    stones: Board,
    dead: Iterable[Point],
    komi: float,
    captures: Dict[str, int],
    rules: str = "japanese",
    owned: Optional[Dict[Point, str]] = None,
) -> Dict:
    """Counts the position with `dead` treated as removed.

    `captures` counts stones captured during play, keyed by the capturing player
    ("by_black", "by_white"). Dead stones are added to the opponent's captures under
    Japanese rules and simply vanish under Chinese ones.

    `owned` replaces the territory read off the board, for a position whose borders
    are not closed yet: see `estimate`.
    """
    dead_set = {point for point in dead if point in stones}
    living = {point: colour for point, colour in stones.items() if point not in dead_set}
    if owned is None:
        owned = territory(living, size)

    territory_count = {"B": 0, "W": 0}
    for colour in owned.values():
        territory_count[colour] += 1

    dead_count = {"B": 0, "W": 0}
    for point in dead_set:
        dead_count[stones[point]] += 1

    if str(rules).lower() in ("chinese", "cn", "aga"):
        # Area scoring: living stones plus enclosed territory. Prisoners do not count.
        stone_count = {"B": 0, "W": 0}
        for colour in living.values():
            stone_count[colour] += 1
        black = territory_count["B"] + stone_count["B"]
        white = territory_count["W"] + stone_count["W"] + komi
        detail = {"stones": stone_count}
    else:
        # Territory scoring: enclosed points plus every stone captured, including the
        # ones just agreed to be dead.
        black = territory_count["B"] + captures.get("by_black", 0) + dead_count["W"]
        white = territory_count["W"] + captures.get("by_white", 0) + dead_count["B"] + komi
        # Keyed by capturing player, like `territory`, so the payload speaks one
        # language throughout.
        detail = {
            "prisoners": {
                "B": captures.get("by_black", 0) + dead_count["W"],
                "W": captures.get("by_white", 0) + dead_count["B"],
            }
        }

    difference = black - white
    if difference > 0:
        result = f"B+{difference:g}"
    elif difference < 0:
        result = f"W+{-difference:g}"
    else:
        result = "Draw"

    return {
        "black": black,
        "white": white,
        "komi": komi,
        "territory": territory_count,
        "result": result,
        "points": [{"row": r, "col": c, "color": colour} for (r, c), colour in sorted(owned.items())],
        **detail,
    }


def suggest_dead(
    size: int,
    stones: Board,
    ownership: Optional[List[float]],
    threshold: float = 0.55,
) -> List[Point]:
    """Groups KataGo considers to belong to the opponent.

    `ownership` is KataGo's flat grid, row-major from the top, positive for Black. A
    group whose mean ownership sits clearly on the other side is proposed as dead;
    the player has the final say by clicking.
    """
    if not ownership or len(ownership) != size * size:
        return []
    dead: List[Point] = []
    for group in all_groups(stones, size):
        colour = stones[next(iter(group))]
        mean = sum(ownership[row * size + col] for row, col in group) / len(group)
        belongs_to_black = mean > 0
        if (colour == "B" and not belongs_to_black and abs(mean) >= threshold) or (
            colour == "W" and belongs_to_black and abs(mean) >= threshold
        ):
            dead.extend(sorted(group))
    return sorted(dead)



#: KaTrain's own bounds for counting an open position (`Game.manual_score`): past
#: `SETTLED` a point's owner is known, under `DAME` it belongs to nobody, and in
#: between it is still in doubt.
SETTLED = 0.85
DAME = 0.15
#: How many points may still be in doubt for the count to stand, as in KaTrain.
MAX_UNKNOWN = 10
#: How sure KataGo must be of a point's owner for the board to mark it while the
#: position is still open. Lower, the marks would promise more than KataGo does.
MARK_THRESHOLD = 0.5


def estimate(
    size: int,
    stones: Board,
    ownership: Optional[List[float]],
    komi: float,
    captures: Dict[str, int],
    rules: str = "japanese",
    lead: Optional[float] = None,
) -> Optional[Dict]:
    """The score as it would stand if the game ended the way KataGo sees it.

    Borrowed from KaTrain's `Game.manual_score`: once nearly every point has a
    settled owner, the position is counted like a finished game, with a total that
    adds up (`count`). Before that, counting the points KataGo is sure of would
    leave out most of the board, so the figure is KataGo's own lead (`lead`,
    Black's point of view), rounded to the half point as KaTrain does, and the
    board only marks what KataGo already gives to one side. None until the
    ownership map has arrived.
    """
    if not ownership or len(ownership) != size * size:
        return None
    count = settled_count(size, stones, ownership, komi, captures, rules)
    if count is not None:
        points, dead = count["points"], count["dead"]
        lead = count["black"] - count["white"]
    else:
        dead = suggest_dead(size, stones, ownership)
        owned = {point: "W" if stones[point] == "B" else "B" for point in dead}
        for row in range(size):
            for col in range(size):
                value = ownership[row * size + col]
                if (row, col) not in stones and abs(value) >= MARK_THRESHOLD:
                    owned[(row, col)] = "B" if value > 0 else "W"
        points = [{"row": r, "col": c, "color": colour} for (r, c), colour in sorted(owned.items())]
        lead = None if lead is None else round(2 * lead) / 2
    return {"lead": lead, "count": count, "points": points, "dead": dead}


def settled_count(
    size: int,
    stones: Board,
    ownership: List[float],
    komi: float,
    captures: Dict[str, int],
    rules: str = "japanese",
) -> Optional[Dict]:
    """The count of a position whose every point but a few has a settled owner.

    A stone KataGo gives to the opponent is dead; an empty point it gives to one
    side is that side's. None when too much of the board is still in doubt, or
    when too much of it is nobody's: the game is not over enough to count.
    """
    owned: Dict[Point, str] = {}
    dead: List[Point] = []
    unknown = 0
    dame = 0
    for row in range(size):
        for col in range(size):
            point = (row, col)
            value = ownership[row * size + col]
            colour = stones.get(point)
            if colour is not None and (value if colour == "B" else -value) > SETTLED:
                continue  # a living stone
            if abs(value) < DAME:
                dame += colour is None
                continue
            if abs(value) < SETTLED:
                unknown += 1
                continue
            owned[point] = "B" if value > 0 else "W"
            if colour is not None:
                dead.append(point)
    if unknown > MAX_UNKNOWN or dame > 4 * (size + size):
        return None
    counted = score(size, stones, dead, komi, captures, rules, owned=owned)
    counted["dead"] = sorted(dead)
    return counted
