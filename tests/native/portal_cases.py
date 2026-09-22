"""Native KDE 6.7 screenshot regression, using real dialogs and portal input."""

import json
import subprocess
import time
from pathlib import Path

from access import Atspi, action, nodes, walk
from control import BASE, mark, rpc, wait_for
from scenarios import (
    combo,
    focus_app,
    focus_target,
    key,
    kwin,
    mouse_events,
    run_counted,
    status,
)

PORTAL_APP = "xdg-desktop-portal-kde"


def frame(title):
    return any(
        n.get_role_name() == "frame" and n.get_name() == title
        for n, _ in nodes(PORTAL_APP)
    )


def portal_button(title, name, position, count):
    """German KDE 6.7 fallback for buttons whose AT-SPI names are empty.

    The visible labels/order are verified in this version's dialog and native
    screenshot evidence. Fail on a changed layout; never guess another dialog.
    """
    frames = [n for n, _ in nodes(PORTAL_APP) if n.get_role_name() == "frame"]
    assert len(frames) == 1 and frames[0].get_name() == title
    buttons = [
        n
        for n, _ in walk(frames[0])
        if n.get_role_name() == "button"
        and n.get_state_set().contains(Atspi.StateType.SHOWING)
    ]
    named = [n for n in buttons if n.get_name() == name]
    if len(named) == 1:
        button = named[0]
    else:
        assert len(buttons) == count and all(not n.get_name() for n in buttons)
        buttons.sort(
            key=lambda n: Atspi.Component.get_extents(n, Atspi.CoordType.SCREEN).x
        )
        button = buttons[position]
    assert button.get_state_set().contains(Atspi.StateType.ENABLED)
    assert button.get_action_iface().do_action(0)


def grant_remote():
    wait_for(lambda: frame("Fernsteuerung"), timeout=10)
    kwin("focus_portal")
    portal_button("Fernsteuerung", "Akzeptieren", 0, 2)


def screenshot_dialog():
    return frame("Bildschirmfoto anfordern")


def open_capture():
    action("Position wählen / Neu wählen …", role="button")
    wait_for(screenshot_dialog)


def picker_text():
    return "\n".join(n.get_name() for n, _ in nodes() if n.get_role_name() == "label")


def probe_driver(name):
    started = time.monotonic()
    rpc("driver", cmd="move", x=80, y=400)
    mark(name, passed=True, independent_portal_ms=(time.monotonic() - started) * 1000)


def close_picker():
    kwin("focus_picker")
    key(0xFF1B)
    wait_for(lambda: not any("Esc / Rechtsklick" in n.get_name() for n, _ in nodes()))


def pin_target():
    # A fresh picker follows the pointer: explicitly pin and verify every time.
    kwin("focus_picker")
    rpc("driver", cmd="move", x=80, y=400)
    rpc("driver", cmd="click")
    wait_for(lambda: "X: 80 · Y: 400" in picker_text())
    key(0xFF0D)
    wait_for(lambda: any("X: 80 · Y: 400" in n.get_name() for n, _ in nodes()))


def main():
    grant_remote()
    wait_for(lambda: rpc("driver", cmd="state")["ready"])
    kwin("place")
    wait_for(lambda: "Bereit" in status())
    action("Mit 4×-Lupe auswählen (Bildschirmaufnahme)", role="check box")

    open_capture()
    probe_driver("independent_client_during_dialog")
    wait_for(lambda: "zu lange" in picker_text(), timeout=4)
    wait_for(lambda: not screenshot_dialog())
    assert "Deny" in picker_text()
    probe_driver("unanswered_dialog_closed_after_timeout")
    close_picker()
    time.sleep(0.3)
    assert "Esc / Rechtsklick" not in picker_text()

    open_capture()
    subprocess.run(
        ["spectacle", "-b", "-n", "-o", str(BASE / "screenshot-dialog.png")], check=True
    )
    portal_button("Bildschirmfoto anfordern", "Abbrechen", 1, 3)
    wait_for(lambda: "nicht verfügbar" in picker_text())
    assert "Lupe 4×" not in picker_text()
    probe_driver("denied_capture_falls_back")
    close_picker()

    open_capture()
    # KDE defaults to Full Screen. Verify this before accepting the image.
    assert any(
        n.get_role_name() == "text" and Atspi.Text.get_text(n, 0, -1) == "Vollbild"
        for n, _ in nodes(PORTAL_APP)
    )
    portal_button("Bildschirmfoto anfordern", "Übernehmen", 2, 3)

    def save_ready():
        buttons = [n for n, _ in nodes(PORTAL_APP) if n.get_role_name() == "button"]
        return len(buttons) == 3 and all(
            n.get_state_set().contains(Atspi.StateType.ENABLED) for n in buttons
        )

    wait_for(save_ready, timeout=2)
    portal_button("Bildschirmfoto anfordern", "Speichern", 0, 3)
    wait_for(lambda: "Lupe 4×" in picker_text(), timeout=3)
    rpc("driver", cmd="move", x=80, y=400)
    subprocess.run(
        ["spectacle", "-b", "-n", "-o", str(BASE / "magnifier.png")], check=True
    )
    mark("approved_real_screenshot_magnifier", passed=True)
    pin_target()

    # Exercise actual clicks and Stop after the screenshot failure paths.
    before = len(mouse_events())
    focus_target()
    action("▶  Starten", role="button")
    grant_remote()
    wait_for(lambda: "Gestoppt" in status())
    new = mouse_events()[before:]
    assert len(new) == 6, new
    assert all(e["x"] == 80 and e["y"] == 400 for e in new)
    assert [e["type"] == "MouseButtonRelease" for e in new] == [False, True] * 3
    mark("clicks_after_capture_failures", passed=True, mouse_events=len(new))
    action("Bis zum Stoppen", role="radio button")
    focus_target()
    action("▶  Starten", role="button")
    wait_for(lambda: "Klickt" in status())
    wait_for(lambda: len(mouse_events()) >= before + 10)
    action("■  Stoppen", role="button")
    wait_for(lambda: "Gestoppt" in status())
    count = len(mouse_events())
    time.sleep(0.3)
    assert len(mouse_events()) == count
    mark("stop_after_capture_failures", passed=True, quiet_ms=300)

    # Saved helpers exercise real visible menu choices and verify their values.
    action("Anzahl", role="radio button")
    for index, button in enumerate([1, 2, 4]):
        combo("Maustaste", index)
        for click_type in [0, 1]:
            combo("Klicktyp", click_type)
            run_counted(
                "native_click_matrix",
                button=button,
                double=bool(click_type),
                hotkey=False,
            )
    focus_target()
    rpc("driver", cmd="key_state", keysym=0xFFE9, state=1)
    try:
        key(0xFFC1)  # Alt+F4 must not remove the sink.
    finally:
        rpc("driver", cmd="key_state", keysym=0xFFE9, state=0)
    time.sleep(0.1)
    assert rpc("target", cmd="state")["visible"]
    mark("target_ignores_alt_f4", passed=True)

    focus_app()
    open_capture()
    started = time.monotonic()
    kwin("close_app")
    pid = json.loads((BASE / "pids.json").read_text())["app"]
    wait_for(lambda: not Path(f"/proc/{pid}").exists())
    wait_for(lambda: not screenshot_dialog())
    probe_driver("close_app_cleans_screenshot_dialog")
    mark(
        "shutdown_pending_capture",
        passed=True,
        elapsed_ms=(time.monotonic() - started) * 1000,
    )


if __name__ == "__main__":
    main()
