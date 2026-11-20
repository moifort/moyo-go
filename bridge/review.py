"""Reading a game record: the tree, the best move, the variation, the progress.

Every function here takes data and returns data. Nothing touches the engine, the
filesystem or the protocol, so the whole module can be exercised against an SGF
written inline in a test and a node whose analysis was filled in by hand.

The bridge never opens a file. The app reads the record and sends its text, which
keeps `shims/chardet` honest and spares the child process any question about the
sandbox.
"""

from typing import Any, Dict, List, Optional

from katrain.core.game import KaTrainSGF
from pysgf import Move

from protocol import CommandError, to_display_coords


def parse(text: str):
    """SGF text -> the root of a KaTrain move tree."""
    if not text.strip():
        raise CommandError("bad_sgf", "le fichier est vide")
    try:
        root = KaTrainSGF.parse_sgf(text)
    except Exception as exc:
        raise CommandError("bad_sgf", f"SGF illisible : {exc}") from exc
    width, height = root.board_size
    if width != height:
        raise CommandError("bad_sgf", f"plateau {width}×{height} : seuls les plateaux carrés sont gérés")
    return root


def main_line(root) -> List:
    """The nodes of the main line, root first.

    A record may hold variations; we follow the first child throughout, which is the
    line the record is about. Branches are out of scope — see TODO.md.
    """
    line = [root]
    node = root
    while node.children:
        node = node.ordered_children[0]
        line.append(node)
    return line


def move_count(root) -> int:
    """Number of moves in the main line. The root is position zero, not a move."""
    return len(main_line(root)) - 1


def game_info(root) -> Dict[str, Any]:
    """What the record says about the game, for the sidebar.

    Absent properties come back as None rather than empty strings, so the app can
    tell "the record does not say" from "the record says nothing".
    """

    def text(name: str) -> Optional[str]:
        value = root.get_property(name, None)
        value = value.strip() if isinstance(value, str) else value
        return value or None

    return {
        "black_name": text("PB"),
        "white_name": text("PW"),
        "black_rank": text("BR"),
        "white_rank": text("WR"),
        "result": text("RE"),
        "date": text("DT"),
        "event": text("EV"),
        "game_name": text("GN"),
    }


def best_move(node, size: int) -> Optional[Dict[str, Any]]:
    """KataGo's first choice at this node, or None while it has nothing to say.

    A pass also comes back as None: there is no point to mark on the board, and the
    app has nothing to draw.
    """
    candidates = node.candidate_moves
    if not candidates:
        return None
    top = candidates[0]
    move = Move.from_gtp(top["move"], player=node.next_player)
    if move.is_pass:
        return None
    return {
        **to_display_coords(move.coords, size),
        "points_lost": round(top.get("pointsLost") or 0.0, 2),
    }


def variation(node) -> List[str]:
    """KataGo's own continuation from this node, as GTP moves.

    Comes straight out of the analysis, so walking it costs nothing. The colours
    alternate on their own: it is a line of play, not a list of candidates.
    """
    candidates = node.candidate_moves
    if not candidates:
        return []
    return list(candidates[0].get("pv") or [])


def progress(root) -> Dict[str, int]:
    """How much of the main line KataGo has finished, for the gauge.

    Counted on the main line rather than the whole tree: a record with variations
    would otherwise show a gauge that stalls on positions nobody is looking at.
    """
    line = main_line(root)
    return {"done": sum(1 for node in line if node.analysis_complete), "total": len(line)}
