"""What the library needs from the bridge: a game kept as it goes, and picked up again.

Same fake engine as the other session tests: no analysis ever comes back, so the AI
never moves on its own, and a game here is whatever the tests play.
"""

import io
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

from katrain.core.constants import PLAYER_HUMAN, PLAYING_NORMAL

import review
from protocol import EventWriter
from session import BridgeSession

RECORD = (
    "(;GM[1]FF[4]SZ[9]KM[6.5]RU[japanese]PB[Noir]PW[Blanc]RE[B+R]GN[Finale]"
    ";B[ee];W[cc];B[gg];W[cg];B[gc])"
)


class FakeEngine:
    def __getattr__(self, name):
        return lambda *args, **kwargs: None


@pytest.fixture
def session():
    stream = io.StringIO()
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge._stream = stream
    bridge._local_queries = []
    bridge._send_local_query = lambda node, zone: bridge._local_queries.append((node, zone))
    return bridge


@pytest.fixture
def playing(session):
    """Human takes both colours, so moves can be played without an AI turn."""
    run(session, session.new_game, 1, 9, 6.5, "japanese", "B", "ai:human", {})
    for color in ("B", "W"):
        session.players_info[color].update(PLAYER_HUMAN, PLAYING_NORMAL)
    return session


def run(session, method, *args):
    session.run_task(method, *args)


def events(session):
    lines = session._stream.getvalue().strip().split("\n")
    return [json.loads(line) for line in lines if line]


def saved(session, reason="autosave", black=None, white=None):
    run(session, session.export_sgf, 99, black, white, reason)
    answer = events(session)[-1]
    assert answer["event"] == "sgf", answer
    return answer


def last_state(session):
    return [e for e in events(session) if e["event"] == "state"][-1]


def moves(text):
    return [node.move.gtp() for node in review.main_line(review.parse(text))[1:]]


# -- what the answer carries -------------------------------------------------


def test_the_answer_says_who_asked(playing):
    assert saved(playing, "autosave")["reason"] == "autosave"
    assert saved(playing, "export")["reason"] == "export"


def test_an_unknown_reason_is_refused(playing):
    run(playing, playing.export_sgf, 5, None, None, "backup")
    assert events(playing)[-1]["code"] == "bad_arguments"


def test_the_final_board_is_the_position_at_the_end_of_the_line(playing):
    run(playing, playing.play, 2, 0, 0)  # A9, top left
    run(playing, playing.play, 3, 8, 8)  # J1, bottom right
    board = saved(playing)["final_board"]
    assert board["size"] == 9
    assert len(board["stones"]) == 81
    assert board["stones"][0] == "b"
    assert board["stones"][80] == "w"
    assert board["stones"].count(".") == 79


def test_the_move_count_is_the_length_of_the_line(playing):
    run(playing, playing.play, 2, 4, 4)
    run(playing, playing.play, 3, 2, 2)
    assert saved(playing)["move_count"] == 2


