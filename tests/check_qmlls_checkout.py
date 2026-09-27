"""Build a separate checkout and verify qmlls sees the generated controller type."""

import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
QMLLS = os.environ.get("QMLLS", "/usr/lib/qt6/bin/qmlls")


def run(*command, cwd=None, env=None):
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(
            f"{' '.join(map(str, command))} failed:\n{result.stdout}{result.stderr}"
        )
    return result.stdout


class LanguageServer:
    def __init__(self, checkout):
        self.process = subprocess.Popen(
            [QMLLS],
            cwd=checkout,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.buffer = b""

    def send(self, message):
        payload = json.dumps(message).encode("utf-8")
        self.process.stdin.write(
            f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii") + payload
        )
        self.process.stdin.flush()

    def receive(self, deadline):
        while time.monotonic() < deadline:
            if b"\r\n\r\n" in self.buffer:
                header, remaining = self.buffer.split(b"\r\n\r\n", 1)
                length = next(
                    int(line.split(b":", 1)[1])
                    for line in header.split(b"\r\n")
                    if line.lower().startswith(b"content-length:")
                )
                if len(remaining) >= length:
                    self.buffer = remaining[length:]
                    return json.loads(remaining[:length])
            readable, _, _ = select.select(
                [self.process.stdout], [], [], max(0, deadline - time.monotonic())
            )
            if readable:
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    break
                self.buffer += data
        raise TimeoutError("qmlls did not respond in time")

    def response(self, request_id):
        deadline = time.monotonic() + 30
        while True:
            message = self.receive(deadline)
            if message.get("id") == request_id:
                if "error" in message:
                    raise RuntimeError(f"qmlls request failed: {message['error']}")
                return message["result"]

    def close(self):
        self.process.terminate()
        try:
            self.process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.communicate()


def check_completion(checkout):
    source = checkout / "qml/Main.qml"
    lines = source.read_text().splitlines()
    line_index = next(
        index for index, line in enumerate(lines) if "controller.fixed_x, controller.fixed_y" in line
    )
    column = lines[line_index].index("controller.fixed_x") + len("controller.")
    server = LanguageServer(checkout)
    try:
        server.send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": os.getpid(),
                    "rootUri": checkout.as_uri(),
                    "workspaceFolders": [{"uri": checkout.as_uri(), "name": checkout.name}],
                    "capabilities": {},
                },
            }
        )
        server.response(1)
        server.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        server.send(
            {
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": source.as_uri(),
                        "languageId": "qml",
                        "version": 1,
                        "text": source.read_text(),
                    }
                },
            }
        )
        server.send(
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "textDocument/completion",
                "params": {
                    "textDocument": {"uri": source.as_uri()},
                    "position": {"line": line_index, "character": column},
                },
            }
        )
        completion = server.response(2)
        items = completion if isinstance(completion, list) else completion["items"]
        labels = {item["label"] for item in items}
        expected = {"fixed_x", "fixed_y", "running", "start"}
        missing = expected - labels
        if missing:
            raise AssertionError(f"qmlls cannot resolve AppController: missing {sorted(missing)}")
    finally:
        server.close()


def main():
    with tempfile.TemporaryDirectory(prefix="klickmeister qmlls ") as directory:
        checkout = Path(directory) / "another checkout"
        run("git", "clone", "--quiet", "--local", "--no-hardlinks", str(ROOT), str(checkout))
        if (checkout / ".qmlls.ini").exists():
            raise AssertionError("A personal .qmlls.ini was copied into the clone")
        target_dir = checkout / "cargo output"
        build_env = os.environ.copy()
        build_env["CARGO_TARGET_DIR"] = str(target_dir)
        run("cargo", "build", "--locked", cwd=checkout, env=build_env)
        run("bash", "scripts/setup-qmlls.sh", cwd=checkout, env=build_env)
        configuration = (checkout / ".qmlls.ini").read_text()
        expected_dir = target_dir / "cxxqt/qml_modules"
        if f'buildDir="{expected_dir}"' not in configuration:
            raise AssertionError(f"Wrong qmlls build directory:\n{configuration}")
        check_completion(checkout)
        print("Fresh checkout: qmlls resolves AppController and its properties.")


if __name__ == "__main__":
    main()
