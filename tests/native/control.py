import json
import os
import socket
import time
from pathlib import Path

BASE = Path(os.environ["KLICKMEISTER_NATIVE_DIR"])


def rpc(which, *, timeout=5, **request):
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(timeout)
        sock.connect(str(BASE / (which + ".sock")))
        sock.sendall((json.dumps(request) + "\n").encode())
        data = b""
        while b"\n" not in data:
            chunk = sock.recv(65536)
            if not chunk:
                raise RuntimeError("Socket closed without reply")
            data += chunk
    result = json.loads(data)
    if which == "driver":
        if not result["ok"]:
            raise RuntimeError(result["error"])
        return result["value"]
    return result


def events():
    path = BASE / "mouse-events.jsonl"
    return (
        [json.loads(line) for line in path.read_text().splitlines()]
        if path.exists()
        else []
    )


def mark(name, **fields):
    row = {"test": name, "t_ns": time.monotonic_ns(), **fields}
    with (BASE / "results.jsonl").open("a") as f:
        f.write(json.dumps(row) + "\n")
    print(json.dumps(row), flush=True)


def wait_for(predicate, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.05)
    raise TimeoutError("Expected condition not observed")
