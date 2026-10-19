"""The score estimate, asked for at any moment of a game."""

import io
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

from protocol import CommandError, EventWriter
from pysgf import Move
from session import BridgeSession


class FakeEngine:
    """Absorbs the analysis requests Game fires off; no KataGo involved."""

    def __getattr__(self, name):
        return lambda *args, **kwargs: None


@pytest.fixture
def session():
    stream = io.StringIO()
    bridge = BridgeSession(EventWriter(stream))
    bridge._engine = FakeEngine()
    bridge.new_game(1, 9, 6.5, "japanese", "B", "ai:human", {})
    bridge._stream = stream
    return bridge


def states(session):
    lines = session._stream.getvalue().strip().split("\n")
    return [e for e in (json.loads(line) for line in lines if line) if e["event"] == "state"]


def own_left_half(node, size=9):
    """KataGo's verdict, by hand: the four left columns Black's, the four right White's."""
    node.analysis["ownership"] = [
        0.95 if col < 4 else (-0.95 if col > 4 else 0.0) for row in range(size) for col in range(size)
    ]


def test_off_by_default(session):
    assert states(session)[-1]["estimating"] is False
    assert "estimate" not in states(session)[-1]


def test_waits_for_the_ownership_map(session):
    session.set_estimate(2, True)
    state = states(session)[-1]
    assert state["estimating"] is True
    assert "estimate" not in state


def test_arrives_with_the_ownership_map(session):
    session.set_estimate(2, True)
    own_left_half(session.game.current_node)
    session._on_state_advanced()
    estimate = states(session)[-1]["estimate"]
    assert estimate["count"]["territory"] == {"B": 36, "W": 36}
    assert estimate["count"]["result"] == "W+6.5"
    assert estimate["lead"] == -6.5


def test_a_later_analysis_that_changes_nothing_sends_nothing(session):
    session.set_estimate(2, True)
    own_left_half(session.game.current_node)
    session._on_state_advanced()
    count = len(states(session))
    session._on_state_advanced()
    assert len(states(session)) == count


def test_follows_the_moves_played(session):
    session.set_estimate(2, True)
    own_left_half(session.game.current_node)
    session.game.play(Move(coords=(0, 0), player="B"))
    own_left_half(session.game.current_node)
    session._on_state_advanced()
    estimate = states(session)[-1]["estimate"]
    # The stone stands on a point of Black's: no longer territory, still Black's.
    assert estimate["count"]["territory"] == {"B": 35, "W": 36}


def test_an_open_position_shows_katagos_lead(session):
    session.set_estimate(2, True)
    node = session.game.current_node
    node.analysis["ownership"] = [0.3] * 81
    node.analysis["root"] = {"scoreLead": 1.8}
    session._on_state_advanced()
    estimate = states(session)[-1]["estimate"]
    assert estimate["count"] is None
    assert estimate["lead"] == 2.0
    assert estimate["points"] == []


def test_switched_off(session):
    session.set_estimate(2, True)
    own_left_half(session.game.current_node)
    session.set_estimate(3, False)
    state = states(session)[-1]
    assert state["estimating"] is False
    assert "estimate" not in state


def test_gives_way_to_the_real_count(session):
    session.set_estimate(2, True)
    own_left_half(session.game.current_node)
    for player in ("B", "W"):
        session.game.play(Move(coords=None, player=player))
    session._enter_scoring()
    session._emit_state(4)
    state = states(session)[-1]
    assert "scoring" in state
    assert "estimate" not in state


def test_refused_without_a_game():
    bridge = BridgeSession(EventWriter(io.StringIO()))
    with pytest.raises(CommandError):
        bridge.set_estimate(1, True)
