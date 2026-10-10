"""Writing a game record: a KaTrain tree back to SGF text.

The mirror of `review`, and pure in the same way: a tree goes in, text comes out.
The bridge never writes a file. The app asks for the text and writes it where the
player chose in the save panel — a grant the sandbox gives the window, not the
child process.

KaTrain's own `Game.write_sgf` is not used: it opens the file itself, names the
players through its own translations, and stamps the root with a comment and an
invisible marker meant for KaTrain alone. Only the properties the record actually
carries are written here: moves, setup stones, comments, and the game information.
"""

import re
from typing import Any, Dict, Iterable, List, Optional

#: The text is handed to the app as a Python string and written out as UTF-8,
#: whatever charset the record declared when it was read.
CHARSET = "UTF-8"


def text(root, line: Optional[List[Any]] = None, properties: Optional[Dict[str, Any]] = None) -> str:
    """The record as SGF text.

    `line`, when given, is a path from the root: only those nodes are written, which
    is how a game against the AI leaves out the moves taken back. Without it the
    whole tree goes out, branches included.

    `properties` are laid over the root's own. A value of None removes the property.
    """
    root_properties = _root_properties(root, properties or {})
    on_line = None if line is None else {id(node) for node in line}

    def children(node) -> List[Any]:
        kept = node.ordered_children
        if on_line is not None:
            kept = [child for child in kept if id(child) in on_line]
        return kept

    # Iterative, like pysgf's own writer: a long game is a deep tree.
    out: List[str] = []
    stack: List[Any] = [")", root, "("]
    while stack:
        item = stack.pop()
        if isinstance(item, str):
            out.append(item)
            continue
        out.append(_node_text(root_properties if item is root else _properties(item)))
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
