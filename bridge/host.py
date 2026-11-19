"""Headless KaTrain host: everything the core needs that is not the go game.

The KaTrain core expects a single object carrying `.game`, `.players_info`,
`.config` and `.controls`, and it reaches into all four without checking whether a
UI is attached. That plumbing — inert controls, diagnostics routed away from the
protocol channel, the task queue, the engine's lifetime — has nothing to do with go
and lives here, so `session.py` can be read as the game and nothing else.
"""

import os
import queue
import sys
import threading
from typing import Optional

os.environ.setdefault("KIVY_NO_ARGS", "1")
os.environ.setdefault("KIVY_NO_CONSOLELOG", "1")

from enginepaths import bundle_engine_overrides
from katrain.core.base_katrain import KaTrainBase
from katrain.core.constants import OUTPUT_ERROR
from katrain.core.engine import KataGoEngine

from protocol import CommandError


class _Inert:
    """Swallows any attribute access, call or assignment.

    The core reaches into `katrain.controls` on the teaching and editing paths
    without checking whether a UI is attached. Returning something inert keeps
    those paths from raising in a headless process.
    """

    __slots__ = ()

    def __call__(self, *args, **kwargs):
        return None

    def __getattr__(self, name):
        return _INERT

    def __setattr__(self, name, value):
        pass

    def __bool__(self):
        return False


_INERT = _Inert()


class NullControls:
    """Stands in for the Kivy controls object, logging what the core reaches for.

    Each attribute name is reported once on stderr. An unexpected name showing up
    means the core took a path we have not accounted for, which is worth knowing
    even though nothing breaks.
    """

    def __init__(self, log):
        object.__setattr__(self, "_log", log)
        object.__setattr__(self, "_seen", set())

    def __getattr__(self, name):
        seen = object.__getattribute__(self, "_seen")
        if name not in seen:
            seen.add(name)
            object.__getattribute__(self, "_log")(f"core reached for controls.{name}")
        return _INERT

    def __setattr__(self, name, value):
        pass


def _command_id(args) -> Optional[int]:
    """The id of the command a task runs for, if it runs for one.

    Every command method takes its command id first, so an error can be attributed
    to the command that caused it. Tasks the core queues on its own — an analysis
    coming back — start with a node instead, and belong to no command.
    """
    first = args[0] if args else None
    return first if isinstance(first, int) and not isinstance(first, bool) else None


class KaTrainHost(KaTrainBase):
    """The process side of a KaTrain session: worker thread, engine, diagnostics.

    Everything that touches the KaTrain core happens on a single worker thread. The
    core notifies progress by calling `update_state()` from KataGo's reader thread; if
    we generated the AI move right there, that thread would block waiting for the very
    analyses it is supposed to be reading. KaTrain solves this with a message loop, and
    so do we: `update_state()` only enqueues, the worker does the work.
    """

    def __init__(self, writer):
        self._writer = writer
        self._tasks: "queue.Queue" = queue.Queue()
        self._engine: Optional[KataGoEngine] = None
        self._stopping = False
        super().__init__()
        self._apply_bundle_paths()
        self.controls = NullControls(self._log_stderr)

    def _apply_bundle_paths(self) -> None:
        """Laisse le bundle imposer ses chemins moteur, s'il y en a un.

        Dans l'application distribuée, le sandbox interdit ~/.katrain : binaire,
        modèles et configuration vivent dans le bundle. Hors bundle, aucune
        variable n'est posée et la configuration de l'utilisateur reste intacte.
        """
        overrides = bundle_engine_overrides(os.environ)
        if overrides:
            self._config.setdefault("engine", {}).update(overrides)

    # -- logging -------------------------------------------------------------
    # The base class prints to stdout, which is the protocol channel. Everything
    # diagnostic goes to stderr instead.

    def _log_stderr(self, message: str) -> None:
        sys.stderr.write(f"{message}\n")
        sys.stderr.flush()

    def log(self, message, level=1):
        if level == OUTPUT_ERROR or self.debug_level >= level:
            self._log_stderr(str(message))

    # -- worker loop ---------------------------------------------------------

    def start(self) -> None:
        self._worker = threading.Thread(target=self._run, daemon=True, name="bridge-worker")
        self._worker.start()

    def submit(self, fn, *args) -> None:
        self._tasks.put((fn, args))

    def _run(self) -> None:
        while True:
            fn, args = self._tasks.get()
            if fn is None:
                return
            self.run_task(fn, *args)

    def run_task(self, fn, *args) -> None:
        """Runs one command and turns anything it raises into an error event.

        Kept apart from the loop so the policy — which failures reach the app, and
        under which id — can be exercised without starting a thread.
        """
        try:
            fn(*args)
        except CommandError as exc:
            self._writer.emit("error", _command_id(args), code=exc.code, message=exc.message)
        except Exception as exc:  # keep the bridge alive; the app sees the error
            self._writer.emit("error", _command_id(args), code="internal", message=f"{type(exc).__name__}: {exc}")
            self._log_stderr(f"worker error: {type(exc).__name__}: {exc}")

    def stop(self) -> None:
        self._stopping = True
        self._tasks.put((None, ()))
        if self._engine is not None:
            try:
                self._engine.shutdown(finish=False)
            except Exception:
                pass

    # -- engine --------------------------------------------------------------

    def start_engine(self) -> None:
        self._engine = KataGoEngine(self, self.config("engine"))
