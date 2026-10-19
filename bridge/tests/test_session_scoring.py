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
    # A game over is read in analysis, which asks for local readings a fake engine
    # cannot build.
    bridge._send_local_query = lambda node, zone: None
    bridge.new_game(1, 9, 6.5, "japanese", "B", "ai:human", {})
    bridge._stream = stream
    return bridge


def events(session):
    return [json.loads(line) for line in session._stream.getvalue().strip().split("\n") if line]


def last_state(session):
    return [e for e in events(session) if e["event"] == "state"][-1]


def both_pass(session):
    """Passes for both sides directly on the game, bypassing turn ownership."""
    for player in ("B", "W"):
        session.game.play(Move(coords=None, player=player))


class TestEnteringScoring:
    def test_a_fresh_game_is_being_played(self, session):
        assert session._status == "playing"
        assert last_state(session)["status"] == "playing"
        assert "scoring" not in last_state(session)

    def test_one_pass_is_not_the_end(self, session):
        session.game.play(Move(coords=None, player="B"))
        assert not session._two_passes_played()

    def test_two_passes_end_the_game(self, session):
        both_pass(session)
        assert session._two_passes_played()

    def test_entering_scoring_publishes_a_count(self, session):
        both_pass(session)
        session._enter_scoring()
        session._emit_state(9)
        state = last_state(session)
        assert state["status"] == "scoring"
        assert state["scoring"]["result"] is not None
        assert state["scoring"]["dead_stones"] == []

    def test_the_komi_reaches_the_count(self, session):
        both_pass(session)
        session._enter_scoring()
        assert session._count()["komi"] == 6.5
        # An empty board is nobody's territory, so komi alone decides it.
        assert session._count()["result"] == "W+6.5"


class TestMarkingDeadStones:
    def _position(self, session):
        """A white stone stranded in Black's corner, alive on the board but doomed.

            W . B . . .
            . . B . . .
            B B B . . .

        The white stone keeps two liberties, so it is not captured — it is exactly
        the kind of group the players have to agree is dead.
        """
        size = 9
        wall = [(0, 2), (1, 2), (2, 2), (2, 1), (2, 0)]
        for row, col in wall:
            session.game.play(Move(coords=(col, size - 1 - row), player="B"))
        session.game.play(Move(coords=(0, size - 1), player="W"))
        assert (0, 0) in __import__("serialize").stone_map(session.game)
        session._enter_scoring()
        session._stream.truncate(0)
        session._stream.seek(0)

    def test_marking_a_group_dead_changes_the_count(self, session):
        self._position(session)
        before = session._count()
        # Alive, the white stone makes its corner neutral.
        assert before["territory"]["B"] < session._count()["territory"]["B"] + 1
        session.toggle_dead(2, 0, 0)
        after = session._count()
        # Dead, it hands over the three points it was denying, plus itself.
        assert after["territory"]["B"] == before["territory"]["B"] + 4
        assert after["black"] == before["black"] + 5
        assert last_state(session)["scoring"]["dead_stones"] == [{"row": 0, "col": 0}]

    def test_marking_it_again_brings_it_back_to_life(self, session):
        self._position(session)
        session.toggle_dead(2, 0, 0)
        session.toggle_dead(3, 0, 0)
        assert session._dead == set()
        assert last_state(session)["scoring"]["dead_stones"] == []

    def test_clicking_an_empty_point_is_refused(self, session):
        self._position(session)
        with pytest.raises(CommandError) as exc:
            session.toggle_dead(2, 5, 5)
        assert exc.value.code == "no_group"

    def test_marking_is_refused_while_the_game_is_on(self, session):
        with pytest.raises(CommandError) as exc:
            session.toggle_dead(2, 0, 0)
        assert exc.value.code == "not_scoring"


class TestLeavingScoring:
    def test_accepting_the_score_ends_the_game(self, session):
        both_pass(session)
        session._enter_scoring()
        session.accept_score(5)
        state = last_state(session)
        assert state["status"] == "finished"
        assert state["result"] == "W+6.5"

    def test_resuming_takes_back_the_last_pass(self, session):
        both_pass(session)
        session._enter_scoring()
        moves_before = session.game.current_node.depth
        session.resume_game(6)
        assert session._status == "playing"
        assert session.game.current_node.depth == moves_before - 1
        assert session._dead == set()

    def test_playing_is_refused_while_counting(self, session):
        both_pass(session)
        session._enter_scoring()
        with pytest.raises(CommandError) as exc:
            session.play(7, 4, 4)
        assert exc.value.code == "not_playing"

    def test_a_new_game_leaves_scoring_behind(self, session):
        both_pass(session)
        session._enter_scoring()
        session._dead = {(0, 0)}
        session.new_game(8, 9, 6.5, "japanese", "B", "ai:human", {})
        assert session._status == "playing"
        assert session._dead == set()


