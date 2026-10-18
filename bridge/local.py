"""The fight on the board, read on its own: KataGo kept inside a zone.

The best move is often a big point far from the fight, which is right and teaches
nothing about the fight itself. This module answers the other question — what is
the best play *here*, and how does it go on — for a zone drawn around the last move.

KaTrain already analyses a region of interest, but constrains the first move only:
its line drifts back to the biggest point on the board as soon as it can. Here the
constraint holds for the whole sequence, for both colours, because the point is to
read the fight out to its end.

Every function but `request` takes data and returns data, like `review.py`.
"""

from typing import Any, Callable, Dict, List, Optional

from katrain.core.engine import KataGoEngine
from pysgf import Move

import scoring
from protocol import to_display_coords

#: How far the zone reaches beyond the stones in the fight, in lines.
MARGIN = 2

#: The smallest zone, in lines a side: room enough to read a life-and-death fight.
MIN_SPAN = 7

#: A zone left this many lines or fewer short of an edge runs on to it. Fights
#: settle against the edges and in the corners: a zone stopping on the second
#: line would cut off the very points where a group lives or dies.
EDGE_REACH = 3

#: How many moves deep both colours are kept inside the zone. Past it KataGo may
#: leave, and the sequence handed to the app stops where it does.
DEPTH = 12


def region(stones: Dict[tuple, str], size: int, last: Optional[Dict[str, int]]) -> Optional[Dict[str, int]]:
    """The zone of the fight, in display coordinates, bounds inclusive.

    Drawn around the last move and every group touching it, friend or foe, then
    widened by `MARGIN` and to at least `MIN_SPAN` a side, then run on to an edge
    within `EDGE_REACH`, so a fight near a corner takes the corner in. None without
    a last move, and None when the zone grows to the whole board: there is nothing
    local left to say that the best move does not already say.
    """
    if last is None:
        return None
    point = (last["row"], last["col"])
    fight = scoring.group_at(stones, size, point) or {point}
    for stone in list(fight):
        for neighbour in scoring.neighbours(stone, size):
            if neighbour in stones and neighbour not in fight:
                fight |= scoring.group_at(stones, size, neighbour)
    top, bottom = _reach_edge(*_widen(min(r for r, _ in fight), max(r for r, _ in fight), size), size)
    left, right = _reach_edge(*_widen(min(c for _, c in fight), max(c for _, c in fight), size), size)
    if (top, left, bottom, right) == (0, 0, size - 1, size - 1):
        return None
    return {"top": top, "left": left, "bottom": bottom, "right": right}


def drawn(zone: Dict[str, Any], size: int) -> Dict[str, int]:
    """A zone the player drew, put in order. Raises ValueError when off the board.

    The corners may come in either order: a drag goes any way across the board.
    """
    rows = sorted((int(zone["top"]), int(zone["bottom"])))
    cols = sorted((int(zone["left"]), int(zone["right"])))
    if rows[0] < 0 or cols[0] < 0 or rows[1] >= size or cols[1] >= size:
        raise ValueError(f"zone {zone} is off a {size}×{size} board")
    return {"top": rows[0], "left": cols[0], "bottom": rows[1], "right": cols[1]}


def _reach_edge(low: int, high: int, size: int):
    """Runs one side of the zone on to the edge it nearly touches.

    Both edges within reach happens on a small board: only the nearer one is taken,
    or a 9×9 zone would cover the whole width and stop being local.
    """
    gap_low, gap_high = low, size - 1 - high
    if gap_low <= EDGE_REACH and (gap_high > EDGE_REACH or gap_low <= gap_high):
        return 0, high
    if gap_high <= EDGE_REACH:
        return low, size - 1
    return low, high


def _widen(low: int, high: int, size: int):
    low, high = max(0, low - MARGIN), min(size - 1, high + MARGIN)
    span = min(MIN_SPAN, size)
    while high - low + 1 < span:
        if low > 0:
            low -= 1
        if high - low + 1 < span and high < size - 1:
            high += 1
    return low, high


def contains(zone: Dict[str, int], point: Dict[str, int]) -> bool:
    return zone["top"] <= point["row"] <= zone["bottom"] and zone["left"] <= point["col"] <= zone["right"]


