"""Turn a KaTrain Game into the state payload the app renders.

Deliberately free of engine and process concerns: every function here takes a Game
and returns plain data, so the whole module can be tested against a game built by
hand with no KataGo running.
"""

from typing import Any, Dict, List, Optional

from protocol import to_display_coords


def board_size(game) -> int:
    """Side length of a square board.

    The milestone only supports square boards; a rectangular one would silently
    corrupt every coordinate conversion, so it is rejected loudly instead.
    """
    width, height = game.board_size
    if width != height:
        raise ValueError(f"non-square board {width}x{height} is not supported")
    return width


def stones(game) -> List[Dict[str, Any]]:
    size = board_size(game)
    placed = []
    for move in game.stones:
        placed.append({**to_display_coords(move.coords, size), "color": move.player})
    return placed


def score_history(game) -> List[Optional[float]]:
    """Score lead from Black's point of view, one entry per node from the root.

    Entries whose analysis has not come back yet are None; the app leaves those
    bars out rather than drawing them at zero.
    """
    return [node.score for node in game.current_node.nodes_from_root]


def captures(game) -> Dict[str, int]:
    """Stones captured by each player.

    The core counts prisoners by the colour of the captured stone, so the stones
    Black captured are the white ones. Naming the keys by the capturing player
    here keeps that inversion from leaking into the app.
    """
    prisoners = game.prisoner_count
    return {"by_black": prisoners["W"], "by_white": prisoners["B"]}


def last_move(game) -> Optional[Dict[str, int]]:
    move = game.current_node.move
    if move is None or move.is_pass:
        return None
    return to_display_coords(move.coords, board_size(game))


def stone_map(game) -> Dict[tuple, str]:
    """Stones keyed by display coordinate, the shape the scoring module expects."""
    size = board_size(game)
    placed = {}
    for move in game.stones:
        point = to_display_coords(move.coords, size)
        placed[(point["row"], point["col"])] = move.player
    return placed


def game_state(
    game,
    human_color: str,
    status: str = "playing",
    result: Optional[str] = None,
    scoring: Optional[Dict[str, Any]] = None,
    dead: Optional[List[tuple]] = None,
    ai_strategy: Optional[str] = None,
    ai_settings: Optional[Dict[str, Any]] = None,
    review: Optional[Dict[str, Any]] = None,
    extra: Optional[Dict[str, Any]] = None,
    estimating: bool = False,
    estimate: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    node = game.current_node
    payload = {
        "size": board_size(game),
        "stones": stones(game),
        "to_play": node.next_player,
        "move_number": node.depth,
        "last_move": last_move(game),
        "captures": captures(game),
        "score_history": score_history(game),
        "score_lead": node.score,
        "human_color": human_color,
        "status": status,
        "result": result,
        "ai_strategy": ai_strategy,
        "ai_settings": ai_settings,
    }
    if review is not None:
        # A review reads the whole record at once: the move number is a position in
        # the main line rather than the depth of the node on the board, which a
        # variation would otherwise inflate. The session supplies both.
        payload.update(review)
    if extra is not None:
        payload.update(extra)
    if scoring is not None:
        payload["scoring"] = count(scoring, dead)
    # The estimate is asked for, then waited on: KataGo's ownership map may not
    # be back yet, and the app says so rather than showing nothing.
    payload["estimating"] = estimating
    if estimate is not None:
        payload["estimate"] = {
            "lead": estimate["lead"],
            "points": estimate["points"],
            "dead_stones": [{"row": r, "col": c} for r, c in estimate["dead"]],
            "count": None if estimate["count"] is None else count(estimate["count"], estimate["count"]["dead"]),
        }
    return payload


def count(scoring: Dict[str, Any], dead: Optional[List[tuple]]) -> Dict[str, Any]:
    """A count as the app reads it, final or estimated.

    Every component of the total travels with it, so the panel can show a sum that
    adds up instead of a bare figure.
    """
    return {
        "black": scoring["black"],
        "white": scoring["white"],
        "komi": scoring["komi"],
        "territory": scoring["territory"],
        "prisoners": scoring.get("prisoners"),
        "stones": scoring.get("stones"),
        "result": scoring["result"],
        "points": scoring["points"],
        "dead_stones": [{"row": r, "col": c} for r, c in sorted(dead or [])],
    }
