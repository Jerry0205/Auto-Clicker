"""Run a native scenario with an owned click target and fail-closed supervision."""

import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from guard import supervise, terminate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--binary", type=Path, default=Path("target/release/klickmeister")
    )
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("scenario", type=Path)
    parser.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    base = Path(tempfile.mkdtemp(prefix="klickmeister-native-"))
    os.environ["KLICKMEISTER_NATIVE_DIR"] = str(base)
    os.environ["XDG_CONFIG_HOME"] = str(base / "config")
    os.environ["QT_QPA_PLATFORM"] = "wayland"
    os.environ["QT_LINUX_ACCESSIBILITY_ALWAYS_ON"] = "1"
    print(f"Native artifacts: {base}", flush=True)
    from control import rpc, wait_for

    processes = {}
    logs = []

    def start(name, command):
        log = (base / f"{name}.log").open("w")
        logs.append(log)
        processes[name] = subprocess.Popen(
            command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True
        )
        return processes[name]

    def stopped(signum, frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, stopped)
    try:
        target = start(
            "target", [sys.executable, str(Path(__file__).with_name("target.py"))]
        )
        wait_for(lambda: (base / "target.sock").exists())
        state = rpc("target", cmd="state")
        assert state["visible"], "Target is not mapped"
        screen = state["screen"]
        identity = [
            screen["name"],
            screen["manufacturer"],
            screen["model"],
            screen["serial"],
            screen["width"],
            screen["height"],
            round(screen["scale"]),
        ]
        config = base / "config/klickmeister/config.toml"
        config.parent.mkdir(parents=True)
        config.write_text(
            'interval_ms = 100\nmouse_button = "left"\nclick_type = "single"\n'
            'repeat_mode = "count"\nrepeat_count = 3\nposition_mode = "fixed"\n'
            'fixed_x = 80\nfixed_y = 400\nhotkey = "Pause"\nmonitor_identity = '
            + json.dumps(
                json.dumps(identity, ensure_ascii=False, separators=(",", ":")),
                ensure_ascii=False,
            )
            + "\n"
        )
        start("driver", [sys.executable, str(Path(__file__).with_name("driver.py"))])
        app = start("app", [str(args.binary.resolve())])
        (base / "pids.json").write_text(
            json.dumps({name: p.pid for name, p in processes.items()})
        )
        scenario = start(
            "scenario", [sys.executable, str(args.scenario.resolve()), *args.args]
        )
        last_check = 0

        def check_target():
            nonlocal last_check
            if processes["driver"].poll() is not None:
                raise RuntimeError("Input driver exited")
            if time.monotonic() - last_check >= 0.25:
                assert rpc("target", cmd="state", timeout=0.1)["visible"], (
                    "Click target disappeared"
                )
                last_check = time.monotonic()

        return supervise(app, target, scenario, args.timeout, check_target)
    finally:
        # Never close the sink while either the app or scenario can send input.
        for name in ("scenario", "app", "driver", "target"):
            if name in processes:
                terminate(processes[name])
        for log in logs:
            log.close()
        path = base / "scenario.log"
        if path.exists():
            print(path.read_text(), end="")


if __name__ == "__main__":
    sys.exit(main())
