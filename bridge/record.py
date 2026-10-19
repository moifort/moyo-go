"""Writing a game record: a KaTrain tree back to SGF text.

The mirror of `review`, and pure in the same way: a tree goes in, text comes out.
The bridge never writes a file. The app asks for the text and writes it where the
player chose in the save panel — a grant the sandbox gives the window, not the
child process.

KaTrain's own `Game.write_sgf` is not used: it opens the file itself, names the
players through its own translations, and stamps the root with a comment and an
invisible marker meant for KaTrain alone. Only the properties the record actually
carries are written here: moves, setup stones, comments, the game information, and
KataGo's analysis of each position — in KaTrain's own `KT[]` format, so a record
opened again, here or in KaTrain, is not analysed a second time.
"""

import re
from typing import Any, Dict, Iterable, List, Optional

from katrain.core.constants import ANALYSIS_FORMAT_VERSION
from katrain.core.game_node import analysis_dumps

#: The text is handed to the app as a Python string and written out as UTF-8,
#: whatever charset the record declared when it was read.
CHARSET = "UTF-8"


def text(root, nodes: Optional[Iterable[Any]] = None, properties: Optional[Dict[str, Any]] = None) -> str:
    """The record as SGF text.

    `nodes`, when given, are the only ones written. A path from the root is how a
    game against the AI leaves out the moves taken back; the nodes a record came
    with are how its analysis is saved without the variation being walked. Without
    it the whole tree goes out, branches included.

    `properties` are laid over the root's own. A value of None removes the property.
    """
    root_properties = _root_properties(root, properties or {})
    written = None if nodes is None else {id(node) for node in nodes}

    def children(node) -> List[Any]:
        kept = node.ordered_children
        if written is not None:
            kept = [child for child in kept if id(child) in written]
        return kept

    analyses = {id(node): _analysis(node) for node in root.nodes_in_tree}
    if any(analyses.values()):
        root_properties["KTV"] = [ANALYSIS_FORMAT_VERSION]

    # Iterative, like pysgf's own writer: a long game is a deep tree.
    out: List[str] = []
    stack: List[Any] = [")", root, "("]
    while stack:
        item = stack.pop()
        if isinstance(item, str):
            out.append(item)
            continue
        properties = root_properties if item is root else _properties(item)
        if analyses.get(id(item)):
            properties = {**properties, "KT": analyses[id(item)]}
        out.append(_node_text(properties))
        following = children(item)
        if len(following) == 1:
            stack.append(following[0])
        elif following:
            for child in reversed(following):
                stack += [")", child, "("]
    return "".join(out)


def sgf_date(value: Optional[str]) -> Optional[str]:
    """KaTrain dates a new game with the time of day; SGF wants the day alone."""
    if not value:
        return None
    return str(value).split(" ")[0]


def _properties(node) -> Dict[str, List[Any]]:
    """What the node carries, its comment included.

    KaTrain lifts `C[]` out of the properties on reading and keeps it as the node's
    note, having already dropped the comments it generated itself. The note is the
    only place the record's own commentary still lives.
    """
    properties = {key: list(values) for key, values in node.properties.items()}
    note = (getattr(node, "note", "") or "").strip()
    if note:
        properties["C"] = [note]
    return properties


def _analysis(node) -> Optional[List[str]]:
    """The node's analysis as KaTrain stores it, or None when there is none to store.

    An analysis read from the file and not yet unpacked by KaTrain goes back out as
    the text it came in: saving early must not lose what the record already had.
    """
    if node.analysis_complete:
        try:
            return analysis_dumps(node.analysis)
        except Exception:
            # KaTrain itself saves the rest of the record when one analysis will
            # not pack; a position analysed again is a smaller loss than the game.
            return None
    return list(node.analysis_from_sgf) if node.analysis_from_sgf else None


def _root_properties(root, overrides: Dict[str, Any]) -> Dict[str, List[Any]]:
    merged = _properties(root)
    merged["CA"] = [CHARSET]
    for key, value in overrides.items():
        if value is None:
            merged.pop(key, None)
        else:
            merged[key] = [value]
    return merged


def _node_text(properties: Dict[str, Iterable[Any]]) -> str:
    return ";" + "".join(
        key + "".join(f"[{_escape(value)}]" for value in values)
        for key, values in properties.items()
        if values
    )


def _escape(value: Any) -> str:
    return re.sub(r"([\]\\])", r"\\\1", str(value))
