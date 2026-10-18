"""The zone of the fight and the reading kept inside it, without KataGo."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

import local


def test_no_zone_without_a_last_move():
    assert local.region({}, 19, None) is None


def test_a_lone_stone_gets_the_smallest_zone():
    zone = local.region({(9, 9): "B"}, 19, {"row": 9, "col": 9})
    assert zone == {"top": 6, "left": 6, "bottom": 12, "right": 12}


def test_the_zone_takes_in_every_group_touching_the_last_move():
    # A white stone at (9, 9) touches a black chain running down to row 14.
    stones = {(9, 9): "W", (10, 9): "B", (11, 9): "B", (12, 9): "B", (13, 9): "B", (14, 9): "B"}
    stones[(3, 3)] = "B"  # far away, not part of the fight
    zone = local.region(stones, 19, {"row": 9, "col": 9})
    assert zone == {"top": 7, "left": 6, "bottom": 16, "right": 12}


def test_a_corner_zone_stays_on_the_board():
    zone = local.region({(0, 0): "B"}, 19, {"row": 0, "col": 0})
    assert zone == {"top": 0, "left": 0, "bottom": 6, "right": 6}


def test_a_zone_as_wide_as_the_board_is_no_zone():
    stones = {(r, 4): "B" for r in range(9)}
    stones.update({(4, c): "B" for c in range(9)})
    assert local.region(stones, 9, {"row": 4, "col": 4}) is None


def test_the_sequence_stops_where_it_leaves_the_zone_or_passes():
    zone = {"top": 0, "left": 2, "bottom": 6, "right": 8}
    analysis = {"moveInfos": [{"move": "G6", "order": 0, "pv": ["G6", "H6", "A1", "G7"]}]}
    assert local.variation(analysis, zone, 9) == ["G6", "H6"]
    analysis = {"moveInfos": [{"move": "G6", "order": 0, "pv": ["G6", "pass", "H6"]}]}
    assert local.variation(analysis, zone, 9) == ["G6"]


def test_the_first_choice_is_the_one_ranked_first():
    zone = {"top": 0, "left": 0, "bottom": 8, "right": 8}
    analysis = {
        "moveInfos": [
            {"move": "A1", "order": 1, "pv": ["A1"]},
            {"move": "B2", "order": 0, "pv": ["B2", "C3"]},
        ]
    }
    assert local.variation(analysis, zone, 9) == ["B2", "C3"]


def test_the_constraint_is_deepened_on_its_way_to_katago():
    sent = []

    class Engine:
        def send_query(self, query, *args):
            sent.append(query)

    deepened = local._Deepened(Engine(), 12)
    deepened.send_query({"avoidMoves": [{"player": "B", "untilDepth": 1}, {"player": "W", "untilDepth": 1}]}, None, None)
    assert [entry["untilDepth"] for entry in sent[0]["avoidMoves"]] == [12, 12]