class TestAIStrategies:
    def test_the_catalogue_comes_from_katrain_not_from_us(self, session):
        catalogue = session.available_strategies()
        # KaTrain's own recommended order, filtered to what this install configures.
        assert "ai:human" in catalogue["strategies"]
        assert "ai:default" in catalogue["strategies"]
        assert catalogue["strategies"][0] == "ai:default"
        assert all(catalogue["ai_settings"][s] is not None for s in catalogue["strategies"])

    def test_the_current_mode_travels_with_the_state(self, session):
        state = last_state(session)
        assert state["ai_strategy"] == "ai:human"
        assert state["ai_settings"]["human_kyu_rank"] == 8

    def test_switching_mode_takes_effect_at_once(self, session):
        session.set_ai(4, "ai:pro", {"pro_year": 1950})
        state = last_state(session)
        assert state["ai_strategy"] == "ai:pro"
        assert state["ai_settings"]["pro_year"] == 1950
        assert session.players_info["W"].strategy == "ai:pro"

    def test_the_human_side_is_never_turned_into_an_ai(self, session):
        session.set_ai(4, "ai:default", {})
        assert session.players_info["B"].human
        assert session.players_info["W"].ai

    def test_an_unknown_mode_is_refused(self, session):
        with pytest.raises(CommandError) as exc:
            session.set_ai(4, "ai:nonsense", {})
        assert exc.value.code == "unknown_ai"

    def test_settings_given_are_remembered(self, session):
        session.set_ai(4, "ai:human", {"human_kyu_rank": -3})
        assert session.config("ai/ai:human")["human_kyu_rank"] == -3
        # Restore, since the config file is shared with KaTrain itself.
        session.set_ai(5, "ai:human", {"human_kyu_rank": 8})

    def test_playing_as_white_puts_the_ai_on_black(self, session):
        session.new_game(9, 9, 6.5, "japanese", "W", "ai:human", {})
        assert session._ai_color == "B"
        assert session.players_info["B"].ai
        assert session.players_info["W"].human


class TestResigning:
    """A resignation ends the game, and its result names the winner: always the AI."""

    def test_resigning_on_your_own_turn_hands_the_game_over(self, session):
        session.resign(2)
        assert session.game.end_result == "W+R"

    def test_resigning_while_the_ai_thinks_still_hands_it_over(self, session):
        session.new_game(9, 9, 6.5, "japanese", "W", "ai:human", {})
        # Black, the AI, is to move: the player gives up before it has answered.
        session.resign(10)
        assert session.game.end_result == "B+R"

    def test_resigning_ends_the_game_on_screen(self, session):
        session.resign(2)
        state = last_state(session)
        assert state["status"] == "finished"
        assert state["result"] == "W+R"

    def test_a_resigned_game_is_not_counted(self, session):
        session.resign(2)
        assert "scoring" not in last_state(session)

    @pytest.mark.parametrize("action, code", [("resign", "not_playing"), ("undo", "nothing_to_undo")])
    def test_nothing_more_is_played_after_resigning(self, session, action, code):
        session.resign(2)
        attempt = {
            "resign": lambda: session.resign(3),
            "undo": lambda: session.undo(3),
        }[action]
        with pytest.raises(CommandError) as exc:
            attempt()
        assert exc.value.code == code
        assert session.game.end_result == "W+R"

    def test_a_resigned_game_opens_in_analysis(self, session):
        session.resign(2)
        assert last_state(session)["view"] == "analysis"

    @pytest.mark.parametrize("action", ["play", "pass"])
    def test_a_stone_after_resigning_is_a_branch_not_a_move(self, session, action):
        session.resign(2)
        end = session.game.current_node
        {"play": lambda: session.play(3, 4, 4), "pass": lambda: session.play_pass(3)}[action]()
        assert session.game.current_node.parent is end
        assert last_state(session)["status"] == "finished"
        assert last_state(session)["result"] == "W+R"

    def test_a_new_game_starts_afresh(self, session):
        session.resign(2)
        session.new_game(3, 9, 6.5, "japanese", "B", "ai:human", {})
        state = last_state(session)
        assert state["status"] == "playing"
        assert state["result"] is None
