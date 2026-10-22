import io
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

import follow
from protocol import CommandError, EventWriter
from session import BridgeSession


class FakeEngine:
    """Absorbs the analysis requests Game fires off; no KataGo involved."""

    def __init__(self):
        self.analysed = 0

    def __getattr__(self, name):
        return lambda *args, **kwargs: None


SIZE = 9


def rows(*stones):
    """A 9x9 board from (row, col, colour) triples."""
    grid = [["."] * SIZE for _ in range(SIZE)]
    for r, c, color in stones:
        grid[r][c] = "X" if color == "B" else "O"
    return ["".join(line) for line in grid]


@pytest.fixture
def stream():
    return io.StringIO()


@pytest.fixture
def session(stream):
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    # The review a game ends in reads locally, through a query builder a fake engine
    # cannot feed.
    bridge._local_queries = []
    bridge._send_local_query = lambda node, zone: bridge._local_queries.append((node, zone))
    bridge.follow_start(1, SIZE, 6.5, "japanese")
    bridge.follow_board(2, rows())
    return bridge


def last_state(stream):
    events = [json.loads(line) for line in stream.getvalue().splitlines()]
    return [event for event in events if event["event"] == "state"][-1]


def board(session):
    return {(r, c): color for (r, c), color in sorted(_stones(session).items())}


def _stones(session):
    import serialize

    return serialize.stone_map(session.game)


def test_nobody_is_to_move_on_the_mac(session, stream):
    state = last_state(stream)
    assert state["status"] == "following"
    assert state["in_sync"] is True
    with pytest.raises(CommandError):
        session.undo(3)


def test_a_click_while_following_opens_the_analysis(session, stream):
    session.follow_board(3, rows((2, 2, "B")))
    live = session.game.current_node
    session.play(4, 4, 4)
    state = last_state(stream)
    assert state["view"] == "analysis"
    assert state["status"] == "following"
    assert session.game.current_node.parent is live
    assert session._live is live


def test_one_new_stone_is_a_move(session, stream):
    session.follow_board(3, rows((2, 2, "B")))
    assert session.game.current_node.depth == 1
    assert last_state(stream)["move_number"] == 1
    session.follow_board(4, rows((2, 2, "B"), (6, 6, "W")))
    assert session.game.current_node.depth == 2
    assert session.game.current_node.next_player == "B"


def test_two_new_stones_are_two_moves(session):
    session.follow_board(3, rows((2, 2, "B"), (6, 6, "W")))
    assert session.game.current_node.depth == 2
    assert session.game.current_node.parent.move.player == "B"


def test_a_stone_of_the_wrong_colour_comes_after_a_pass(session):
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_board(4, rows((2, 2, "B"), (3, 3, "B")))
    node = session.game.current_node
    assert node.depth == 3
    assert node.parent.is_pass


def test_a_capture_is_read_through_the_rules(session):
    # White's stone at (0, 0) is captured by Black's second stone.
    session.follow_board(3, rows((0, 1, "B")))
    session.follow_board(4, rows((0, 1, "B"), (0, 0, "W")))
    session.follow_board(5, rows((0, 1, "B"), (1, 0, "B")))
    assert session.game.current_node.depth == 3
    assert session.game.prisoner_count["W"] == 1


def test_a_stone_lifted_is_a_move_taken_back(session, stream):
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_board(4, rows((2, 2, "B"), (6, 6, "W")))
    session.follow_board(5, rows((2, 2, "B")))
    assert session.game.current_node.depth == 1
    assert last_state(stream)["in_sync"] is True


def test_a_misread_stone_is_corrected(session):
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_board(4, rows((2, 2, "B"), (6, 6, "W")))
    # The white stone was really one line further.
    session.follow_board(5, rows((2, 2, "B"), (6, 7, "W")))
    node = session.game.current_node
    assert node.depth == 2
    assert board(session) == {(2, 2): "B", (6, 7): "W"}


def test_several_moves_seen_at_once_are_all_played(session, stream):
    session.follow_board(3, rows((2, 2, "B")))
    # Three moves went by before the phone sent the board: White, Black, White.
    session.follow_board(4, rows((2, 2, "B"), (6, 6, "W"), (4, 4, "B"), (0, 8, "W")))
    node = session.game.current_node
    assert node.depth == 4
    assert [n.move.player for n in node.nodes_from_root[1:]] == ["B", "W", "B", "W"]
    assert last_state(stream)["in_sync"] is True


def test_a_position_out_of_reach_is_shown_as_placed_stones(session, stream):
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_board(4, rows((2, 2, "B"), (3, 3, "B"), (4, 4, "B")))
    # No moves explain it: the stones are placed, so the Mac shows the real board.
    assert board(session) == {(2, 2): "B", (3, 3): "B", (4, 4): "B"}
    assert session.game.current_node.move is None
    assert last_state(stream)["in_sync"] is False
    # The next move seen is followed from there.
    session.follow_board(5, rows((2, 2, "B"), (3, 3, "B"), (4, 4, "B"), (6, 6, "W")))
    assert session.game.current_node.move.player == "W"
    assert last_state(stream)["in_sync"] is True


