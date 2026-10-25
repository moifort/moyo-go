"""The analysis mode: stones placed by hand, the tree they grow, and the two cursors.

Driven with a fake engine, so no analysis ever comes back: what is tested is who
moves where, which nodes the tree shows, and what a save keeps.
"""

import io
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

from protocol import CommandError, EventWriter
from session import BridgeSession

RECORD = (
    "(;GM[1]FF[4]SZ[9]KM[6.5]RU[japanese]PB[Noir]PW[Blanc]RE[B+R]"
    ";B[ee];W[cc];B[gg];W[cg];B[gc])"
)
SIZE = 9


class FakeEngine:
    """Absorbs the analysis requests Game fires off; no KataGo involved."""

    def __getattr__(self, name):
        return lambda *args, **kwargs: None


def make_session():
    stream = io.StringIO()
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge._stream = stream
    bridge._send_local_query = lambda node, zone: None
    return bridge


@pytest.fixture
def reviewing():
    bridge = make_session()
    bridge.load_sgf(1, "partie.sgf", RECORD)
    return bridge


@pytest.fixture
def playing():
    """A game against an AI that never gets to move: KataGo never answers."""
    bridge = make_session()
    bridge.new_game(1, SIZE, 6.5, "japanese", "B", "ai:human", {})
    return bridge


def events(session, kind=None):
    lines = session._stream.getvalue().strip().split("\n")
    found = [json.loads(line) for line in lines if line]
    return [e for e in found if kind is None or e["event"] == kind]


def last_state(session):
    return events(session, "state")[-1]


def last_tree(session):
    return events(session, "tree")[-1]["nodes"]


def tree_node(session, node):
    number = session._number(node)
    return next(entry for entry in last_tree(session) if entry["id"] == number)


def rows(*stones):
    grid = [["."] * SIZE for _ in range(SIZE)]
    for r, c, color in stones:
        grid[r][c] = "X" if color == "B" else "O"
    return ["".join(line) for line in grid]


def analysed(node, pv):
    """Stands in for KataGo: the parts of an analysis a review actually reads."""
    node.analysis = {
        "completed": True,
        "root": {"scoreLead": 0.0, "winrate": 0.5},
        "moves": {
            pv[0]: {"move": pv[0], "order": 0, "scoreLead": 0.0, "winrate": 0.5, "visits": 100, "pv": list(pv)}
        },
    }
    return node


# -- the toggle ---------------------------------------------------------------


def test_a_record_is_read_in_analysis_with_no_live_game(reviewing):
    state = last_state(reviewing)
    assert state["view"] == "analysis"
    assert state["live_node_id"] is None
    with pytest.raises(CommandError) as exc:
        reviewing.set_view(2, "live")
    assert exc.value.code == "no_live_game"


def test_analysis_sets_the_game_aside_and_live_brings_it_back(playing):
    playing.play(2, 4, 4)
    live = playing.game.current_node
    playing.set_view(3, "analysis")
    assert last_state(playing)["live_node_id"] == playing._number(live)
    playing.play(4, 2, 2)
    playing.play(5, 6, 6)
    assert playing.game.current_node is not live
    playing.set_view(6, "live")
    assert playing.game.current_node is live
    state = last_state(playing)
    assert state["view"] == "live"
    assert state["node_id"] == state["live_node_id"] == playing._number(live)


def test_both_colours_are_placed_by_hand_in_analysis(playing):
    playing.set_view(2, "analysis")
    playing.play(3, 4, 4)
    playing.play(4, 2, 2)
    assert [n.move.player for n in playing.game.current_node.nodes_from_root[1:]] == ["B", "W"]


def test_the_ai_waits_while_the_player_analyses(playing):
    calls = []
    playing._ai_pending = True
    playing.set_view(2, "analysis")
    original = playing._maybe_play_ai_move
    playing._maybe_play_ai_move = lambda: calls.append(playing._analysing()) or original()
    playing._on_state_advanced()
    assert calls == []  # an analysis landing in analysis never reaches the AI
    playing.set_view(3, "live")
    assert calls == [False]
    assert events(playing, "thinking")[-1]["value"] is True


