"""Where a group can be hit: the weak points of the stones on the board.

A weak point is not named — cut, vital point, eye — nor found by shape. It is a
point that matters to an unsettled group: KataGo is asked where each colour would
play near the stones, with the ownership map after each candidate, and a point
counts when the group's stones fare much worse if the attacker plays there than
if the group's own side does. That is the old proverb, the opponent's vital point
is your own, measured.

Comparing the two colours on the same point leaves the tempo out: neither answer
gains a move on the other. Comparing a candidate with the position before, or with
the other candidates, does not — and KataGo, left free, spends its visits on the
biggest point on the board and never looks at a group it does not need to attack
right now. Hence the moves kept near the stones.

The other colour's answer comes from the same position after a pass, the usual way
of asking KataGo "and if the other side were to play?".

Every function but `request` takes data and returns data, like `local.py`.
"""

from statistics import mean
from typing import Any, Callable, Dict, List, Optional, Set

from katrain.core.engine import KataGoEngine
from pysgf import Move

import scoring
from protocol import to_display_coords, to_engine_coords

#: How far from the stones KataGo may play, in lines.
REACH = 2

#: A candidate KataGo barely read still has the network's own ownership map
#: after it, which is what is compared; one visit is too few to be its own.
MIN_VISITS = 2

#: A chain whose mean ownership reaches this is settled: nothing to attack.
SETTLED = 0.85

#: The least swing worth a point on the board, in stones. A quiet opening stays
#: under 0.15; a lone stone under attack or a cut already shows 0.3 and more.
THRESHOLD = 0.3

#: The most points shown per colour, strongest first.
MOST = 3


def area(stones: Dict[tuple, str], size: int) -> Set[tuple]:
    """The empty points within `REACH` lines of a stone, in display coordinates."""
    near = set()
    for row, col in stones:
        for r in range(max(0, row - REACH), min(size, row + REACH + 1)):
            for c in range(max(0, col - REACH), min(size, col + REACH + 1)):
                if (r, c) not in stones:
                    near.add((r, c))
    return near


def points(
    mine: Dict[str, Any], theirs: Dict[str, Any], stones: Dict[tuple, str], size: int, player: str
) -> List[Dict[str, Any]]:
    """The weak points `player` could hit.

    `mine` is KataGo's answer with `player` to move, `theirs` with the other colour
    to move; `stones` is keyed by display coordinate. Ownership maps are KataGo's,
    flat, row-major from the top, positive for Black.
    """
    sign = 1 if player == "B" else -1
    roots = [answer.get("ownership") for answer in (mine, theirs)]
    if any(not own or len(own) != size * size for own in roots):
        return []
    targets = [
        chain
        for chain in scoring.all_groups(stones, size)
        if stones[next(iter(chain))] != player
        and abs(mean(sum(own[r * size + c] for own in roots) / 2 for r, c in chain)) < SETTLED
    ]
    if not targets:
        return []
    ours, others = _candidates(mine, size), _candidates(theirs, size)
    found = []
    for move in ours.keys() & others.keys():
        hit, held = ours[move], others[move]
        swing = sign * sum(hit[r * size + c] - held[r * size + c] for chain in targets for r, c in chain)
        if swing >= THRESHOLD:
            point = to_display_coords(Move.from_gtp(move).coords, size)
            found.append({**point, "color": player, "swing": round(swing, 1)})
    found.sort(key=lambda p: (-p["swing"], p["row"], p["col"]))
    return found[:MOST]


def _candidates(answer: Dict[str, Any], size: int) -> Dict[str, List[float]]:
    """Each candidate move read enough, with the ownership map after it."""
    return {
        info["move"]: info["ownership"]
        for info in answer.get("moveInfos") or []
        if info.get("visits", 0) >= MIN_VISITS
        and len(info.get("ownership") or []) == size * size
        and info["move"].lower() != "pass"
    }


class _Shaped:
    """The engine, seen through a query kept near the stones, a pass first if asked.

    KaTrain builds the query — rules, komi, moves, settings — and its region of
    interest is a rectangle for both colours; here it is one colour, around every
    stone. A pass node in the tree would show up in it, so the pass is added here.
    """

    def __init__(self, engine, player: str, moves: List[str], passer: Optional[str]):
        self._engine = engine
        self._player = player
        self._moves = moves
        self._passer = passer

    def __getattr__(self, name):
        return getattr(self._engine, name)

    def send_query(self, query, callback, error_callback, next_move=None, node=None):
        if self._passer is not None:
            query["moves"].append([self._passer, "pass"])
            query["analyzeTurns"] = [len(query["moves"])]
        query["allowMoves"] = [{"player": self._player, "moves": self._moves, "untilDepth": 1}]
        self._engine.send_query(query, callback, error_callback, next_move, node)


def request(engine, node, player: str, near: Set[tuple], size: int, on_result: Callable, on_error: Callable, priority: int):
    """Asks KataGo where `player` would play near the stones, with each candidate's
    ownership map. `near` is in display coordinates.

    The answer goes to `on_result`, never to the node: mixed into KaTrain's
    candidates, the other colour's moves would move the green marker.
    """
    moves = [Move(coords=to_engine_coords(row, col, size)).gtp() for row, col in sorted(near)]
    passer = node.next_player if player != node.next_player else None
    requested = node.analysis_visits_requested
    KataGoEngine.request_analysis(
        _Shaped(engine, player, moves, passer),
        node,
        callback=lambda result, partial: None if partial else on_result(result),
        error_callback=on_error,
        priority=priority,
        ownership=True,
        include_policy=False,
    )
    # The request bumps the node's own bookkeeping; KaTrain would read it as a
    # deeper whole-board analysis than the one it actually has.
    node.analysis_visits_requested = requested