def whole_board_choice(node, zone: Dict[str, int], size: int) -> Optional[str]:
    """The best move on the whole board, as GTP, when it already lies in the zone.

    The zone then constrains nothing, and its own reading — fewer visits, a search
    of its own — can only disagree by noise. Showing that noise as a second move
    "costing half a point" would teach something false.
    """
    candidates = node.candidate_moves
    if not candidates:
        return None
    move = Move.from_gtp(candidates[0]["move"], player=node.next_player)
    if move.is_pass or not contains(zone, to_display_coords(move.coords, size)):
        return None
    return candidates[0]["move"]


def _top(analysis: Dict[str, Any], prefer: Optional[str] = None) -> Optional[Dict[str, Any]]:
    infos = analysis.get("moveInfos") or []
    preferred = [info for info in infos if info["move"] == prefer]
    if preferred:
        return preferred[0]
    return min(infos, key=lambda info: info.get("order", 0)) if infos else None


def best_move(analysis: Dict[str, Any], node, size: int, prefer: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """KataGo's first choice inside the zone, with what it costs against the whole board.

    `prefer` is the whole-board choice when it lies in the zone: it is then the
    local move too, at no cost. Otherwise the cost is measured against the node's
    own, unconstrained analysis, the way KaTrain measures `pointsLost`; None until
    that analysis is back. Scores come as Black's lead, so the sign follows the
    player to move. A local move that reads marginally better is noise, and costs
    nothing.
    """
    top = _top(analysis, prefer)
    if top is None:
        return None
    move = Move.from_gtp(top["move"], player=node.next_player)
    if move.is_pass:
        return None
    if prefer is not None and top["move"] == prefer:
        return {**to_display_coords(move.coords, size), "points_lost": 0.0}
    root = node.analysis.get("root") if node.analysis else None
    lost = None
    if root and root.get("scoreLead") is not None and top.get("scoreLead") is not None:
        sign = 1 if node.next_player == "B" else -1
        lost = round(max(0.0, sign * (root["scoreLead"] - top["scoreLead"])), 2)
    return {**to_display_coords(move.coords, size), "points_lost": lost}


def variation(analysis: Dict[str, Any], zone: Dict[str, int], size: int, prefer: Optional[str] = None) -> List[str]:
    """The local sequence as GTP moves, cut where it leaves the zone or passes."""
    top = _top(analysis, prefer)
    if top is None:
        return []
    line = []
    for gtp in top.get("pv") or []:
        move = Move.from_gtp(gtp)
        if move.is_pass or not contains(zone, to_display_coords(move.coords, size)):
            break
        line.append(gtp)
    return line


class _Deepened:
    """The engine, seen through a query that keeps both colours in the zone longer.

    KaTrain builds the region-of-interest query — rules, komi, moves, settings — and
    hard-codes `untilDepth: 1`. Rather than copy that builder, the query is let
    through and deepened on its way to KataGo.
    """

    def __init__(self, engine, depth: int):
        self._engine = engine
        self._depth = depth

    def __getattr__(self, name):
        return getattr(self._engine, name)

    def send_query(self, query, callback, error_callback, next_move=None, node=None):
        for entry in query.get("avoidMoves", []):
            entry["untilDepth"] = self._depth
        self._engine.send_query(query, callback, error_callback, next_move, node)


def request(engine, node, zone: Dict[str, int], size: int, on_result: Callable, on_error: Callable, priority: int):
    """Asks KataGo for the zone alone. The answer goes to `on_result`, never to the node.

    Storing it on the node would mix it into KaTrain's candidates, and the
    whole-board marker would start pointing inside the zone.
    """
    # KaTrain's region is (xmin, xmax, ymin, ymax) in its own frame: column, then
    # row counted from the bottom.
    roi = [zone["left"], zone["right"], size - 1 - zone["bottom"], size - 1 - zone["top"]]
    requested = node.analysis_visits_requested
    KataGoEngine.request_analysis(
        _Deepened(engine, DEPTH),
        node,
        callback=lambda result, partial: None if partial else on_result(result),
        error_callback=on_error,
        region_of_interest=roi,
        priority=priority,
        ownership=False,
        include_policy=False,
    )
    # The request bumps the node's own bookkeeping; KaTrain would read it as a
    # deeper whole-board analysis than the one it actually has.
    node.analysis_visits_requested = requested