def test_asking_for_the_analysis_while_counting_settles_the_count(playing):
    playing.play_pass(2)
    playing.game.play(__import__("pysgf").Move(coords=None, player="W"))
    playing._enter_scoring()
    playing.set_view(3, "analysis")
    state = last_state(playing)
    assert state["status"] == "finished"
    assert state["view"] == "analysis"
    assert state["result"]


def test_a_counted_game_opens_in_analysis(playing):
    playing.play_pass(2)
    playing.game.play(__import__("pysgf").Move(coords=None, player="W"))
    playing._enter_scoring()
    playing.accept_score(3)
    state = last_state(playing)
    assert state["status"] == "finished"
    assert state["view"] == "analysis"
    assert state["result"]


# -- the tree -----------------------------------------------------------------


def test_a_stone_on_a_record_opens_a_branch(reviewing):
    reviewing.goto(2, 2)
    fork = reviewing.game.current_node
    reviewing.play(3, 0, 0)
    branch = reviewing.game.current_node
    assert branch.parent is fork
    assert tree_node(reviewing, branch)["origin"] == "analysis"
    assert tree_node(reviewing, fork)["origin"] == "game"
    assert last_state(reviewing)["move_number"] == 3
    # The chart stays the game's.
    assert last_state(reviewing)["move_count"] == 5


def test_a_move_already_there_is_walked_into_not_doubled(reviewing):
    reviewing.goto(2, 0)
    first = reviewing._line[1]
    point = first.move.coords
    from protocol import to_display_coords

    spot = to_display_coords(point, SIZE)
    reviewing.play(3, spot["row"], spot["col"])
    assert reviewing.game.current_node is first
    assert len(reviewing.game.root.children) == 1


def test_a_click_in_the_tree_goes_there(reviewing):
    reviewing.goto(2, 1)
    reviewing.play(3, 0, 0)
    branch = reviewing.game.current_node
    reviewing.goto(4, 5)
    reviewing.goto_node(5, reviewing._number(branch))
    assert reviewing.game.current_node is branch


def test_a_click_in_the_tree_from_the_live_view_enters_analysis(playing):
    playing.play(2, 4, 4)
    first = playing.game.current_node
    playing.goto_node(4, playing._number(playing.game.root))
    state = last_state(playing)
    assert state["view"] == "analysis"
    assert state["live_node_id"] == playing._number(first)
    assert playing.game.current_node is playing.game.root


def test_forward_stays_on_the_line_and_never_enters_a_branch(reviewing):
    reviewing.goto(2, 2)
    fork = reviewing.game.current_node
    reviewing.play(3, 0, 0)
    reviewing.navigate(4, "back")
    assert reviewing.game.current_node is fork
    reviewing.navigate(5, "forward")
    assert reviewing.game.current_node is reviewing._line[3]


def test_forward_inside_a_branch_carries_on_down_it(reviewing):
    reviewing.goto(2, 2)
    reviewing.play(3, 0, 0)
    branch = reviewing.game.current_node
    reviewing.play(4, 0, 8)
    deep = reviewing.game.current_node
    reviewing.goto_node(5, reviewing._number(branch))
    reviewing.navigate(6, "forward")
    assert reviewing.game.current_node is deep


def test_down_enters_the_branches_of_a_fork_one_after_the_other(reviewing):
    reviewing.goto(2, 2)
    fork = reviewing.game.current_node
    reviewing.play(3, 0, 0)
    first = reviewing.game.current_node
    reviewing.goto(4, 2)
    reviewing.play(5, 8, 8)
    second = reviewing.game.current_node
    reviewing.goto(6, 2)
    reviewing.navigate(7, "next_sibling")
    assert reviewing.game.current_node is first
    reviewing.navigate(8, "next_sibling")
    assert reviewing.game.current_node is second
    reviewing.navigate(9, "previous_sibling")
    reviewing.navigate(10, "previous_sibling")
    assert reviewing.game.current_node is reviewing._line[3]
    assert reviewing.game.current_node.parent is fork


