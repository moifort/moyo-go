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

import follow
import local
import record
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
        self._status = "playing"  # playing | scoring | finished | review | following
        #: Following a game on a real board: the next position seen is the start,
        #: placed as it is, since the game may be joined halfway through.
        self._follow_fresh = False
        #: False when the last position seen could not be reached by any move.
        self._follow_in_sync = True
        #: KataGo at work while following: each move analysed for the score and the
        #: curve, plus the best move and, in the zone of the last move, the best
        #: local move with what it costs. Off, KataGo computes nothing.
        self._follow_analysis = False
        self._dead: set = set()
        #: The player asked to see the score estimated from KataGo's ownership map.
        #: It stays on, move after move, until they turn it off.
        self._estimating = False
        #: What the last state said of the estimate, so a fresher ownership map is
        #: sent only when it changes the count.
        self._emitted_estimate: Optional[tuple] = None
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
        #: Whose line the variation follows: "best" for KataGo's own, "local" for
        #: the reading kept inside the zone of the fight.
        self._variation_kind = "best"
        #: The local reading of each position looked at, by node id: its zone, and
        #: KataGo's answer once it is back. Only positions put on screen are asked
        #: for, so a record costs one extra analysis per position actually read.
        self._local: Dict[int, Dict[str, Any]] = {}
        #: The zone the player drew, in place of the inferred one. It stays while
        #: the record is walked — a fight is read over several moves — until cleared.
        self._drawn_zone: Optional[Dict[str, int]] = None
        #: The player asked for the local sequence before KataGo had read it. The
        #: first move is played as soon as the reading lands, rather than the press
        #: being lost and the board looking stuck.
        self._local_wanted = False
        #: A further local reading asked from the end of the sequence being walked,
        #: so the fight can be followed to its end rather than to the end of one
        #: KataGo line: {"node", "depth", "wanted", "done"}. `done` once KataGo
        #: has nothing left to play in the zone.
        self._local_extension: Optional[Dict[str, Any]] = None
        self._game_info: Dict[str, Any] = {}
        #: Every node the record came with, branches included, and the command that
        #: opened it. Once all of them are analysed the record goes back to the app
        #: to be written over its file; variation nodes are not part of it.
        self._recorded: List[Any] = []
        self._record_command: Optional[int] = None
        self._record_sent = False
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
        if self._estimating and self._estimate_key(self._estimate()) != self._emitted_estimate:
            self._emit_state()
        if self._status == "review":
            self._on_review_advanced()
            return
        if self._status == "following":
            self._on_following_advanced()
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
        self._send_analysed_record()
        best = self._best_move()
        key = None if best is None else (best["row"], best["col"])
        # The local move's cost is measured against this very analysis, so a
        # deeper reading of the whole board can change it under a still marker.
        nearby = self._local_move()
        key = (key, None if nearby is None else nearby["points_lost"])
        if key != self._emitted_best:
            self._emitted_best = key
            self._emit_state()

    def _on_following_advanced(self) -> None:
        """An analysis came back while following: move the markers, if they are shown."""
        if not self._follow_analysis:
            return
        key = (self._hint_key(), id(self.game.current_node))
        if key != self._emitted_best:
            self._emitted_best = key
            self._emit_state()

    def _hint_key(self):
        best = review.best_move(self.game.current_node, self._size())
        nearby = self._local_move()
        return (
            None if best is None else (best["row"], best["col"]),
            None if nearby is None else (nearby["row"], nearby["col"], nearby["points_lost"]),
        )

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

    def _send_analysed_record(self) -> None:
        """Hands the record back with its analysis, once every position has one.

        Only if KataGo did some of the work: a file that came fully analysed would
        be written over with what it already says. The text leaves out the variation
        being walked — the file gets its analysis, not the player's exploration.
        """
        if self._record_sent or not self._recorded:
            return
        if not all(node.analysis_complete for node in self._recorded):
            return
        self._record_sent = True
        if all(node.analysis_from_sgf for node in self._recorded):
            return
        self._writer.emit(
            "record_analysed",
            self._record_command,
            contents=record.text(self.game.root, nodes=self._recorded),
        )

    def _maybe_play_ai_move(self) -> None:
        """Reproduces the core's own trigger condition for an AI move.

        Mirrors katrain/__main__.py: the AI only moves once the current node's
        analysis is complete, it is the AI's turn, and the game has not ended.

        One condition is left out: KaTrain also waits for the node to have no
        children, so the AI keeps still while the player browses the tree. Nothing
        browses here — `_ai_pending` already says the AI owes a move — and the tree
        keeps what an undo took back: a move replayed after an undo, or a count
        called off after the AI's pass, lands on a node with children, and the AI
        would wait forever.
        """
        node = self.game.current_node
        if not self._ai_pending:
            return
        if not (node.analysis_complete and not self.game.end_result):
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
        if self._status == "following":
            self._writer.emit(
                "state",
                command_id,
                **serialize.game_state(
                    self.game,
                    self._human_color,
                    status="following",
                    extra=self._follow_extra(),
                    **self._estimate_fields(),
                ),
            )
            return
        result = self.game.current_node.end_state if self._status == "finished" else None
        # A resigned game has nothing to count: the stones on the board were never
        # agreed on, and a territory table would contradict the result above it.
        counted = (
            self._count()
            if self._status == "scoring" or (self._status == "finished" and not self._ended_by_resignation())
            else None
        )
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
                **self._estimate_fields(),
            ),
        )

    # -- score estimate ------------------------------------------------------

    def set_estimate(self, command_id, on):
        """Shows or hides the score estimated from KataGo's ownership map."""
        self._require_game()
        self._estimating = bool(on)
        self._emit_state(command_id)

    def _estimate(self) -> Optional[Dict[str, Any]]:
        """The score KataGo's ownership map points to, while the player asks for it.

        Averaged with the position before, as KaTrain's own manual score does: the
        map leans towards whoever is to move, and the mean takes that lean out.
        Nothing once the game is being counted for real.
        """
        if not self._estimating or self._status in ("scoring", "finished"):
            return None
        node = self.game.current_node
        ownership = node.ownership
        before = node.parent.ownership if node.parent is not None else None
        if ownership and before and len(before) == len(ownership):
            ownership = [(now + then) / 2 for now, then in zip(ownership, before)]
        return scoring.estimate(
            size=self._size(),
            stones=serialize.stone_map(self.game),
            ownership=ownership,
            komi=self.game.root.komi,
            captures=serialize.captures(self.game),
            rules=str(self.game.root.ruleset or "japanese"),
            lead=node.score,
        )

    def _estimate_key(self, counted: Optional[Dict[str, Any]]) -> Optional[tuple]:
        if counted is None:
            return None
        return (id(self.game.current_node), counted["lead"], len(counted["points"]), len(counted["dead"]))

    def _estimate_fields(self) -> Dict[str, Any]:
        counted = self._estimate()
        self._emitted_estimate = self._estimate_key(counted)
        return {"estimating": self._estimating, "estimate": counted}

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

    def _ended_by_resignation(self) -> bool:
        return str(self.game.current_node.end_state or "").endswith("+R")

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
        """Steps back until it is the human's turn again, two moves in the usual case.

        Not once the game is over: a resignation or an accepted count is final, and
        the next game starts from the new-game sheet.
        """
        self._require_game()
        self._refuse_in_review()
        self._refuse_when_over()
        self._refuse_when_following()
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
        """Ends the game on the spot: no count, and nothing more is played."""
        self._require_game()
        self._refuse_in_review()
        if self._status != "playing":
            raise CommandError("not_playing", "the game is over")
        self._status = "finished"
        self._dead = set()
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
        self._variation_kind = "best"
        self._local = {}
        self._drawn_zone = None
        self._local_wanted = False
        self._local_extension = None
        self._game_info = {}
        self._recorded = []
        self._record_command = None
        self._record_sent = False
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
        self._recorded = list(self.game.root.nodes_in_tree)
        self._record_command = command_id
        self._index = len(self._line) - 1
        self.game.set_current_node(self._line[self._index])
        self._boost_window()
        self._request_local(ask=True)
        self._emit_state(command_id)

    def export_sgf(self, command_id, black_name, white_name):
        """Hands the game over as SGF text, for the app to write where the player chose.

        A game against the AI goes out as the line actually on the board: moves taken
        back stay in KaTrain's tree but were never part of the game. A record under
        review goes out whole, as it came in — names, result, branches — plus the
        variation being walked, which is how a reading of KataGo's is kept.
        """
        self._require_game()
        if self._status == "review":
            text = record.text(self.game.root)
        else:
            text = record.text(
                self.game.root,
                nodes=self.game.current_node.nodes_from_root,
                properties={
                    "AP": "Moyo",
                    "DT": record.sgf_date(self.game.root.get_property("DT", None)),
                    "PB": black_name or None,
                    "PW": white_name or None,
                    "RE": self.game.end_result or None,
                },
            )
        self._writer.emit("sgf", command_id, contents=text)

    def goto(self, command_id, move_number):
        """Jumps to a position in the main line. Out-of-range asks are clamped."""
        self._require_review()
        self._prune_variation()
        self._local_wanted = False
        self._index = max(0, min(int(move_number), len(self._line) - 1))
        self.game.set_current_node(self._line[self._index])
        self._emitted_best = None
        self._boost_window()
        self._request_local(ask=True)
        self._emit_state(command_id)

    def step_variation(self, command_id, step, kind="best"):
        """Walks a continuation one move per call, colours alternating.

        `kind` picks the line: KataGo's own, or the local sequence. Starting one
        while walking the other goes back to the record first, so the board never
        shows half of each.
        """
        self._require_review()
        if kind not in ("best", "local"):
            raise CommandError("bad_arguments", f"unknown variation kind '{kind}'")
        self._local_wanted = False
        if int(step) > 0:
            if self._variation and kind != self._variation_kind:
                self._prune_variation()
                self.game.set_current_node(self._line[self._index])
            if kind == "local" and not self._variation:
                self._request_local(ask=True)
            if kind == "local" and not self._variation and self._local_pending():
                self._local_wanted = True
                self._emit_state(command_id)
                return
            self._variation_kind = kind
            self._push_variation(command_id)
        else:
            self._pop_variation(command_id)

    def _anchor_line(self) -> List[str]:
        """The continuation the current variation follows, as it stands right now."""
        anchor = self._line[self._index]
        if self._variation_kind == "best":
            return review.variation(anchor)
        reading = self._local.get(id(anchor))
        if not reading or reading["analysis"] is None:
            return []
        prefer = local.whole_board_choice(anchor, reading["zone"], self._size())
        return local.variation(reading["analysis"], reading["zone"], self._size(), prefer)

    def _refresh_anchor_pv(self) -> None:
        """Takes a longer continuation from the anchor once the analysis has deepened.

        The first press often lands on a reading built from the policy alone, whose
        continuation is a single move. Freezing that would stop the walk at the
        shallowest view KataGo ever had of the position. A fresher line is adopted
        only when it still begins with the moves already on the board, so the branch
        under the player's eyes is extended and never rewritten.
        """
        fresh = self._anchor_line()
        walked = len(self._variation)
        if len(fresh) <= len(self._anchor_pv):
            return
        if fresh[:walked] != self._anchor_pv[:walked]:
            return
        self._anchor_pv = fresh

    def _push_variation(self, command_id) -> None:
        anchor = self._line[self._index]
        if not self._variation:
            self._anchor_pv = self._anchor_line()
        else:
            self._refresh_anchor_pv()
        depth = len(self._variation)
        if depth >= len(self._anchor_pv):
            if self._variation_kind == "local":
                if self._extend_local(wanted=True):
                    self._emit_state(command_id)
                    return
                self._refuse_local_end(anchor)
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
        if self._variation_kind == "local" and len(self._variation) >= len(self._anchor_pv):
            # The last move KataGo read: read on now, so the next press finds it ready.
            self._extend_local(wanted=False)
        self._emit_state(command_id)

    def _extend_local(self, wanted: bool) -> bool:
        """Has KataGo read on from the end of the local sequence, in the same zone.

        True when a reading is on its way, its first move to be played on arrival if
        `wanted`; False when there is nothing more to read: KataGo already passed or
        left the zone from here, or the sequence is as long as it is allowed to get.
        """
        depth = len(self._variation)
        if self._variation_kind != "local" or depth == 0 or depth >= local.LONGEST:
            return False
        extension = self._local_extension
        if extension is not None and extension["depth"] == depth:
            if extension["done"]:
                return False
            extension["wanted"] = extension["wanted"] or wanted
            return True
        reading = self._local.get(id(self._line[self._index]))
        if not reading or reading["zone"] is None:
            return False
        node = self.game.current_node
        self._local_extension = {"node": node, "depth": depth, "wanted": wanted, "done": False}
        self._send_local_query(node, reading["zone"])
        return True

    def _on_local_failure(self, node, analysis) -> None:
        """KataGo refused a local query: a reading on from the end stops there."""
        self._log_stderr(f"local analysis failed: {analysis}")
        extension = self._local_extension
        if extension is not None and node is extension["node"]:
            extension["done"] = True
            extension["wanted"] = False
            self._emit_state()

    def _on_local_extension(self, analysis, zone) -> None:
        """A reading from the end of the sequence: append it, and play on if asked."""
        extension = self._local_extension
        if extension is None or self.game.current_node is not extension["node"]:
            return  # the walk has moved since; its answer no longer fits the board
        line = local.variation(analysis, zone, self._size()) if zone is not None else []
        if not line:
            extension["done"] = True
            extension["wanted"] = False
            self._emit_state()
            return
        self._anchor_pv = self._anchor_pv[: extension["depth"]] + line
        self._local_extension = None
        if extension["wanted"]:
            try:
                self._push_variation(None)
                return
            except CommandError:
                pass
        self._emit_state()

    def _refuse_local_end(self, anchor) -> None:
        reading = self._local.get(id(anchor))
        if not reading or reading["zone"] is None:
            raise CommandError("no_variation", "aucun combat local à cette position")
        if reading["analysis"] is None:
            raise CommandError("no_variation", "l'analyse locale n'est pas encore revenue")
        raise CommandError("no_variation", "la séquence locale s'arrête là")

    def _pop_variation(self, command_id) -> None:
        if not self._variation:
            raise CommandError("no_variation", "il n'y a pas de variante à remonter")
        parent, node, created = self._variation.pop()
        self.game.set_current_node(parent)
        if created:
            parent.children = [child for child in parent.children if child is not node]
        self._local_extension = None
        if not self._variation:
            self._anchor_pv = []
            self._variation_kind = "best"
        self._emit_state(command_id)

    def _prune_variation(self) -> None:
        """Drops the whole variation branch, keeping whatever belongs to the record."""
        while self._variation:
            parent, node, created = self._variation.pop()
            if created:
                parent.children = [child for child in parent.children if child is not node]
        self._anchor_pv = []
        self._variation_kind = "best"
        self._local_extension = None

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
        own, and asking for one would cost a wait for no gain in the reading. A local
        sequence being walked has no whole-board marker: it is not the best move.
        """
        size = serialize.board_size(self.game)
        depth = len(self._variation)
        if depth == 0:
            return review.best_move(self._line[self._index], size)
        if self._variation_kind != "best":
            return None
        return self._next_in_variation(0.0)

    def _next_in_variation(self, points_lost) -> Optional[Dict[str, Any]]:
        depth = len(self._variation)
        if depth >= len(self._anchor_pv):
            return None
        move = Move.from_gtp(self._anchor_pv[depth], player=self.game.current_node.next_player)
        if move.is_pass:
            return None
        return {**to_display_coords(move.coords, self._size()), "points_lost": points_lost}

    # -- local reading -------------------------------------------------------

    def set_local_zone(self, command_id, zone):
        """Reads the fight inside a zone the player drew; None goes back to the inferred one.

        Whatever was read for the old zone no longer answers the question, so the
        position on screen is asked again. A local sequence being walked belonged to
        the old zone too: the board goes back to the record.
        """
        self._require_review()
        if zone is not None:
            try:
                zone = local.drawn(zone, self._size())
            except (KeyError, TypeError, ValueError) as exc:
                raise CommandError("bad_arguments", str(exc)) from exc
        self._drawn_zone = zone
        self._local_wanted = False
        if self._variation:
            self._prune_variation()
            self.game.set_current_node(self._line[self._index])
        # A zone just drawn is a question asked: read it straight away.
        self._request_local(ask=True)
        self._emit_state(command_id)

    def _focus_node(self):
        """The position the local reading is about: the record's, or the game's own."""
        return self._line[self._index] if self._status == "review" else self.game.current_node

    def _request_local(self, ask: bool = False) -> None:
        """Places the zone of the position on screen; `ask` also has KataGo read it.

        The zone costs nothing and is placed on every move, so the keys and buttons
        know whether there is a fight to read. A review asks for the reading of every
        position it lands on, since the board shows it next to the best move; a
        followed game only when its analysis is on. The reading is asked for once per
        position and zone.
        """
        node = self._focus_node()
        if self._engine is None:
            return
        zone = self._drawn_zone or local.region(
            serialize.stone_map(self.game), self._size(), serialize.last_move(self.game)
        )
        reading = self._local.get(id(node))
        if reading is None or reading["zone"] != zone:
            reading = {"zone": zone, "analysis": None, "asked": False}
            self._local[id(node)] = reading
        if ask and zone is not None and not reading["asked"]:
            reading["asked"] = True
            self._send_local_query(node, zone)

    def _send_local_query(self, node, zone) -> None:
        """The only call that reaches KataGo for a local reading; tests replace it."""
        local.request(
            self._engine,
            node,
            zone,
            self._size(),
            on_result=lambda analysis: self.submit(self._on_local_analysis, node, analysis, zone),
            on_error=lambda analysis: self.submit(self._on_local_failure, node, analysis),
            # Ahead of the neighbours `_boost_window` queues at the default priority:
            # the player is looking at this position, and may already be waiting.
            priority=PRIORITY_DEFAULT + 1,
        )

    def _on_local_analysis(self, node, analysis, zone=None) -> None:
        extension = self._local_extension
        if extension is not None and node is extension["node"]:
            self._on_local_extension(analysis, zone)
            return
        reading = self._local.get(id(node))
        if reading is None or self._status not in ("review", "following"):
            return  # another record has been opened since
        if zone is not None and reading["zone"] != zone:
            return  # the answer to a zone redrawn since
        reading["analysis"] = analysis
        if node is not self._focus_node():
            return
        if self._local_wanted and not self._variation:
            self._local_wanted = False
            self._variation_kind = "local"
            try:
                self._push_variation(None)
                return
            except CommandError:
                self._variation_kind = "best"  # nothing to walk after all: just show it
        self._emit_state()

    def _local_pending(self) -> bool:
        """KataGo has been asked about the zone on screen and has not answered yet.

        Inside the local sequence, that is the reading on from its end.
        """
        if self._variation:
            extension = self._local_extension
            return bool(
                self._variation_kind == "local"
                and extension is not None
                and not extension["done"]
                and extension["depth"] == len(self._variation)
            )
        reading = self._local.get(id(self._focus_node()))
        return bool(reading and reading.get("asked") and reading["analysis"] is None)

    def _local_reading(self) -> Optional[Dict[str, Any]]:
        if self._variation and self._variation_kind != "local":
            return None
        return self._local.get(id(self._focus_node()))

    def _local_zone(self) -> Optional[Dict[str, int]]:
        """The zone on screen: on the record itself, and while its sequence is walked."""
        reading = self._local_reading()
        return reading["zone"] if reading else None

    def _local_move(self) -> Optional[Dict[str, Any]]:
        """The local marker: the zone's best move, or the local sequence's next one."""
        reading = self._local_reading()
        if not reading or reading["analysis"] is None:
            return None
        if self._variation:
            return self._next_in_variation(None)
        node = self._focus_node()
        prefer = local.whole_board_choice(node, reading["zone"], self._size())
        return local.best_move(reading["analysis"], node, self._size(), prefer)

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
                    "variation_kind": self._variation_kind if self._variation else None,
                    "best_move": self._best_move(),
                    "local_move": self._local_move(),
                    "local_zone": self._local_zone(),
                    "local_zone_drawn": self._drawn_zone is not None,
                    "local_pending": self._local_pending(),
                    "local_wanted": self._local_wanted
                    or bool(self._local_extension and self._local_extension["wanted"]),
                },
                **self._estimate_fields(),
            ),
        )

    def _require_review(self) -> None:
        if self._status != "review":
            raise CommandError("not_reviewing", "aucune partie n'est en cours de revue")

    def _refuse_when_over(self) -> None:
        if self._status == "finished":
            raise CommandError("not_playing", "the game is over")

    def _refuse_when_following(self) -> None:
        if self._status == "following":
            raise CommandError("not_playing", "la partie se joue sur le plateau, pas ici")

    def _refuse_in_review(self) -> None:
        if self._status == "review":
            raise CommandError("not_playing", "la partie est en revue, pas en cours")


    # -- following a game on a real board ------------------------------------

    def follow_start(self, command_id, size, komi, rules, analysis=False):
        """Starts following a game between two people, seen by the phone.

        Nobody is to move on the Mac: both players are human, the AI never plays,
        and KataGo only analyses. The game proper starts with the next position.
        """
        if self._engine is None:
            raise CommandError("no_engine", "engine not started")
        for color in ("B", "W"):
            self.players_info[color].update(PLAYER_HUMAN, PLAYING_NORMAL)
        self._human_color = "B"
        self._clear_review()
        self._emitted_scores.clear()
        self._dead = set()
        self._ai_pending = False
        self._status = "following"
        self._follow_fresh = True
        self._follow_in_sync = True
        self._follow_analysis = bool(analysis)
        self.game = Game(self, self._engine, game_properties={"SZ": size, "KM": komi, "RU": rules})
        self._writer.emit("thinking", None, value=False)
        self._emit_state(command_id)

    def follow_board(self, command_id, rows):
        """The position on the real board changed: find the moves that lead there.

        Forward first — a move, a pass and a move, one move each — then back to an
        earlier position, a move taken back, then a correction a few moves back.
        Every candidate is played through the core and kept only if the board it
        produces is the one seen, captures included.
        """
        self._require_following()
        size = self._size()
        target = follow.read_rows(rows, size)
        if self._follow_fresh:
            self._follow_fresh = False
            if target:
                self._join_halfway(target, size)
            self._follow_in_sync = True
            self._emit_state(command_id)
            return
        self._follow_in_sync = self._reach(target)
        self._request_local(ask=self._follow_analysis)
        self._emit_state(command_id)

    def _follow_extra(self) -> Dict[str, Any]:
        extra: Dict[str, Any] = {"in_sync": self._follow_in_sync, "analysis": self._follow_analysis}
        if self._follow_analysis:
            extra.update(
                best_move=review.best_move(self.game.current_node, self._size()),
                local_move=self._local_move(),
                local_zone=self._local_zone(),
                local_pending=self._local_pending(),
            )
        return extra

    def follow_analysis(self, command_id, on):
        """Switches KataGo on or off while following.

        Off, what is queued is dropped and nothing new is asked. On again, the
        position on the board is read first, then the moves played meanwhile, so
        the curve fills its gaps behind the figure that matters.
        """
        self._require_following()
        self._follow_analysis = bool(on)
        if self._follow_analysis:
            for node in reversed(self.game.current_node.nodes_from_root):
                if not node.analysis_complete:
                    node.analyze(self.game.engines[node.next_player])
        elif self._engine is not None:
            self._engine.terminate_queries()
        self._request_local(ask=self._follow_analysis)
        self._emit_state(command_id)

    def _join_halfway(self, target, size) -> None:
        """The first position already has stones: place them as the game's setup."""
        properties = dict(self.game.root.properties)
        self.game = Game(self, self._engine, game_properties={**properties, **follow.setup_properties(target, size)})

    def _reach(self, target) -> bool:
        start = self.game.current_node
        if serialize.stone_map(self.game) == target or self._play_towards(target):
            return True
        line = start.nodes_from_root
        for node in reversed(line[:-1]):
            self.game.set_current_node(node)
            if serialize.stone_map(self.game) == target:
                return True
        for node in reversed(line[-1 - follow.CORRECTION_DEPTH : -1]):
            self.game.set_current_node(node)
            if self._play_towards(target):
                return True
        self.game.set_current_node(start)
        return False

    def _play_towards(self, target) -> bool:
        """Tries the candidate sequences from the current node; keeps the first that fits."""
        start = self.game.current_node
        size = self._size()
        saved_pl = start.get_property("PL", None)
        # Only a setup leaves the turn open; an empty board is Black's to start.
        turn_unknown = start.is_root and not start.children and bool(start.placements)
        before = serialize.stone_map(self.game)
        for sequence in follow.candidates(before, target, start.next_player, turn_unknown):
            played, created = [], []
            try:
                for step in sequence:
                    node = self.game.current_node
                    if step is None:
                        move = Move(coords=None, player=node.next_player)
                    else:
                        color, (row, col) = step
                        if color != node.next_player and turn_unknown and node is start:
                            # Joined halfway: the first move seen says who was to move.
                            node.set_property("PL", color)
                        move = Move(coords=to_engine_coords(row, col, size), player=color)
                    before = list(node.children)
                    child = self.game.play(move, analyze=False)
                    played.append(child)
                    if all(other is not child for other in before):
                        created.append((node, child))
                if serialize.stone_map(self.game) == target:
                    if self._follow_analysis:
                        for node in played:
                            node.analyze(self.game.engines[node.next_player])
                    return True
            except IllegalMoveException:
                pass
            for parent, child in created:
                parent.children = [other for other in parent.children if other is not child]
            if start.get_property("PL", None) != saved_pl:
                start.set_property("PL", saved_pl) if saved_pl else start.clear_property("PL")
            self.game.set_current_node(start)
        return False

    def follow_end(self, command_id, result):
        """The game on the real board is over: open it as a record under review.

        The analyses already made are kept, and the record is the line actually
        followed: corrections and moves taken back stay in the tree, off the line.
        """
        self._require_following()
        if result:
            self.game.root.set_property("RE", result)
        line = self.game.current_node.nodes_from_root
        self._clear_review()
        self._status = "review"
        self._line = line
        self._game_info = review.game_info(self.game.root)
        self._index = len(line) - 1
        self.game.set_current_node(line[self._index])
        self._boost_window()
        self._request_local(ask=True)
        self._emit_state(command_id)

    def _require_following(self) -> None:
        if self._status != "following":
            raise CommandError("not_following", "aucune partie n'est suivie")

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
        self._refuse_when_following()
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