def test_a_misread_board_is_left_when_the_game_comes_back(session, stream):
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_board(4, rows((2, 2, "B"), (3, 3, "B"), (4, 4, "B")))
    session.follow_board(5, rows((2, 2, "B"), (6, 6, "W")))
    node = session.game.current_node
    assert node.depth == 2
    assert node.move.player == "W"
    assert last_state(stream)["in_sync"] is True


def test_placed_stones_can_lift_and_turn_stones(session, stream):
    for n, stones in enumerate(
        [
            [(2, 2, "B")],
            [(2, 2, "B"), (6, 6, "W")],
            [(2, 2, "B"), (6, 6, "W"), (4, 4, "B")],
            [(2, 2, "B"), (6, 6, "W"), (4, 4, "B"), (0, 0, "W")],
            [(2, 2, "B"), (6, 6, "W"), (4, 4, "B"), (0, 0, "W"), (8, 8, "B")],
        ]
    ):
        session.follow_board(3 + n, rows(*stones))
    # The first stone is gone, the second changed colour, two black stones appeared.
    seen = [(6, 6, "B"), (4, 4, "B"), (0, 0, "W"), (8, 8, "B"), (1, 1, "B"), (7, 7, "B")]
    session.follow_board(10, rows(*seen))
    assert board(session) == {(r, c): color for r, c, color in seen}
    assert last_state(stream)["in_sync"] is False


def test_an_illegal_board_leaves_no_trace_in_the_tree(session):
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_board(4, rows((2, 2, "B"), (3, 3, "B"), (4, 4, "B")))
    assert len(session.game.current_node.children) == 0


def test_a_game_joined_halfway_starts_from_the_position_seen(stream):
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge.follow_start(1, SIZE, 6.5, "japanese")
    bridge.follow_board(2, rows((2, 2, "B"), (6, 6, "W")))
    assert bridge.game.current_node.depth == 0
    assert board(bridge) == {(2, 2): "B", (6, 6): "W"}
    assert bridge.game.current_node.next_player == "B"
    # White was in fact to move: the first move seen settles it, with no pass.
    bridge.follow_board(3, rows((2, 2, "B"), (6, 6, "W"), (4, 4, "W")))
    assert bridge.game.current_node.depth == 1
    assert bridge.game.current_node.move.player == "W"


def joined(stream, board, history):
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge.follow_start(1, SIZE, 6.5, "japanese")
    bridge.follow_board(2, board, history)
    return bridge


def test_a_game_joined_with_its_history_keeps_its_moves(stream):
    # Black captures White's corner stone: the prisoner is counted on the Mac too.
    history = {
        "setup_black": [], "setup_white": [],
        "moves": [
            {"color": "B", "point": [0, 1]},
            {"color": "W", "point": [0, 0]},
            {"color": "B", "point": [1, 0]},
            {"color": "W"},
        ],
    }
    bridge = joined(stream, rows((0, 1, "B"), (1, 0, "B")), history)
    node = bridge.game.current_node
    assert node.depth == 4
    assert node.is_pass
    assert bridge.game.prisoner_count["W"] == 1
    assert node.next_player == "B"
    assert last_state(stream)["in_sync"] is True
    bridge.follow_board(3, rows((0, 1, "B"), (1, 0, "B"), (4, 4, "B")))
    assert bridge.game.current_node.depth == 5


def test_the_history_starts_from_its_setup(stream):
    history = {"setup_black": [[2, 2], [6, 6]], "setup_white": [], "moves": [{"color": "W", "point": [4, 4]}]}
    bridge = joined(stream, rows((2, 2, "B"), (6, 6, "B"), (4, 4, "W")), history)
    assert bridge.game.root.placements
    assert bridge.game.current_node.depth == 1
    assert bridge.game.current_node.move.player == "W"


def test_erased_stones_are_cleared_before_their_move(stream):
    history = {
        "setup_black": [], "setup_white": [],
        "moves": [{"color": "B", "point": [2, 2]}, {"color": "W", "point": [6, 6], "erased": [[2, 2]]}],
    }
    bridge = joined(stream, rows((6, 6, "W")), history)
    assert board(bridge) == {(6, 6): "W"}
    assert bridge.game.current_node.move.player == "W"
    assert last_state(stream)["in_sync"] is True


def test_a_history_that_misses_the_board_still_lands_on_it(stream):
    history = {"setup_black": [], "setup_white": [], "moves": [{"color": "B", "point": [2, 2]}]}
    bridge = joined(stream, rows((2, 2, "B"), (6, 6, "W")), history)
    assert bridge.game.current_node.depth == 2
    assert board(bridge) == {(2, 2): "B", (6, 6): "W"}


def test_an_illegal_history_stops_where_the_rules_do(stream):
    history = {
        "setup_black": [], "setup_white": [],
        "moves": [{"color": "B", "point": [2, 2]}, {"color": "W", "point": [2, 2]}],
    }
    bridge = joined(stream, rows((2, 2, "B")), history)
    assert bridge.game.current_node.depth == 1
    assert last_state(stream)["in_sync"] is True