def test_siblings_and_the_way_back_to_the_game(reviewing):
    reviewing.goto(2, 2)
    fork = reviewing.game.current_node
    reviewing.play(3, 0, 0)
    reviewing.play(4, 0, 8)
    deep = reviewing.game.current_node
    reviewing.navigate(5, "back")
    reviewing.navigate(6, "previous_sibling")
    # The branch was played after the game's own move: the game's move comes first.
    assert reviewing.game.current_node is reviewing._line[3]
    reviewing.navigate(7, "next_sibling")
    assert reviewing.game.current_node is deep.parent
    reviewing.goto_node(8, reviewing._number(deep))
    reviewing.navigate(9, "game")
    assert reviewing.game.current_node is fork
    reviewing.navigate(10, "end")
    assert reviewing.game.current_node is reviewing._line[-1]


def test_start_and_nowhere_to_go(reviewing):
    reviewing.navigate(2, "start")
    assert reviewing.game.current_node is reviewing.game.root
    reviewing.navigate(3, "back")
    assert reviewing.game.current_node is reviewing.game.root
    with pytest.raises(CommandError):
        reviewing.navigate(4, "sideways")


def test_moves_taken_back_against_the_ai_are_hidden(playing):
    playing.play(2, 4, 4)
    playing.game.play(__import__("pysgf").Move.from_gtp("C3", player="W"))
    undone = playing.game.current_node
    playing.undo(3)
    playing.play(4, 6, 6)
    shown = {entry["id"] for entry in last_tree(playing)}
    assert playing._number(undone) not in shown
    assert playing._number(playing.game.current_node) in shown


def test_a_branch_from_a_move_taken_back_brings_it_into_view(playing):
    playing.play(2, 4, 4)
    first = playing.game.current_node
    playing.set_view(3, "analysis")
    playing.play(4, 2, 2)
    branch = playing.game.current_node
    playing.set_view(5, "live")
    playing.undo(6)
    playing.play(7, 6, 6)
    shown = {entry["id"] for entry in last_tree(playing)}
    assert playing._number(first) in shown
    assert playing._number(branch) in shown


def test_the_tree_is_sent_only_when_its_shape_changes(reviewing):
    before = len(events(reviewing, "tree"))
    reviewing.goto(2, 1)
    reviewing.goto(3, 3)
    assert len(events(reviewing, "tree")) == before
    reviewing.play(4, 0, 0)
    assert len(events(reviewing, "tree")) == before + 1


# -- the preview of KataGo's line ---------------------------------------------


def test_a_preview_left_with_the_arrows_stays_as_a_branch(reviewing):
    reviewing.goto(2, 2)
    anchor = analysed(reviewing.game.current_node, ["A1", "J9"])
    reviewing.step_variation(3, 1)
    first = reviewing.game.current_node
    reviewing.step_variation(4, 1)
    assert tree_node(reviewing, first)["origin"] == "preview"
    reviewing.navigate(5, "back")
    # One move back along what is now a branch, not out of it.
    assert reviewing.game.current_node is first
    assert reviewing._variation == []
    assert tree_node(reviewing, first)["origin"] == "analysis"
    reviewing.navigate(6, "back")
    assert reviewing.game.current_node is anchor
    reviewing.play(7, 8, 8)
    assert len(anchor.children) == 3  # the game, KataGo's line kept, the new stone


def test_a_preview_taken_back_with_its_own_key_leaves_no_trace(reviewing):
    reviewing.goto(2, 2)
    anchor = analysed(reviewing.game.current_node, ["A1", "J9"])
    reviewing.step_variation(3, 1)
    reviewing.step_variation(4, -1)
    assert reviewing.game.current_node is anchor
    assert all(child is reviewing._line[3] for child in anchor.children)


def test_a_stone_placed_from_a_preview_keeps_it(reviewing):
    reviewing.goto(2, 2)
    anchor = analysed(reviewing.game.current_node, ["A1", "J9"])
    reviewing.step_variation(3, 1)
    walked = reviewing.game.current_node
    reviewing.play(4, 4, 0)
    assert reviewing.game.current_node.parent is walked
    assert reviewing._variation == []
    assert tree_node(reviewing, walked)["origin"] == "analysis"
    reviewing.navigate(5, "game")
    assert any(child is walked for child in anchor.children)


