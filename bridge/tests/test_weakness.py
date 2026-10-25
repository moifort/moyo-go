"""The weak points of the groups on the board, picked out of KataGo's answers."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

import weakness

SIZE = 9

#: A white chain of two stones in the middle, a black one of three on the left.
STONES = {
    (4, 4): "W", (4, 5): "W",
    (2, 0): "B", (2, 1): "B", (2, 2): "B",
}


def ownership(white=-0.5, black=0.5):
    """A flat map, Black-positive: each chain owned as told, the rest neutral."""
    grid = [0.0] * (SIZE * SIZE)
    for (row, col), colour in STONES.items():
        grid[row * SIZE + col] = white if colour == "W" else black
    return grid


def answer(moves, root=None):
    """KataGo's answer: the root map, and each move with the map after it."""
    return {
        "ownership": root or ownership(),
        "moveInfos": [{"move": m, "visits": v, "ownership": own} for m, (own, v) in moves.items()],
    }


def test_a_point_that_matters_to_a_chain_stands_out():
    # Black at E4 leaves the white chain at -0.2 a stone; White there, at -0.8.
    black = answer({"E4": (ownership(white=-0.2), 20), "A1": (ownership(), 20)})
    white = answer({"E4": (ownership(white=-0.8), 20), "A1": (ownership(), 20)})
    assert weakness.points(black, white, STONES, SIZE, "B") == [{"row": 5, "col": 4, "color": "B", "swing": 1.2}]


def test_the_tempo_is_no_weak_point():
    # Wherever either colour plays, the chain fares the same.
    black = answer({"E4": (ownership(white=-0.2), 20), "A1": (ownership(white=-0.2), 20)})
    white = answer({"E4": (ownership(white=-0.2), 20), "A1": (ownership(white=-0.2), 20)})
    assert weakness.points(black, white, STONES, SIZE, "B") == []


def test_a_small_swing_is_noise():
    black = answer({"E4": (ownership(white=-0.45), 20)})
    white = answer({"E4": (ownership(white=-0.5), 20)})
    assert weakness.points(black, white, STONES, SIZE, "B") == []


def test_a_settled_chain_is_not_a_target():
    root = ownership(white=-0.95)
    black = answer({"E4": (ownership(white=-0.2), 20)}, root=root)
    white = answer({"E4": (ownership(white=-0.95), 20)}, root=root)
    assert weakness.points(black, white, STONES, SIZE, "B") == []


def test_only_the_other_colour_s_stones_count():
    # The point matters to the black chain: a white weak point, not a black one.
    black = answer({"D7": (ownership(black=0.9), 20)})
    white = answer({"D7": (ownership(black=0.1), 20)})
    assert weakness.points(black, white, STONES, SIZE, "B") == []
    assert weakness.points(white, black, STONES, SIZE, "W") == [{"row": 2, "col": 3, "color": "W", "swing": 2.4}]


def test_three_at_most_strongest_first():
    moves = {"E4": -0.0, "F4": -0.1, "G4": -0.2, "H4": -0.3}
    black = answer({m: (ownership(white=w), 20) for m, w in moves.items()})
    white = answer({m: (ownership(white=-0.9), 20) for m in moves})
    assert [p["swing"] for p in weakness.points(black, white, STONES, SIZE, "B")] == [1.8, 1.6, 1.4]


def test_a_point_one_colour_never_read_is_left_out():
    black = answer({"E4": (ownership(white=-0.2), 20)})
    white = answer({"E4": (ownership(white=-0.8), 1)})
    assert weakness.points(black, white, STONES, SIZE, "B") == []


def test_passes_and_answers_without_ownership_are_ignored():
    black = answer({"pass": (ownership(white=-0.2), 20)})
    white = answer({"pass": (ownership(white=-0.8), 20)})
    assert weakness.points(black, white, STONES, SIZE, "B") == []
    assert weakness.points({}, white, STONES, SIZE, "B") == []


def test_the_area_reaches_two_lines_around_the_stones():
    near = weakness.area({(0, 0): "B"}, SIZE)
    assert near == {(r, c) for r in range(3) for c in range(3)} - {(0, 0)}
    assert weakness.area({}, SIZE) == set()
