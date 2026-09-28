import json
import subprocess
import sys
import time
from pathlib import Path

import tomllib
from access import Atspi, action, find, nodes
from control import BASE, events, mark, rpc, wait_for
from gi.repository import GLib


def pump():
    context = GLib.MainContext.default()
    while context.pending():
        context.iteration(False)


def status():
    pump()
    return next(
        (n.get_name() for n, d in nodes() if n.get_name().startswith("Status:")), ""
    )


def kwin(op):
    result = subprocess.run(
        [sys.executable, str(Path(__file__).with_name("kwin.py")), op],
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


def focus_app():
    kwin("focus_app")
    time.sleep(0.15)


def focus_target():
    kwin("focus_target")
    time.sleep(0.15)
    assert rpc("target", cmd="state")["active"]


def key(k):
    rpc("driver", cmd="key", keysym=k)


def type_value(name, value):
    focus_app()
    n = find(name, role="text")
    assert Atspi.Component.grab_focus(n)
    time.sleep(0.1)
    rpc("driver", cmd="key_state", keysym=0xFFE3, state=1)
    try:
        key(ord("a"))
    finally:
        rpc("driver", cmd="key_state", keysym=0xFFE3, state=0)
    for ch in str(value):
        key(ord(ch))
    pump()
    actual = Atspi.Text.get_text(n, 0, -1)
    assert actual.replace(".", "").replace(",", "") == str(value), (name, actual, value)


CHOICES = {
    "Maustaste": ["Links", "Rechts", "Mitte"],
    "Klicktyp": ["Einfach", "Doppelt"],
}


def choose(name, index):
    """Press a visible segment button and verify that it became the checked option."""
    focus_app()
    label = CHOICES[name][index]
    action(label, role="radio button")
    pump()
    wait_for(
        lambda: find(label, role="radio button")
        .get_state_set()
        .contains(Atspi.StateType.CHECKED)
    )


def fixed_point():
    """Return the X/Y values currently shown in the main window."""
    return tuple(
        int(Atspi.Value.get_current_value(find(name, role="spin button")))
        for name in ("X-Koordinate auf dem Monitor", "Y-Koordinate auf dem Monitor")
    )


def mouse_events():
    return [e for e in events() if "button" in e]


def run_counted(
    name,
    button=1,
    double=False,
    count=3,
    interval=100,
    hotkey=True,
    allow_permission=False,
):
    assert fixed_point() == (80, 400), "Restore the test coordinates before starting"
    before = len(mouse_events())
    focus_target()
    if hotkey:
        key(0xFF13)
    else:
        action("Starten", role="button")
    if allow_permission:
        wait_for(
            lambda: any(
                n.get_name() == "Akzeptieren"
                for n, d in nodes("xdg-desktop-portal-kde")
            )
        )
        action("Akzeptieren", app="xdg-desktop-portal-kde", role="button")
    expected = 2 * count * (2 if double else 1)
    wait_for(
        lambda: len(mouse_events()) >= before + expected,
        timeout=max(5, count * interval / 1000 + 3),
    )
    wait_for(lambda: "Gestoppt" in status())
    time.sleep(0.2)
    new = mouse_events()[before:]
    assert len(new) == expected, (name, len(new), expected, status())
    assert [e["type"] == "MouseButtonRelease" for e in new] == [False, True] * (
        expected // 2
    ), new
    assert all(e["button"] == button and e["x"] == 80 and e["y"] == 400 for e in new), (
        new
    )
    assert all(e["buttons"] == 0 for e in new if e["type"] == "MouseButtonRelease")
    saved = tomllib.loads((BASE / "config/klickmeister/config.toml").read_text())
    assert saved["repeat_count"] == count and saved["interval_ms"] == interval, saved
    assert saved["mouse_button"] == {1: "left", 2: "right", 4: "middle"}[button], saved
    assert saved["click_type"] == ("double" if double else "single"), saved
    mark(
        name,
        passed=True,
        button=button,
        cycles=count,
        mouse_events=len(new),
        interval_ms=interval,
        start="global hotkey" if hotkey else "UI button",
        event_begin=before,
        event_end=before + len(new),
    )
    return new
