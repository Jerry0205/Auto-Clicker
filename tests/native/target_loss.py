"""Intentional target crash while the clicker is idle; run.py must fail closed."""

import json
import os
import signal
import time

from control import BASE, mark

pids = json.loads((BASE / "pids.json").read_text())
os.kill(pids["app"], 0)
mark("inject_native_target_loss", app_pid=pids["app"], target_pid=pids["target"])
os.kill(pids["target"], signal.SIGKILL)
# Reaching this deadline means supervision failed. No clicks are started here.
time.sleep(10)
raise RuntimeError("Target loss was not caught by the supervisor")
