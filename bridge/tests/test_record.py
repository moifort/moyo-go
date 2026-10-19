"""Writing a game record: the tree back to SGF text.

Pure, like `review`: a tree goes in, text comes out. Every test reads its own output
back through the same parser the app uses on import, so a record Moyo writes is one
Moyo can open.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

import record
import review

RECORD = (
    "(;GM[1]FF[4]SZ[19]KM[6.5]RU[japanese]"
    "PB[Shusaku]PW[Gennan]RE[B+2]DT[1846-07-21]"
    ";B[qd];W[dp];B[oc];W[dd])"
)

BRANCHED = "(;GM[1]FF[4]SZ[9];B[ee](;W[cc]C[the joseki];B[gg])(;W[gg]))"


def moves(root):
    return [node.move.gtp() for node in review.main_line(root)[1:]]


def test_a_record_reads_back_move_for_move():
    written = record.text(review.parse(RECORD))
    assert moves(review.parse(written)) == ["R16", "D4", "P17", "D16"]


def test_the_record_keeps_what_it_says_about_the_game():
    info = review.game_info(review.parse(record.text(review.parse(RECORD))))
    assert info["black_name"] == "Shusaku"
    assert info["result"] == "B+2"
    assert info["date"] == "1846-07-21"


def test_branches_and_comments_survive():
    written = record.text(review.parse(BRANCHED))
    first = review.parse(written).children[0]
    assert [child.move.gtp() for child in first.children] == ["C7", "G3"]
    # KaTrain lifts C[] out of the properties and into the node's note on reading.
    assert "W[cc]C[the joseki]" in written


def test_a_line_writes_that_line_and_nothing_else():
    root = review.parse(BRANCHED)
    line = [root, root.children[0], root.children[0].children[1]]
    reread = review.parse(record.text(root, nodes=line))
    assert moves(reread) == ["E5", "G3"]
    assert len(reread.children[0].children) == 1


def test_written_as_utf8_whatever_the_file_said():
    root = review.parse("(;GM[1]FF[4]CA[GB2312]SZ[9]PB[本因坊秀策];B[ee])")
    written = record.text(root)
    assert "CA[UTF-8]" in written
    assert "GB2312" not in written
    assert review.game_info(review.parse(written))["black_name"] == "本因坊秀策"


def test_properties_given_override_the_root():
    written = record.text(review.parse(RECORD), properties={"PB": "Moi", "AP": "Moyo"})
    reread = review.parse(written)
    assert reread.get_property("PB") == "Moi"
    assert reread.get_property("AP") == "Moyo"
    assert reread.get_property("PW") == "Gennan"


def test_an_empty_property_given_removes_it():
    written = record.text(review.parse(RECORD), properties={"RE": None})
    assert "RE[" not in written


def test_brackets_and_backslashes_are_escaped():
    written = record.text(review.parse("(;GM[1]FF[4]SZ[9];B[ee])"), properties={"GN": "a]b\\c"})
    assert review.parse(written).get_property("GN") == "a]b\\c"


def test_the_date_is_cut_to_the_day():
    assert record.sgf_date("2026-10-10 15 04 33") == "2026-10-10"
    assert record.sgf_date("1846-07-21") == "1846-07-21"
    assert record.sgf_date("1846-07-21,22") == "1846-07-21,22"
    assert record.sgf_date(None) is None


def full_analysis(score_lead, size=9):
    """What KataGo hands back for a position, ownership and policy included."""
    return {
        "completed": True,
        "root": {"scoreLead": score_lead, "winrate": 0.5, "visits": 500},
        "moves": {"C3": {"move": "C3", "order": 0, "scoreLead": score_lead, "winrate": 0.5,
                         "visits": 400, "pv": ["C3", "D4"]}},
        "ownership": [0.5] * (size * size),
        "policy": [0.25] * (size * size + 1),
    }


def test_an_analysis_goes_out_and_comes_back():
    root = review.parse("(;GM[1]FF[4]SZ[9];B[ee];W[cc])")
    first = root.children[0]
    first.analysis = full_analysis(2.5)
    reread = review.parse(record.text(root))
    node = reread.children[0]
    # KaTrain's own format: read back by the same call KaTrain makes on opening.
    assert node.load_analysis()
    assert node.analysis_complete
    assert node.analysis["root"]["scoreLead"] == 2.5
    assert node.analysis["moves"]["C3"]["pv"] == ["C3", "D4"]
    assert len(node.analysis["ownership"]) == 81
    assert reread.get_property("KTV") == "1.0"


def test_a_position_not_yet_analysed_goes_out_without_one():
    root = review.parse("(;GM[1]FF[4]SZ[9];B[ee];W[cc])")
    root.children[0].analysis = full_analysis(2.5)
    reread = review.parse(record.text(root))
    assert not reread.children[0].children[0].load_analysis()


def test_a_record_with_no_analysis_carries_no_marker_of_it():
    written = record.text(review.parse(RECORD))
    assert "KT" not in written


def test_an_analysis_read_but_not_yet_unpacked_is_kept():
    root = review.parse("(;GM[1]FF[4]SZ[9];B[ee])")
    root.children[0].analysis = full_analysis(-1.0)
    stored = review.parse(record.text(root))
    # Straight out of the parser: the analysis is still the text the file carried.
    reread = review.parse(record.text(stored))
    assert reread.children[0].load_analysis()
    assert reread.children[0].analysis["root"]["scoreLead"] == -1.0
