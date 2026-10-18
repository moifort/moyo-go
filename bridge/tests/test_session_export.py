"""The session hands its game over as SGF text: played against the AI, or reviewed.

Same fake engine as the other session tests. The AI never moves, so a game here is
whatever the human side plays, which is all the export needs to see.
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
    "(;GM[1]FF[4]SZ[9]KM[6.5]RU[japanese]PB[Noir]PW[Blanc]RE[B+R]"
    ";B[ee]C[opening];W[cc];B[gg];W[cg];B[gc])"
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
    # The local reading goes through KaTrain's query builder, which a fake engine
    # cannot feed; the queries are kept here instead, for the tests to answer.
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


def exported(session, black=None, white=None):
    run(session, session.export_sgf, 99, black, white)
    answer = events(session)[-1]
    assert answer["event"] == "sgf", answer
    assert answer["id"] == 99
    return answer["contents"]


def moves(text):
    return [node.move.gtp() for node in review.main_line(review.parse(text))[1:]]


def test_a_game_goes_out_move_for_move(playing):
    run(playing, playing.play, 2, 4, 4)
    run(playing, playing.play, 3, 2, 2)
    assert moves(exported(playing)) == ["E5", "C7"]


def test_the_game_carries_its_settings_and_who_played(playing):
    run(playing, playing.play, 2, 4, 4)
    root = review.parse(exported(playing, black="Thibaut", white="KataGo · Humain 5k"))
    # Read back as text: pysgf only types the properties KaTrain asks it to.
    assert root.get_property("SZ") == "9"
    assert root.get_property("KM") == "6.5"
    assert root.get_property("PB") == "Thibaut"
    assert root.get_property("PW") == "KataGo · Humain 5k"
    assert root.get_property("AP") == "Moyo"


def test_the_date_is_a_day(playing):
    date = review.game_info(review.parse(exported(playing)))["date"]
    assert len(date) == 10 and date[4] == "-" and date[7] == "-"


def test_moves_taken_back_stay_out(playing):
    run(playing, playing.play, 2, 4, 4)
    run(playing, playing.play, 3, 2, 2)
    run(playing, playing.undo, 4)
    run(playing, playing.play, 5, 6, 6)
    assert moves(exported(playing)) == ["E5", "G3"]


def test_a_resignation_is_the_result(playing):
    run(playing, playing.play, 2, 4, 4)
    run(playing, playing.resign, 3)  # the player, on Black, gives up
    assert review.game_info(review.parse(exported(playing)))["result"] == "W+R"


def test_an_unfinished_game_has_no_result(playing):
    run(playing, playing.play, 2, 4, 4)
    assert review.game_info(review.parse(exported(playing)))["result"] is None


def test_a_record_goes_out_as_it_came_in(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    text = exported(session, black="ignored", white="ignored")
    info = review.game_info(review.parse(text))
    assert info["black_name"] == "Noir"
    assert info["result"] == "B+R"
    assert moves(text) == ["E5", "C7", "G3", "C3", "G7"]
    assert "C[opening]" in text


def test_a_record_keeps_the_variation_being_walked(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    run(session, session.goto, 2, 1)
    session._line[1].analysis = {
        "completed": True,
        "root": {"scoreLead": 0.0, "winrate": 0.5},
        "moves": {"D4": {"move": "D4", "order": 0, "scoreLead": 0.0, "winrate": 0.5,
                         "visits": 100, "pv": ["D4", "F6"]}},
    }
    run(session, session.step_variation, 3, 1)
    root = review.parse(exported(session))
    after_first = root.children[0]
    assert [child.move.gtp() for child in after_first.children] == ["C7", "D4"]
    # The record's own line is still the main one.
    assert moves(exported(session)) == ["E5", "C7", "G3", "C3", "G7"]


def test_nothing_to_export_without_a_game(session):
    run(session, session.export_sgf, 7, None, None)
    answer = events(session)[-1]
    assert answer["event"] == "error"
    assert answer["code"] == "no_game"
