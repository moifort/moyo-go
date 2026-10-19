"""A record analysed to the end goes back to the app, analysis included.

The app writes it over the file it opened, so the next opening reads KataGo's work
instead of asking for it again. Same fake engine as the other session tests: the
analyses are filled in by hand, and KaTrain's background pass over the tree is
switched off so it cannot clear them under the test.
"""

import io
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

from katrain.core.game import Game

import record
import review
from protocol import EventWriter
from session import BridgeSession

RECORD = "(;GM[1]FF[4]SZ[9]KM[6.5]RU[japanese]PB[Noir];B[ee];W[cc];B[gg])"


class FakeEngine:
    def __getattr__(self, name):
        return lambda *args, **kwargs: None


@pytest.fixture
def session(monkeypatch):
    monkeypatch.setattr(Game, "analyze_all_nodes", lambda *args, **kwargs: None)
    stream = io.StringIO()
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge._stream = stream
    bridge._send_local_query = lambda node, zone: None
    return bridge


def run(session, method, *args):
    session.run_task(method, *args)


def events(session, name):
    lines = session._stream.getvalue().strip().split("\n")
    return [e for e in (json.loads(line) for line in lines if line) if e["event"] == name]


def analysed(node, score_lead=0.0, pv=("C3", "D4")):
    node.analysis = {
        "completed": True,
        "root": {"scoreLead": score_lead, "winrate": 0.5, "visits": 500},
        "moves": {pv[0]: {"move": pv[0], "order": 0, "scoreLead": score_lead, "winrate": 0.5,
                          "visits": 400, "pv": list(pv)}},
        "ownership": [0.0] * 81,
        "policy": [0.0] * 82,
    }


def advance(session):
    """An analysis came back: what `update_state` queues on the worker."""
    run(session, session._on_state_advanced)


def test_the_record_goes_back_once_every_position_is_analysed(session):
    run(session, session.load_sgf, 4, "partie.sgf", RECORD)
    for depth, node in enumerate(session._line):
        analysed(node, score_lead=float(depth))
    advance(session)

    [saved] = events(session, "record_analysed")
    # Tagged with the opening command: an answer for a record since replaced is
    # recognisable as such on the app's side.
    assert saved["id"] == 4
    reread = review.main_line(review.parse(saved["contents"]))
    assert [node.load_analysis() for node in reread] == [True] * 4
    assert reread[2].analysis["root"]["scoreLead"] == 2.0
    assert review.game_info(review.parse(saved["contents"]))["black_name"] == "Noir"


def test_nothing_goes_back_while_a_position_is_missing(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    for node in session._line[:-1]:
        analysed(node)
    advance(session)
    assert events(session, "record_analysed") == []


def test_the_record_goes_back_only_once(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    for node in session._line:
        analysed(node)
    advance(session)
    advance(session)
    assert len(events(session, "record_analysed")) == 1


def test_a_record_that_came_analysed_is_left_alone(session):
    root = review.parse(RECORD)
    for node in review.main_line(root):
        analysed(node)
    run(session, session.load_sgf, 1, "partie.sgf", record.text(root))
    # What KaTrain's background pass does with an analysis found in the file.
    for node in session._line:
        assert node.load_analysis()
    advance(session)
    assert events(session, "record_analysed") == []


def test_the_variation_being_walked_stays_out(session):
    run(session, session.load_sgf, 1, "partie.sgf", RECORD)
    run(session, session.goto, 2, 1)
    analysed(session._line[1], pv=("D4", "F6"))
    run(session, session.step_variation, 3, 1)
    for node in session._line:
        analysed(node, pv=("D4", "F6"))
    advance(session)

    [saved] = events(session, "record_analysed")
    after_first = review.parse(saved["contents"]).children[0]
    assert [child.move.gtp() for child in after_first.children] == ["C7"]


def test_a_game_against_the_ai_is_not_sent_back(session):
    run(session, session.new_game, 1, 9, 6.5, "japanese", "B", "ai:human", {})
    for node in session.game.root.nodes_in_tree:
        analysed(node)
    advance(session)
    assert events(session, "record_analysed") == []
