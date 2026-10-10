import io
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

from katrain.core.game_node import GameNode
from pysgf import Move

import session as session_module
from protocol import EventWriter
from session import BridgeSession


class FakeEngine:
    """Absorbs the analysis requests Game fires off; no KataGo involved."""

    def __getattr__(self, name):
        return lambda *args, **kwargs: None


@pytest.fixture
def ai_moves(monkeypatch):
    """Every position counts as analysed, and the AI answers on the first free point."""
    monkeypatch.setattr(GameNode, "analysis_complete", property(lambda node: True))
    played = []

    def fake_ai_move(game, strategy, settings):
        node = game.current_node
        taken = {stone.coords for stone in game.stones}
        coords = next((x, y) for y in range(9) for x in range(9) if (x, y) not in taken)
        played.append(coords)
        game.play(Move(coords=coords, player=node.next_player))

    monkeypatch.setattr(session_module, "generate_ai_move", fake_ai_move)
    return played


@pytest.fixture
def session(ai_moves):
    bridge = BridgeSession(EventWriter(io.StringIO()))
    bridge._engine = FakeEngine()
    bridge.new_game(1, 9, 6.5, "japanese", "B", "ai:human", {})
    return bridge


def test_the_ai_answers_a_move(session, ai_moves):
    session.play(2, 4, 4)
    assert len(ai_moves) == 1
    assert session.game.current_node.next_player == "B"


def test_the_ai_answers_a_move_replayed_after_an_undo(session, ai_moves):
    # KaTrain keeps the undone moves in its tree, and playing the same point again
    # walks back into them: the node reached already has the AI's old answer below.
    session.play(2, 4, 4)
    session.undo(3)
    session.play(4, 4, 4)
    assert len(ai_moves) == 2
    assert session.game.current_node.next_player == "B"


def test_the_ai_plays_on_when_the_count_is_called_off_after_its_own_pass(session, ai_moves):
    # The player passes and the AI passes back: the game is counted.
    session.game.play(Move(coords=None, player="B"))
    session.game.play(Move(coords=None, player="W"))
    session._enter_scoring()
    # Resuming takes back the AI's pass, which stays in the tree below.
    session.resume_game(3)
    assert len(ai_moves) == 1
    assert session.game.current_node.next_player == "B"
