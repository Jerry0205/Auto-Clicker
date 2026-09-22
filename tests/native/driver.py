import json
import os
import signal
import socket
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
base = os.environ["KLICKMEISTER_NATIVE_DIR"]
bus = dbus.SessionBus(private=True)
portal = bus.get_object(
    "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop"
)
remote = dbus.Interface(portal, "org.freedesktop.portal.RemoteDesktop")
screen = dbus.Interface(portal, "org.freedesktop.portal.ScreenCast")
loop = GLib.MainLoop()
state = {"ready": False, "session": None, "streams": []}
pending = {}


def empty():
    return dbus.Dictionary({}, signature="sv")


def output(row):
    print(json.dumps(row), flush=True)


def on_response(code, result, path=None):
    callback = pending.pop(str(path), None)
    if callback:
        callback(int(code), result)


bus.add_signal_receiver(
    on_response,
    signal_name="Response",
    dbus_interface="org.freedesktop.portal.Request",
    path_keyword="path",
)


def request(method, args, options, callback):
    token = "native_test_" + str(time.monotonic_ns())
    options["handle_token"] = dbus.String(token)
    path = (
        "/org/freedesktop/portal/desktop/request/"
        + bus.get_unique_name()[1:].replace(".", "_")
        + "/"
        + token
    )
    pending[path] = callback
    method(
        *args,
        dbus.Dictionary(options, signature="sv"),
        reply_handler=lambda h: None,
        error_handler=lambda e: output({"error": str(e)}),
        timeout=120,
    )


def started(code, result):
    if code:
        output({"error": "Start rejected", "code": code})
        return
    state["streams"] = [
        {
            "id": int(s[0]),
            "position": list(s[1].get("position", [])),
            "size": list(s[1].get("size", [])),
        }
        for s in result.get("streams", [])
    ]
    state["ready"] = True
    state["devices"] = int(result["devices"])
    output(state)


def sources(code, result):
    if code:
        output({"error": "Sources rejected", "code": code})
        return
    output({"stage": "waiting for visible KDE permission dialog"})
    request(remote.Start, [dbus.ObjectPath(state["session"]), ""], {}, started)


def devices(code, result):
    if code:
        output({"error": "Devices rejected", "code": code})
        return
    request(
        screen.SelectSources,
        [dbus.ObjectPath(state["session"])],
        {"types": dbus.UInt32(1), "multiple": False, "cursor_mode": dbus.UInt32(1)},
        sources,
    )


def created(code, result):
    if code:
        output({"error": "Create rejected", "code": code})
        return
    state["session"] = str(result["session_handle"])
    request(
        remote.SelectDevices,
        [dbus.ObjectPath(state["session"])],
        {"types": dbus.UInt32(3), "persist_mode": dbus.UInt32(0)},
        devices,
    )


def close(*args):
    if state["session"]:
        try:
            dbus.Interface(
                bus.get_object("org.freedesktop.portal.Desktop", state["session"]),
                "org.freedesktop.portal.Session",
            ).Close(timeout=2)
        except Exception:
            pass
    loop.quit()
    return False


server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(base + "/driver.sock")
server.listen(5)


def client_ready(source, condition):
    c, _ = server.accept()
    c.settimeout(3)
    try:
        data = b""
        while b"\n" not in data:
            chunk = c.recv(4096)
            if not chunk:
                raise ConnectionError("Driver client disconnected before request")
            data += chunk
        req = json.loads(data)
        cmd = req["cmd"]
        result = {}
        if cmd == "state":
            result = state
        elif cmd == "close":
            GLib.idle_add(close)
        elif not state["ready"]:
            raise RuntimeError("Driver permission missing")
        elif cmd == "key":
            for pressed in [1, 0]:
                remote.NotifyKeyboardKeysym(
                    dbus.ObjectPath(state["session"]),
                    empty(),
                    dbus.Int32(req["keysym"]),
                    dbus.UInt32(pressed),
                    timeout=3,
                )
        elif cmd == "key_state":
            remote.NotifyKeyboardKeysym(
                dbus.ObjectPath(state["session"]),
                empty(),
                dbus.Int32(req["keysym"]),
                dbus.UInt32(req["state"]),
                timeout=3,
            )
        elif cmd == "move":
            remote.NotifyPointerMotionAbsolute(
                dbus.ObjectPath(state["session"]),
                empty(),
                dbus.UInt32(state["streams"][0]["id"]),
                dbus.Double(req["x"]),
                dbus.Double(req["y"]),
                timeout=3,
            )
        elif cmd == "click":
            for pressed in [1, 0]:
                remote.NotifyPointerButton(
                    dbus.ObjectPath(state["session"]),
                    empty(),
                    dbus.Int32(req.get("button", 272)),
                    dbus.UInt32(pressed),
                    timeout=3,
                )
        else:
            raise RuntimeError("Unknown command")
        c.sendall((json.dumps({"ok": True, "value": result}) + "\n").encode())
    except Exception as e:
        output({"error": str(e)})
        c.sendall((json.dumps({"ok": False, "error": str(e)}) + "\n").encode())
    finally:
        c.close()
    return True


GLib.io_add_watch(server.fileno(), GLib.IO_IN, client_ready)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, close)
GLib.timeout_add_seconds(3600, close)
request(
    remote.CreateSession,
    [],
    {"session_handle_token": dbus.String("native_test_" + str(time.monotonic_ns()))},
    created,
)
try:
    loop.run()
finally:
    server.close()
    bus.close()
    if os.path.exists(base + "/driver.sock"):
        os.unlink(base + "/driver.sock")
