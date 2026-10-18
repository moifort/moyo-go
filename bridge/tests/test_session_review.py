"""The session under review: navigation, bounds, and the variation branch.

Driven with the same fake engine as the scoring tests, so nothing here waits on
KataGo. Without a real engine no analysis ever comes back, which is exactly what
makes the navigation itself visible.
"""

import io
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

from protocol import EventWriter
from session import BridgeSession

RECORD = (
    "(;GM[1]FF[4]SZ[9]KM[6.5]RU[japanese]PB[Noir]PW[Blanc]RE[B+R]"
    ";B[ee];W[cc];B[gg];W[cg];B[gc])"
)


class FakeEngine:
    """Absorbs the analysis requests Game fires off; no KataGo involved."""

    def __getattr__(self, name):
        return lambda *args, **kwargs: None


@pytest.fixture
def session():
    stream = io.StringIO()
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge._stream = stream
    # The local reading goes through KaTrain's query builder, which a fake engine
    # cannot feed; the queries are kept here instead, for the tests to answer.
    bridge._local_queries = []
    bridge._send_local_query = lambda node, zone: bridge._local_queries.append((node, zone))
    return bridge


@pytest.fixture
def reviewing(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    return session


def run(session, method, *args):
    """Goes through the worker's own error policy, as a real command would."""
    session.run_task(method, *args)


def analysed(node, pv):
    """Stands in for KataGo: the parts of an analysis a review actually reads."""
    node.analysis = {
        "completed": True,
        "root": {"scoreLead": 0.0, "winrate": 0.5},
        "moves": {
            pv[0]: {
                "move": pv[0],
                "order": 0,
                "scoreLead": 0.0,
                "winrate": 0.5,
                "visits": 100,
                "pv": list(pv),
            }
        },
    }
    return node


def events(session):
    lines = session._stream.getvalue().strip().split("\n")
    return [json.loads(line) for line in lines if line]


def last_state(session):
    return [e for e in events(session) if e["event"] == "state"][-1]


def errors(session):
    return [e for e in events(session) if e["event"] == "error"]


def test_a_record_opens_at_its_last_move(reviewing):
    state = last_state(reviewing)
    assert state["status"] == "review"
    assert state["move_number"] == 5
    assert state["move_count"] == 5
    assert len(state["stones"]) == 5
    assert state["game_info"]["black_name"] == "Noir"
    assert state["result"] == "B+R"


def test_the_whole_record_is_on_the_chart_even_from_the_start(reviewing):
    run(reviewing, reviewing.goto, 2, 0)
    state = last_state(reviewing)
    assert state["move_number"] == 0
    # One entry per position of the record, not just the ones already walked.
    assert len(state["score_history"]) == 6
    assert state["stones"] == []


def test_navigation_is_clamped_at_both_ends(reviewing):
    run(reviewing, reviewing.goto, 2, 99)
    assert last_state(reviewing)["move_number"] == 5
    run(reviewing, reviewing.goto, 3, -4)
    assert last_state(reviewing)["move_number"] == 0
    assert errors(reviewing) == []


def test_no_marker_while_nothing_has_been_analysed(reviewing):
    assert last_state(reviewing)["best_move"] is None


def test_playing_commands_are_refused_while_reviewing(reviewing):
    run(reviewing, reviewing.play, 2, 0, 0)
    run(reviewing, reviewing.undo, 3)
    run(reviewing, reviewing.resign, 4)
    assert [e["code"] for e in errors(reviewing)] == ["not_playing"] * 3


def test_navigation_is_refused_outside_a_review(session):
    run(session, session.new_game, 1, 9, 6.5, "japanese", "B", "ai:human", {})
    run(session, session.goto, 2, 3)
    assert errors(session)[-1]["code"] == "not_reviewing"


def test_a_variation_needs_an_analysis_to_walk(reviewing):
    run(reviewing, reviewing.step_variation, 2, 1)
    assert errors(reviewing)[-1]["code"] == "no_variation"


def test_a_variation_is_played_then_taken_back_without_touching_the_record(reviewing):
    run(reviewing, reviewing.goto, 2, 2)
    anchor = reviewing.game.current_node
    children_before = list(anchor.children)
    analysed(anchor, ["A1", "A9"])

    run(reviewing, reviewing.step_variation, 3, 1)
    state = last_state(reviewing)
    assert state["variation_depth"] == 1
    assert len(state["stones"]) == 3
    # The position keeps the record's own move number; the depth says where we are.
    assert state["move_number"] == 2

    run(reviewing, reviewing.step_variation, 4, 1)
    assert last_state(reviewing)["variation_depth"] == 2
    assert len(last_state(reviewing)["stones"]) == 4

    run(reviewing, reviewing.step_variation, 5, -1)
    run(reviewing, reviewing.step_variation, 6, -1)
    assert last_state(reviewing)["variation_depth"] == 0
    assert reviewing.game.current_node is anchor
    assert [id(c) for c in anchor.children] == [id(c) for c in children_before]


def test_a_variation_landing_on_the_played_move_does_not_delete_the_record(reviewing):
    run(reviewing, reviewing.goto, 2, 2)
    anchor = reviewing.game.current_node
    played = anchor.ordered_children[0]
    # The engine's first choice is the move the record actually plays next.
    analysed(anchor, [played.move.gtp()])

    run(reviewing, reviewing.step_variation, 3, 1)
    assert reviewing.game.current_node is played
    run(reviewing, reviewing.step_variation, 4, -1)
    # Walking into the record must leave it whole.
    assert played in anchor.children
    assert reviewing._line[3] is played


def test_stepping_back_with_no_variation_says_so(reviewing):
    run(reviewing, reviewing.step_variation, 2, -1)
    assert errors(reviewing)[-1]["code"] == "no_variation"


def test_navigating_away_prunes_the_branch(reviewing):
    run(reviewing, reviewing.goto, 2, 1)
    anchor = reviewing.game.current_node
    analysed(anchor, ["A1"])
    run(reviewing, reviewing.step_variation, 3, 1)
    assert len(anchor.children) == 2

    run(reviewing, reviewing.goto, 4, 4)
    assert len(anchor.children) == 1
    assert last_state(reviewing)["variation_depth"] == 0


def test_a_new_game_leaves_the_review_behind(reviewing):
    run(reviewing, reviewing.new_game, 2, 9, 6.5, "japanese", "B", "ai:human", {})
    state = last_state(reviewing)
    assert state["status"] == "playing"
    assert "move_count" not in state
    assert reviewing._line == []


def test_an_unreadable_record_is_reported_not_crashed(session):
    run(session, session.load_sgf, 1, "vide.sgf", "")
    assert errors(session)[-1]["code"] == "bad_sgf"


def test_a_deepening_analysis_lets_the_walk_go_further(reviewing):
    """The first press often sees a one-move line; the walk must not freeze there."""
    run(reviewing, reviewing.goto, 2, 2)
    anchor = reviewing.game.current_node
    analysed(anchor, ["A1"])

    run(reviewing, reviewing.step_variation, 3, 1)
    assert last_state(reviewing)["variation_depth"] == 1

    # KataGo keeps pondering and comes back with a longer line from the same move.
    analysed(anchor, ["A1", "A9", "B1"])
    run(reviewing, reviewing.step_variation, 4, 1)
    assert last_state(reviewing)["variation_depth"] == 2
    assert errors(reviewing) == []


def test_a_line_that_disagrees_with_the_board_is_not_adopted(reviewing):
    """A refined analysis that changes its first move must not rewrite the branch."""
    run(reviewing, reviewing.goto, 2, 2)
    anchor = reviewing.game.current_node
    analysed(anchor, ["A1"])
    run(reviewing, reviewing.step_variation, 3, 1)

    # A different first move: the walk keeps the line already on the board.
    analysed(anchor, ["B1", "B9", "C1"])
    run(reviewing, reviewing.step_variation, 4, 1)
    assert errors(reviewing)[-1]["code"] == "no_variation"
    assert last_state(reviewing)["variation_depth"] == 1


# -- local reading -----------------------------------------------------------


def local_answer(pv, score_lead=0.0):
    """Stands in for KataGo's answer to a query kept inside the zone."""
    return {"moveInfos": [{"move": pv[0], "order": 0, "scoreLead": score_lead, "pv": list(pv)}]}


def test_only_the_position_on_screen_is_read_locally(reviewing):
    assert [node for node, _ in reviewing._local_queries] == [reviewing._line[5]]
    run(reviewing, reviewing.goto, 2, 2)
    run(reviewing, reviewing.goto, 3, 5)
    # Coming back to a position already read does not ask again.
    assert [node for node, _ in reviewing._local_queries] == [reviewing._line[5], reviewing._line[2]]


def test_the_zone_is_sent_before_the_answer(reviewing):
    state = last_state(reviewing)
    # The last move is B[gc]: row 2, col 6 on a 9×9 board.
    assert state["local_zone"] == {"top": 0, "left": 2, "bottom": 6, "right": 8}
    assert state["local_move"] is None


def test_the_local_move_comes_with_its_cost(reviewing):
    node = reviewing._line[5]
    analysed(node, ["E7"])
    node.analysis["root"]["scoreLead"] = 4.0  # Black leads by 4 with White to move
    run(reviewing, reviewing._on_local_analysis, node, local_answer(["G6", "H6"], score_lead=6.5))
    state = last_state(reviewing)
    assert state["local_move"] == {"row": 3, "col": 6, "points_lost": 2.5}
    # The whole-board marker is untouched by the local reading.
    assert state["best_move"]["col"] == 4


def test_a_late_answer_for_another_position_is_kept_silent(reviewing):
    node = reviewing._line[5]
    run(reviewing, reviewing.goto, 2, 2)
    count = len([e for e in events(reviewing) if e["event"] == "state"])
    run(reviewing, reviewing._on_local_analysis, node, local_answer(["G6"]))
    assert len([e for e in events(reviewing) if e["event"] == "state"]) == count
    run(reviewing, reviewing.goto, 3, 5)
    assert last_state(reviewing)["local_move"]["col"] == 6


def test_the_local_sequence_is_walked_and_stops_at_the_zone(reviewing):
    node = reviewing._line[5]
    # The third move leaves the zone, whose left edge is column C.
    run(reviewing, reviewing._on_local_analysis, node, local_answer(["G6", "H6", "A1"]))
    run(reviewing, reviewing.step_variation, 2, 1, "local")
    state = last_state(reviewing)
    assert state["variation_kind"] == "local"
    assert state["variation_depth"] == 1
    assert state["best_move"] is None
    assert state["local_move"] == {"row": 3, "col": 7, "points_lost": None}

    run(reviewing, reviewing.step_variation, 3, 1, "local")
    run(reviewing, reviewing.step_variation, 4, 1, "local")
    assert errors(reviewing)[-1]["message"] == "la séquence locale s'arrête là"
    assert last_state(reviewing)["variation_depth"] == 2


def test_switching_lines_starts_again_from_the_record(reviewing):
    node = reviewing._line[5]
    analysed(node, ["A1", "A9"])
    run(reviewing, reviewing._on_local_analysis, node, local_answer(["G6", "H6"]))
    run(reviewing, reviewing.step_variation, 2, 1, "local")
    run(reviewing, reviewing.step_variation, 3, 1, "local")
    run(reviewing, reviewing.step_variation, 4, 1, "best")
    state = last_state(reviewing)
    assert state["variation_kind"] == "best"
    assert state["variation_depth"] == 1
    assert state["local_zone"] is None
    assert len(node.children) == 1  # the local branch is gone

    run(reviewing, reviewing.step_variation, 5, -1)
    assert last_state(reviewing)["variation_kind"] is None
    assert last_state(reviewing)["local_zone"] is not None


def test_a_local_walk_waits_for_its_answer(reviewing):
    run(reviewing, reviewing.step_variation, 2, 1, "local")
    assert errors(reviewing)[-1]["message"] == "l'analyse locale n'est pas encore revenue"


def test_the_first_position_has_no_fight(reviewing):
    run(reviewing, reviewing.goto, 2, 0)
    assert last_state(reviewing)["local_zone"] is None
    run(reviewing, reviewing.step_variation, 3, 1, "local")
    assert errors(reviewing)[-1]["message"] == "aucun combat local à cette position"


def test_a_whole_board_choice_inside_the_zone_is_the_local_move_too(reviewing):
    node = reviewing._line[5]
    analysed(node, ["G6", "H6"])  # inside the zone around G7
    # The local search, noisier, ranks another move first.
    answer = {
        "moveInfos": [
            {"move": "H7", "order": 0, "scoreLead": 0.3, "pv": ["H7"]},
            {"move": "G6", "order": 1, "scoreLead": 0.6, "pv": ["G6", "H5", "H6"]},
        ]
    }
    run(reviewing, reviewing._on_local_analysis, node, answer)
    state = last_state(reviewing)
    assert state["local_move"] == {"row": 3, "col": 6, "points_lost": 0.0}
    assert state["best_move"]["row"] == 3 and state["best_move"]["col"] == 6
    # The sequence walked is the local reading of that same move.
    run(reviewing, reviewing.step_variation, 2, 1, "local")
    run(reviewing, reviewing.step_variation, 3, 1, "local")
    assert last_state(reviewing)["local_move"] == {"row": 3, "col": 7, "points_lost": None}
