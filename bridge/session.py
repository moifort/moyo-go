"""The game the bridge is holding: a game against the AI, or a record under review.

Two modes share one object because the KaTrain core insists on a single host
carrying `.game` and `.players_info`. What they do not share is behaviour: playing
answers to the engine and the clock, reviewing answers to the arrow keys. The mode
is carried by `_status`, which the app reads as well.

Everything process-shaped — the worker thread, the engine's lifetime, the inert
controls — lives in `host.py`. Everything that is pure reading of a record lives in
`review.py`. What remains here is the state and who is allowed to change it.
"""

from typing import Any, Dict, List, Optional

from katrain.core.ai import generate_ai_move
from katrain.core.constants import (
    AI_STRATEGIES_RECOMMENDED_ORDER,
    PLAYER_AI,
    PLAYER_HUMAN,
    PLAYING_NORMAL,
    PRIORITY_DEFAULT,
)
from katrain.core.game import Game, IllegalMoveException
from pysgf import Move

import review
import scoring
import serialize
from host import KaTrainHost
from protocol import CommandError, to_display_coords, to_engine_coords


class BridgeSession(KaTrainHost):
    """Owns the game state and mediates every call into the KaTrain core."""

    #: How many nodes before the current one jump the analysis queue.
    #:
    #: A record opens at its last move and is read backwards, so the positions about
    #: to be asked for are the ones just behind. Everything else keeps the background
    #: priority `Game` already gave it.
    PRIORITY_WINDOW = 5

    def __init__(self, writer):
        self._human_color = "B"
        self._emitted_scores: Dict[int, float] = {}
        self._ai_pending = False
        self._status = "playing"  # playing | scoring | finished | review
        self._dead: set = set()
        # -- review state, all empty outside a review
        #: The main line of the record, cached once. A variation adds nodes to the
        #: tree, so recomputing it would make the record's own length move.
        self._line: List[Any] = []
        self._index = 0
        #: One entry per variation move: (parent, node, we created it).
        #: `Game.play` reuses a matching child, so KataGo's move landing on the move
        #: actually played walks into the record itself — which must never be pruned.
        self._variation: List[tuple] = []
        self._anchor_pv: List[str] = []
        self._game_info: Dict[str, Any] = {}
        #: Nodes already pushed to the front of the queue, by id. `request_analysis`
        #: has no guard against duplicates, and the tree holds every node for the
        #: session's lifetime, so the ids cannot be reused under us.
        self._boosted: set = set()
        self._emitted_best: Optional[tuple] = None
        self._emitted_progress: Optional[int] = None
        super().__init__(writer)

    # -- state notification --------------------------------------------------

    def update_state(self, redraw_board=False):
        """Called by the core whenever an analysis advances. Never does work here."""
        if not self._stopping:
            self.submit(self._on_state_advanced)

    def _on_state_advanced(self) -> None:
        if self.game is None:
            return
        self._emit_new_scores()
        if self._status == "review":
            self._on_review_advanced()
            return
        if self._status == "scoring" and not self._dead:
            # The ownership map often lands after the second pass; take it when it
            # arrives rather than leaving the player with nothing proposed.
            suggested = self._suggested_dead()
            if suggested:
                self._dead = set(suggested)
                self._emit_state()
            return
        self._maybe_play_ai_move()

    def _on_review_advanced(self) -> None:
        """An analysis came back while reviewing: move the gauge, and the marker."""
        self._emit_progress()
        best = self._best_move()
        key = None if best is None else (best["row"], best["col"])
        if key != self._emitted_best:
            self._emitted_best = key
            self._emit_state()

    #: Score changes smaller than this are not worth an event. KataGo keeps refining
    #: an analysis while it ponders, and without a threshold every node would emit a
    #: stream of events differing in the third decimal.
    SCORE_EPSILON = 0.05

    def _score_nodes(self) -> List[Any]:
        """The nodes whose score belongs on the chart.

        While playing, the line up to the current move — there is nothing beyond it.
        While reviewing, the whole record, so stepping back does not blank out the
        part of the chart that lies ahead. Variation nodes are in neither list.
        """
        return self._line if self._status == "review" else self.game.current_node.nodes_from_root

    def _emit_new_scores(self) -> None:
        for node in self._score_nodes():
            if not node.analysis_complete:
                continue
            score = node.score
            if score is None:
                continue
            previous = self._emitted_scores.get(node.depth)
            if previous is not None and abs(previous - score) < self.SCORE_EPSILON:
                continue
            self._emitted_scores[node.depth] = score
            self._writer.emit("score", None, move_number=node.depth, score_lead=round(score, 2))

    def _emit_progress(self) -> None:
        done = sum(1 for node in self._line if node.analysis_complete)
        if done == self._emitted_progress:
            return
        self._emitted_progress = done
        self._writer.emit("analysis_progress", None, done=done, total=len(self._line))

    def _maybe_play_ai_move(self) -> None:
        """Reproduces the core's own trigger condition for an AI move.

        Mirrors katrain/__main__.py: the AI only moves once the current node's
        analysis is complete, it is the AI's turn, nothing has been played on top,
        and the game has not ended.
        """
        node = self.game.current_node
        if not self._ai_pending:
            return
        if not (node.analysis_complete and not node.children and not self.game.end_result):
            return
        if not self.players_info[node.next_player].ai:
            return
        self._ai_pending = False
        strategy = self.players_info[node.next_player].strategy
        settings = self.config(f"ai/{strategy}")
        if settings is None:
            self._writer.emit("error", None, code="unknown_ai", message=f"AI strategy {strategy} not found")
            self._emit_state()
            return
        generate_ai_move(self.game, strategy, settings)
        self._writer.emit("thinking", None, value=False)
        if self._two_passes_played():
            self._enter_scoring()
        self._emit_state()

    # -- commands ------------------------------------------------------------

    def _emit_state(self, command_id: Optional[int] = None) -> None:
        if self._status == "review":
            self._emit_review_state(command_id)
            return
        result = self.game.current_node.end_state if self._status == "finished" else None
        counted = self._count() if self._status in ("scoring", "finished") else None
        if counted is not None and result is None and self._status == "finished":
            result = counted["result"]
        self._writer.emit(
            "state",
            command_id,
            **serialize.game_state(
                self.game,
                self._human_color,
                status=self._status,
                result=result,
                scoring=counted,
                dead=sorted(self._dead),
                ai_strategy=self._ai_strategy,
                ai_settings=self.config(f"ai/{self._ai_strategy}"),
            ),
        )

    # -- end of game ---------------------------------------------------------

    def _count(self) -> Dict[str, Any]:
        """Counts the position as it currently stands, dead stones included."""
        board = serialize.stone_map(self.game)
        captures = serialize.captures(self.game)
        return scoring.score(
            size=serialize.board_size(self.game),
            stones=board,
            dead=self._dead,
            komi=self.game.root.komi,
            captures=captures,
            rules=str(self.game.root.ruleset or "japanese"),
        )

    def _two_passes_played(self) -> bool:
        node = self.game.current_node
        return bool(node.is_pass and node.parent is not None and node.parent.is_pass)

    def _enter_scoring(self) -> None:
        """Two passes: stop playing and propose which stones look dead."""
        self._status = "scoring"
        self._ai_pending = False
        self._dead = set(self._suggested_dead())
        self._writer.emit("thinking", None, value=False)

    def _suggested_dead(self):
        node = self.game.current_node
        return scoring.suggest_dead(
            size=serialize.board_size(self.game),
            stones=serialize.stone_map(self.game),
            ownership=node.ownership,
        )

    def toggle_dead(self, command_id, row, col):
        """Flips the whole group under a point between dead and alive."""
        if self._status != "scoring":
            raise CommandError("not_scoring", "the game is not being counted")
        board = serialize.stone_map(self.game)
        size = serialize.board_size(self.game)
        group = scoring.group_at(board, size, (row, col))
        if not group:
            raise CommandError("no_group", "there is no stone there")
        if group & self._dead:
            self._dead -= group
        else:
            self._dead |= group
        self._emit_state(command_id)

    def accept_score(self, command_id):
        if self._status != "scoring":
            raise CommandError("not_scoring", "the game is not being counted")
        self._status = "finished"
        self.game.current_node.end_state = self._count()["result"]
        self._emit_state(command_id)

    def resume_game(self, command_id):
        """Takes back the last pass so play can continue."""
        if self._status != "scoring":
            raise CommandError("not_scoring", "the game is not being counted")
        self._status = "playing"
        self._dead = set()
        self.game.undo(1)
        if self.players_info[self.game.current_node.next_player].ai:
            self._ai_pending = True
            self._writer.emit("thinking", None, value=True)
            self._maybe_play_ai_move()
        else:
            self._emit_state(command_id)

    def _size(self) -> int:
        return serialize.board_size(self.game)

    def new_game(self, command_id, size, komi, rules, human_color, ai_strategy, ai_settings):
        if self._engine is None:
            raise CommandError("no_engine", "engine not started")
        self._human_color = human_color
        self.players_info[human_color].update(PLAYER_HUMAN, PLAYING_NORMAL)
        self.players_info[self._ai_color].update(PLAYER_AI, ai_strategy)
        if ai_settings:
            self.config(f"ai/{ai_strategy}").update(ai_settings)
        self._clear_review()
        self._emitted_scores.clear()
        self._dead = set()
        self._status = "playing"
        self.game = Game(self, self._engine, game_properties={"SZ": size, "KM": komi, "RU": rules})
        self._ai_pending = self.players_info[self.game.current_node.next_player].ai
        if self._ai_pending:
            self._writer.emit("thinking", None, value=True)
        self._emit_state(command_id)

    def play(self, command_id, row, col):
        self._require_game()
        if self._status != "playing":
            raise CommandError("not_playing", "the game is over")
        node = self.game.current_node
        if self.players_info[node.next_player].ai:
            raise CommandError("not_your_turn", "it is the AI's turn")
        move = Move(coords=to_engine_coords(row, col, self._size()), player=node.next_player)
        try:
            self.game.play(move)
        except IllegalMoveException as exc:
            raise CommandError("illegal_move", str(exc)) from exc
        self._after_human_move(command_id)

    def play_pass(self, command_id):
        self._require_game()
        if self._status != "playing":
            raise CommandError("not_playing", "the game is over")
        node = self.game.current_node
        if self.players_info[node.next_player].ai:
            raise CommandError("not_your_turn", "it is the AI's turn")
        self.game.play(Move(coords=None, player=node.next_player))
        self._after_human_move(command_id)

    def _after_human_move(self, command_id) -> None:
        if self._two_passes_played():
            self._enter_scoring()
            self._emit_state(command_id)
            return
        self._emit_state(command_id)
        if self.game.end_result:
            return
        self._ai_pending = self.players_info[self.game.current_node.next_player].ai
        if self._ai_pending:
            self._writer.emit("thinking", None, value=True)
            self._maybe_play_ai_move()

    def undo(self, command_id):
        """Steps back until it is the human's turn again, two moves in the usual case."""
        self._require_game()
        self._refuse_in_review()
        self._status = "playing"
        self._dead = set()
        self._ai_pending = False
        steps = 0
        while steps < 2 and self.game.current_node.parent is not None:
            self.game.undo(1)
            steps += 1
            if self.players_info[self.game.current_node.next_player].human:
                break
        self._emitted_scores.clear()
        self._writer.emit("thinking", None, value=False)
        self._emit_state(command_id)

    def resign(self, command_id):
        self._require_game()
        self._refuse_in_review()
        self._ai_pending = False
        # Only the player can resign, and may do so while the AI is thinking: the
        # winner is the AI, whoever happens to be to move. The result names the winner.
        self.game.current_node.end_state = f"{self._ai_color}+R"
        self._writer.emit("thinking", None, value=False)
        self._emit_state(command_id)

    def state(self, command_id):
        self._require_game()
        self._emit_state(command_id)

    # -- review --------------------------------------------------------------

    def _clear_review(self) -> None:
        self._line = []
        self._index = 0
        self._variation = []
        self._anchor_pv = []
        self._game_info = {}
        self._boosted = set()
        self._emitted_best = None
        self._emitted_progress = None

    def load_sgf(self, command_id, name, contents):
        """Reads a record and opens it at its last move.

        The text arrives from the app, already decoded. The bridge never opens a
        file: the sandbox grants access to the window, not to the child process,
        and `shims/chardet` is deliberately too modest to guess an encoding.
        """
        if self._engine is None:
            raise CommandError("no_engine", "engine not started")
        root = review.parse(contents)
        self._clear_review()
        self._emitted_scores.clear()
        self._dead = set()
        self._ai_pending = False
        self._status = "review"
        # Nobody is to move: a record is read, not played on.
        for color in ("B", "W"):
            self.players_info[color].update(PLAYER_HUMAN, PLAYING_NORMAL)
        # Game re-reads the tree — handicap stones may be placed — so the main line
        # is taken from the game's own root rather than from the parsed one.
        self.game = Game(self, self._engine, move_tree=root, sgf_filename=name)
        self._line = review.main_line(self.game.root)
        self._game_info = review.game_info(self.game.root)
        self._index = len(self._line) - 1
        self.game.set_current_node(self._line[self._index])
        self._boost_window()
        self._emit_state(command_id)

    def goto(self, command_id, move_number):
        """Jumps to a position in the main line. Out-of-range asks are clamped."""
        self._require_review()
        self._prune_variation()
        self._index = max(0, min(int(move_number), len(self._line) - 1))
        self.game.set_current_node(self._line[self._index])
        self._emitted_best = None
        self._boost_window()
        self._emit_state(command_id)

    def step_variation(self, command_id, step):
        """Walks KataGo's own continuation, one move per call, colours alternating."""
        self._require_review()
        if int(step) > 0:
            self._push_variation(command_id)
        else:
            self._pop_variation(command_id)

    def _refresh_anchor_pv(self) -> None:
        """Takes a longer continuation from the anchor once the analysis has deepened.

        The first press often lands on a reading built from the policy alone, whose
        continuation is a single move. Freezing that would stop the walk at the
        shallowest view KataGo ever had of the position. A fresher line is adopted
        only when it still begins with the moves already on the board, so the branch
        under the player's eyes is extended and never rewritten.
        """
        fresh = review.variation(self._line[self._index])
        walked = len(self._variation)
        if len(fresh) <= len(self._anchor_pv):
            return
        if fresh[:walked] != self._anchor_pv[:walked]:
            return
        self._anchor_pv = fresh

    def _push_variation(self, command_id) -> None:
        anchor = self._line[self._index]
        if not self._variation:
            self._anchor_pv = review.variation(anchor)
        else:
            self._refresh_anchor_pv()
        depth = len(self._variation)
        if depth >= len(self._anchor_pv):
            # Worth telling apart: one is a wait, the other is the end of the line.
            if not anchor.analysis_complete:
                raise CommandError(
                    "no_variation", "l'analyse de cette position n'est pas encore revenue"
                )
            raise CommandError("no_variation", "KataGo ne propose rien au-delà de ce point")
        node = self.game.current_node
        move = Move.from_gtp(self._anchor_pv[depth], player=node.next_player)
        if move.is_pass:
            raise CommandError("no_variation", "la variante proposée s'arrête sur une passe")
        before = list(node.children)
        try:
            played = self.game.play(move)
        except IllegalMoveException as exc:
            raise CommandError("illegal_move", str(exc)) from exc
        created = all(child is not played for child in before)
        self._variation.append((node, played, created))
        self._emit_state(command_id)

    def _pop_variation(self, command_id) -> None:
        if not self._variation:
            raise CommandError("no_variation", "il n'y a pas de variante à remonter")
        parent, node, created = self._variation.pop()
        self.game.set_current_node(parent)
        if created:
            parent.children = [child for child in parent.children if child is not node]
        if not self._variation:
            self._anchor_pv = []
        self._emit_state(command_id)

    def _prune_variation(self) -> None:
        """Drops the whole variation branch, keeping whatever belongs to the record."""
        while self._variation:
            parent, node, created = self._variation.pop()
            if created:
                parent.children = [child for child in parent.children if child is not node]
        self._anchor_pv = []

    def _boost_window(self) -> None:
        """Pushes the current node and the ones just behind it to the front of the queue."""
        if self._engine is None:
            return
        lower = max(0, self._index - self.PRIORITY_WINDOW)
        # Reversed: the position on screen is asked for first, its neighbours after.
        for node in reversed(self._line[lower : self._index + 1]):
            key = id(node)
            if key in self._boosted or node.analysis_complete:
                continue
            self._boosted.add(key)
            node.analyze(self._engine, priority=PRIORITY_DEFAULT)

    def _best_move(self) -> Optional[Dict[str, Any]]:
        """The point to mark: KataGo's first choice, or the variation's next move.

        Inside a variation the marker keeps coming from the anchor's own line, which
        is also what the next step will play. Those nodes carry no analysis of their
        own, and asking for one would cost a wait for no gain in the reading.
        """
        size = serialize.board_size(self.game)
        depth = len(self._variation)
        if depth == 0:
            return review.best_move(self._line[self._index], size)
        if depth >= len(self._anchor_pv):
            return None
        move = Move.from_gtp(self._anchor_pv[depth], player=self.game.current_node.next_player)
        if move.is_pass:
            return None
        return {**to_display_coords(move.coords, size), "points_lost": 0.0}

    def _emit_review_state(self, command_id: Optional[int] = None) -> None:
        self._writer.emit(
            "state",
            command_id,
            **serialize.game_state(
                self.game,
                self._human_color,
                status="review",
                result=self._game_info.get("result"),
                review={
                    "move_number": self._index,
                    "move_count": len(self._line) - 1,
                    "score_history": [node.score for node in self._line],
                    "game_info": self._game_info,
                    "variation_depth": len(self._variation),
                    "best_move": self._best_move(),
                },
            ),
        )

    def _require_review(self) -> None:
        if self._status != "review":
            raise CommandError("not_reviewing", "aucune partie n'est en cours de revue")

    def _refuse_in_review(self) -> None:
        if self._status == "review":
            raise CommandError("not_playing", "la partie est en revue, pas en cours")

    # -- ai ------------------------------------------------------------------

    @property
    def _ai_color(self) -> str:
        return "W" if self._human_color == "B" else "B"

    @property
    def _ai_strategy(self) -> str:
        return self.players_info[self._ai_color].strategy

    def available_strategies(self) -> Dict[str, Any]:
        """The AI modes this installation actually has settings for.

        Taken from KaTrain's own recommended order rather than a list of our own, so
        a mode added upstream shows up without a change here.
        """
        strategies = [s for s in AI_STRATEGIES_RECOMMENDED_ORDER if self.config(f"ai/{s}") is not None]
        return {
            "strategies": strategies,
            "ai_settings": {s: self.config(f"ai/{s}") for s in strategies},
        }

    def set_ai(self, command_id, strategy, settings):
        """Switches the AI mode mid-game; it applies from its next move."""
        self._require_game()
        self._refuse_in_review()
        current = self.config(f"ai/{strategy}")
        if current is None:
            raise CommandError("unknown_ai", f"AI strategy {strategy} not found")
        if settings:
            current.update(settings)
        self.players_info[self._ai_color].update(PLAYER_AI, strategy)
        self._emit_state(command_id)

    def _require_game(self) -> None:
        if self.game is None:
            raise CommandError("no_game", "no game in progress")