def test_the_end_opens_the_line_followed_as_a_record(session, stream):
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_board(4, rows((2, 2, "B"), (6, 6, "W")))
    session.follow_board(5, rows((2, 2, "B"), (6, 7, "W")))
    session.follow_end(6, "B+R")
    state = last_state(stream)
    assert state["status"] == "review"
    assert state["move_number"] == 2
    assert state["move_count"] == 2
    assert state["game_info"]["result"] == "B+R"
    assert board(session) == {(2, 2): "B", (6, 7): "W"}
    with pytest.raises(CommandError):
        session.follow_board(7, rows())


def test_candidates_list_the_likely_sequences():
    assert follow.candidates({}, {(0, 0): "B"}, "B") == [[("B", (0, 0))]]
    assert follow.candidates({}, {(0, 0): "W"}, "B") == [[None, ("W", (0, 0))]]
    assert follow.candidates({}, {(0, 0): "W", (1, 1): "B"}, "B") == [[("B", (1, 1)), ("W", (0, 0))]]
    assert follow.candidates({}, {(0, 0): "B", (1, 1): "B"}, "B") == []
    three = follow.candidates({}, {(0, 0): "B", (1, 1): "W", (2, 2): "B"}, "B")
    assert three == [
        [("B", (0, 0)), ("W", (1, 1)), ("B", (2, 2))],
        [("B", (2, 2)), ("W", (1, 1)), ("B", (0, 0))],
    ]
    assert follow.candidates({}, {(0, 0): "W", (1, 1): "W", (2, 2): "B"}, "B") == [
        [None, ("W", (0, 0)), ("B", (2, 2)), ("W", (1, 1))],
        [None, ("W", (1, 1)), ("B", (2, 2)), ("W", (0, 0))],
    ]


def test_rows_of_the_wrong_size_are_refused():
    with pytest.raises(CommandError):
        follow.read_rows(["..."], SIZE)


# -- KataGo's suggestions while following -------------------------------------


@pytest.fixture
def hinted(stream):
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge._local_queries = []
    bridge._send_local_query = lambda node, zone: bridge._local_queries.append((node, zone))
    bridge.follow_start(1, SIZE, 6.5, "japanese", analysis=True)
    bridge.follow_board(2, rows())
    return bridge


def test_without_suggestions_nothing_is_read_locally(session, stream):
    session._local_queries = []
    session._send_local_query = lambda node, zone: session._local_queries.append((node, zone))
    session.follow_board(3, rows((2, 2, "B")))
    assert session._local_queries == []
    state = last_state(stream)
    assert state["analysis"] is False
    assert "best_move" not in state


def test_with_suggestions_every_move_is_read_around_it(hinted, stream):
    hinted.follow_board(3, rows((2, 2, "B")))
    hinted.follow_board(4, rows((2, 2, "B"), (6, 6, "W")))
    assert [node for node, _ in hinted._local_queries] == [
        hinted.game.current_node.parent,
        hinted.game.current_node,
    ]
    state = last_state(stream)
    assert state["analysis"] is True
    assert state["local_zone"] is not None
    assert state["local_pending"] is True


def test_the_local_answer_lands_on_the_board(hinted, stream):
    hinted.follow_board(3, rows((2, 2, "B")))
    node = hinted.game.current_node
    zone = hinted._local_queries[-1][1]
    answer = {"moveInfos": [{"move": "D7", "order": 0, "scoreLead": 0.0, "pv": ["D7"]}]}
    hinted._on_local_analysis(node, answer, zone)
    state = last_state(stream)
    assert state["local_move"]["row"] == 2 and state["local_move"]["col"] == 3
    assert state["local_pending"] is False


def test_suggestions_can_be_switched_on_mid_game(session, stream):
    session._local_queries = []
    session._send_local_query = lambda node, zone: session._local_queries.append((node, zone))
    session.follow_board(3, rows((2, 2, "B")))
    session.follow_analysis(4, True)
    assert len(session._local_queries) == 1
    assert last_state(stream)["analysis"] is True
    session.follow_analysis(5, False)
    assert "local_zone" not in last_state(stream)


class CountingEngine(FakeEngine):
    """Counts what KataGo is asked, and what is called off."""

    def __init__(self):
        self.asked = []
        self.terminated = 0

    def request_analysis(self, node, *args, **kwargs):
        self.asked.append(node)

    def terminate_queries(self, *args, **kwargs):
        self.terminated += 1


def test_with_the_analysis_off_katago_is_asked_nothing(stream):
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = CountingEngine()
    bridge._send_local_query = lambda node, zone: None
    bridge.follow_start(1, SIZE, 6.5, "japanese", analysis=False)
    bridge.follow_board(2, rows())
    before = len(bridge._engine.asked)
    bridge.follow_board(3, rows((2, 2, "B")))
    bridge.follow_board(4, rows((2, 2, "B"), (6, 6, "W")))
    assert len(bridge._engine.asked) == before
    # On again: the position on the board first, then the moves played meanwhile.
    bridge.follow_analysis(5, True)
    assert bridge._engine.asked[before] is bridge.game.current_node
    bridge.follow_analysis(6, False)
    assert bridge._engine.terminated == 1