def test_a_click_on_a_preview_move_keeps_the_whole_line(reviewing):
    reviewing.goto(2, 2)
    analysed(reviewing.game.current_node, ["A1", "J9", "A9"])
    reviewing.step_variation(3, 1)
    first = reviewing.game.current_node
    reviewing.step_variation(4, 1)
    second = reviewing.game.current_node
    reviewing.goto_node(5, reviewing._number(first))
    assert reviewing.game.current_node is first
    assert reviewing._variation == []
    assert tree_node(reviewing, second)["origin"] == "analysis"


# -- deleting -----------------------------------------------------------------


def test_deleting_a_branch_takes_the_player_back_to_its_fork(reviewing):
    reviewing.goto(2, 2)
    fork = reviewing.game.current_node
    reviewing.play(3, 0, 0)
    branch = reviewing.game.current_node
    reviewing.play(4, 0, 8)
    reviewing.delete_branch(5, reviewing._number(branch))
    assert reviewing.game.current_node is fork
    assert all(child is not branch for child in fork.children)
    assert reviewing._analysis_nodes == {}


def test_the_game_and_the_record_cannot_be_deleted(reviewing):
    with pytest.raises(CommandError) as exc:
        reviewing.delete_branch(2, reviewing._number(reviewing._line[2]))
    assert exc.value.code == "not_analysis_node"


def test_undo_in_analysis_takes_back_the_last_stone_placed(reviewing):
    reviewing.goto(2, 2)
    fork = reviewing.game.current_node
    reviewing.play(3, 0, 0)
    reviewing.undo(4)
    assert reviewing.game.current_node is fork
    with pytest.raises(CommandError) as exc:
        reviewing.undo(5)
    assert exc.value.code == "nothing_to_undo"


# -- following the real board in analysis -------------------------------------


@pytest.fixture
def following():
    bridge = make_session()
    bridge.follow_start(1, SIZE, 6.5, "japanese")
    bridge.follow_board(2, rows())
    bridge.follow_board(3, rows((2, 2, "B")))
    return bridge


def test_the_real_board_is_followed_behind_the_analysis(following):
    following.set_view(4, "analysis")
    following.play(5, 6, 6)
    cursor = following.game.current_node
    following.follow_board(6, rows((2, 2, "B"), (4, 4, "W")))
    assert following.game.current_node is cursor
    live = following._live
    assert live.move.player == "W" and live.depth == 2
    state = last_state(following)
    assert state["live_node_id"] == following._number(live)
    assert state["move_count"] == 2
    following.set_view(7, "live")
    assert following.game.current_node is live


def test_the_real_board_walking_into_a_branch_makes_it_the_game(following):
    following.set_view(4, "analysis")
    following.play(5, 4, 4)
    branch = following.game.current_node
    following.follow_board(6, rows((2, 2, "B"), (4, 4, "W")))
    assert following._live is branch
    assert tree_node(following, branch)["origin"] == "game"
    with pytest.raises(CommandError):
        following.delete_branch(7, following._number(branch))


def test_a_game_ending_while_analysed_keeps_the_position_read(following):
    following.set_view(4, "analysis")
    following.play(5, 6, 6)
    cursor = following.game.current_node
    following.follow_end(6, "B+R")
    state = last_state(following)
    assert state["status"] == "review"
    assert following.game.current_node is cursor
    assert state["move_count"] == 1


# -- saving -------------------------------------------------------------------


def test_a_save_keeps_the_branches_and_drops_the_moves_taken_back(playing):
    playing.play(2, 4, 4)
    playing.game.play(__import__("pysgf").Move.from_gtp("C3", player="W"))
    playing.undo(3)  # both moves: back to Black's turn at the root
    playing.play(4, 4, 4)  # replayed: the move taken back hangs off it, unseen
    playing.set_view(5, "analysis")
    playing.play(6, 0, 0)
    playing.set_view(6, "live")
    playing.export_sgf(7, None, None)
    text = events(playing, "sgf")[-1]["contents"]
    assert "W[aa]" in text
    assert "W[cg]" not in text
    assert "B[ee]" in text


def test_a_record_saves_with_its_branches_and_the_players(reviewing):
    reviewing.goto(2, 2)
    reviewing.play(3, 0, 0)
    reviewing.export_sgf(4, None, None)
    text = events(reviewing, "sgf")[-1]["contents"]
    assert text.count("(") == 3  # the record, and two lines from the fork
    assert "PB[Noir]" in text