def test_a_record_read_halfway_still_shows_its_last_position(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    run(session, session.goto, 2, 1)
    answer = saved(session)
    assert answer["move_count"] == 5
    assert answer["final_board"]["stones"].count("b") == 3
    assert answer["final_board"]["stones"].count("w") == 2
    # The board on screen did not move.
    assert session.game.current_node.depth == 1


def test_the_analysis_counts_the_positions_of_the_line(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    assert saved(session)["analysed"] == {"done": 0, "total": 6}


def test_the_answer_carries_what_the_record_says(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    info = saved(session)["game_info"]
    assert info["black_name"] == "Noir"
    assert info["result"] == "B+R"
    assert info["game_name"] == "Finale"


def test_a_game_against_the_ai_is_signed_in_the_answer_too(playing):
    run(playing, playing.play, 2, 4, 4)
    info = saved(playing, black="Thibaut", white="KataGo")["game_info"]
    assert (info["black_name"], info["white_name"], info["result"]) == ("Thibaut", "KataGo", None)


def test_a_game_under_way_is_kept_without_a_result(playing):
    run(playing, playing.play, 2, 4, 4)
    assert "RE[" not in saved(playing)["contents"]


def test_a_game_being_counted_is_kept_without_a_result(playing):
    run(playing, playing.play, 2, 4, 4)
    run(playing, playing.play_pass, 3)
    run(playing, playing.play_pass, 4)
    assert last_state(playing)["status"] == "scoring"
    assert "RE[" not in saved(playing)["contents"]


# -- picking a game up again -------------------------------------------------


def kept_game(playing, *points):
    for index, (row, col) in enumerate(points):
        run(playing, playing.play, 10 + index, row, col)
    return saved(playing)["contents"]


def test_a_kept_game_resumes_at_its_last_move(playing):
    text = kept_game(playing, (4, 4), (2, 2), (6, 6))
    run(playing, playing.continue_game, 20, text, "W", "ai:human", {})
    state = last_state(playing)
    assert state["status"] == "playing"
    assert state["move_number"] == 3
    assert state["human_color"] == "W"
    assert state["to_play"] == "W"
    assert state["id"] == 20


def test_the_player_moves_when_it_is_their_turn(playing):
    text = kept_game(playing, (4, 4), (2, 2), (6, 6))
    run(playing, playing.continue_game, 20, text, "W", "ai:human", {})
    run(playing, playing.play, 21, 0, 0)
    assert last_state(playing)["move_number"] == 4


def test_the_ai_is_owed_a_move_when_it_is_its_turn(playing):
    text = kept_game(playing, (4, 4), (2, 2), (6, 6))
    run(playing, playing.continue_game, 20, text, "B", "ai:human", {})
    assert playing._ai_pending
    assert [e["value"] for e in events(playing) if e["event"] == "thinking"][-1] is True
    run(playing, playing.play, 21, 0, 0)
    assert events(playing)[-1]["code"] == "not_your_turn"


def test_the_ai_keeps_its_mode(playing):
    text = kept_game(playing, (4, 4))
    run(playing, playing.continue_game, 20, text, "W", "ai:territory", {})
    assert last_state(playing)["ai_strategy"] == "ai:territory"


def test_a_game_ending_on_two_passes_is_counted_again(playing):
    run(playing, playing.play, 2, 4, 4)
    run(playing, playing.play_pass, 3)
    run(playing, playing.play_pass, 4)
    text = saved(playing)["contents"]
    run(playing, playing.continue_game, 20, text, "B", "ai:human", {})
    assert last_state(playing)["status"] == "scoring"


def test_a_game_over_is_not_resumed(session):
    run(session, session.continue_game, 20, RECORD, "B", "ai:human", {})
    answer = events(session)[-1]
    assert answer["event"] == "error"
    assert answer["code"] == "finished"


def test_branches_built_in_analysis_come_back(playing):
    run(playing, playing.play, 2, 4, 4)
    run(playing, playing.play, 3, 2, 2)
    run(playing, playing.set_view, 4, "analysis")
    run(playing, playing.goto, 5, 1)
    run(playing, playing.play, 6, 6, 6)  # a stone placed by hand, off the line
    text = saved(playing)["contents"]
    run(playing, playing.continue_game, 20, text, "B", "ai:human", {})
    tree = [e for e in events(playing) if e["event"] == "tree"][-1]["nodes"]
    assert sorted(node["origin"] for node in tree).count("analysis") == 1
    assert last_state(playing)["move_number"] == 2


def test_resuming_starts_afresh_from_a_review(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    run(session, session.new_game, 2, 9, 6.5, "japanese", "B", "ai:human", {})
    for color in ("B", "W"):
        session.players_info[color].update(PLAYER_HUMAN, PLAYING_NORMAL)
    run(session, session.play, 3, 4, 4)
    text = saved(session)["contents"]
    run(session, session.continue_game, 20, text, "B", "ai:human", {})
    state = last_state(session)
    assert state["status"] == "playing"
    assert state.get("view") == "live"
    assert moves(text) == ["E5"]
