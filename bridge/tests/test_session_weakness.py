"""The weak points of the groups, asked for in analysis while the player wants them."""

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

#: Black to move after the record: four white stones in a row on the fifth line.
RECORD = "(;GM[1]FF[4]SZ[9]KM[6.5]RU[japanese];B[aa];W[de];B[ab];W[ee];B[ac];W[fe];B[ia];W[ge])"


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
    bridge._weakness_queries = []
    bridge._send_weakness_query = lambda node, player, near: bridge._weakness_queries.append((node, player))
    return bridge


@pytest.fixture
def reviewing(session):
    session.run_task(session.load_sgf, 1, "partie.sgf", RECORD)
    return session


def events(session):
    lines = session._stream.getvalue().strip().split("\n")
    return [json.loads(line) for line in lines if line]


def last_state(session):
    return [e for e in events(session) if e["event"] == "state"][-1]


def ownership(white):
    """Black-positive map: the white chain on row 4 owned as told, the rest neutral."""
    grid = [0.0] * 81
    for col in range(3, 7):
        grid[4 * 9 + col] = white
    return grid


def answer(white_at_e4):
    """KataGo's answer: the white chain unsettled, and E4 with the map after it."""
    return {"ownership": ownership(-0.5), "moveInfos": [{"move": "E4", "visits": 50, "ownership": ownership(white_at_e4)}]}


#: Black at E4 leaves the white chain at -0.1 a stone; White there, at -0.8.
BLACK, WHITE = answer(-0.1), answer(-0.8)


def test_off_by_default_and_asks_nothing(reviewing):
    state = last_state(reviewing)
    assert state["weaknessing"] is False
    assert state["weaknesses"] is None
    assert reviewing._weakness_queries == []


def test_turned_on_asks_both_colours_once(reviewing):
    reviewing.run_task(reviewing.set_weaknesses, 2, True)
    node = reviewing.game.current_node
    assert sorted(player for _, player in reviewing._weakness_queries) == ["B", "W"]
    assert all(asked is node for asked, _ in reviewing._weakness_queries)
    state = last_state(reviewing)
    assert state["weaknessing"] is True
    assert state["weaknesses"] is None
    assert state["weaknesses_pending"] is True
    reviewing.run_task(reviewing.state, 3)
    assert len(reviewing._weakness_queries) == 2


def test_shown_only_once_both_colours_are_back(reviewing):
    reviewing.run_task(reviewing.set_weaknesses, 2, True)
    node = reviewing.game.current_node
    reviewing._on_weakness_analysis(node, "B", BLACK)
    assert last_state(reviewing)["weaknesses"] is None
    reviewing._on_weakness_analysis(node, "W", WHITE)
    state = last_state(reviewing)
    assert state["weaknesses_pending"] is False
    assert state["weaknesses"] == [{"row": 5, "col": 4, "color": "B", "swing": 2.8}]


def test_an_empty_board_asks_nothing(session):
    session.run_task(session.load_sgf, 1, "vide.sgf", "(;GM[1]FF[4]SZ[9]KM[6.5])")
    session.run_task(session.set_weaknesses, 2, True)
    assert session._weakness_queries == []
    assert last_state(session)["weaknesses"] == []


def test_a_failed_query_counts_as_nothing_found(reviewing):
    reviewing.run_task(reviewing.set_weaknesses, 2, True)
    node = reviewing.game.current_node
    reviewing._on_weakness_failure(node, "W", {"error": "boom"})
    reviewing._on_weakness_analysis(node, "B", BLACK)
    state = last_state(reviewing)
    assert state["weaknesses"] == []
    assert state["weaknesses_pending"] is False


def test_each_position_is_asked_for_itself(reviewing):
    reviewing.run_task(reviewing.set_weaknesses, 2, True)
    last = reviewing.game.current_node
    reviewing.run_task(reviewing.goto, 3, 4)
    assert len(reviewing._weakness_queries) == 4
    # A late answer for the position left behind does not show on this one.
    reviewing._on_weakness_analysis(last, "B", BLACK)
    reviewing._on_weakness_analysis(last, "W", WHITE)
    assert last_state(reviewing)["weaknesses"] is None
    # Back on it, the answer is there, without asking again.
    reviewing.run_task(reviewing.goto, 4, 8)
    assert len(reviewing._weakness_queries) == 4
    assert last_state(reviewing)["weaknesses"] == [{"row": 5, "col": 4, "color": "B", "swing": 2.8}]


def test_turned_off_hides_them(reviewing):
    reviewing.run_task(reviewing.set_weaknesses, 2, True)
    reviewing.run_task(reviewing.set_weaknesses, 3, False)
    state = last_state(reviewing)
    assert state["weaknessing"] is False
    assert state["weaknesses"] is None


def test_refused_outside_analysis(session):
    session.run_task(session.new_game, 1, 9, 6.5, "japanese", "B", "ai:human", {})
    session.run_task(session.set_weaknesses, 2, True)
    error = [e for e in events(session) if e["event"] == "error"][-1]
    assert error["code"] == "not_reviewing"


def test_a_new_record_forgets_the_old_answers(reviewing):
    reviewing.run_task(reviewing.set_weaknesses, 2, True)
    old = reviewing.game.current_node
    reviewing.run_task(reviewing.load_sgf, 3, "autre.sgf", RECORD)
    reviewing._on_weakness_analysis(old, "B", BLACK)
    assert reviewing._weakness.get(id(reviewing.game.current_node), {}).get("B") is None
