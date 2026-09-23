"""Exercise the interactive screenshot deadline on a real Plasma session."""

import time

from access import Atspi, action, nodes
from control import mark, rpc, wait_for
from portal_cases import (
    close_picker,
    grant_remote,
    open_capture,
    picker_text,
    portal_button,
    screenshot_dialog,
)
from scenarios import kwin, status


def save_ready():
    buttons = [n for n, _ in nodes("xdg-desktop-portal-kde") if n.get_role_name() == "button"]
    return len(buttons) == 3 and all(
        n.get_state_set().contains(Atspi.StateType.ENABLED) for n in buttons
    )


def main():
    grant_remote()
    wait_for(lambda: rpc("driver", cmd="state")["ready"])
    kwin("place")
    wait_for(lambda: "Bereit" in status())
    action("Mit 4×-Lupe auswählen (Bildschirmaufnahme)", role="check box")

    for delay in (6, 12):
        open_capture()
        start = time.monotonic()
        time.sleep(delay)
        assert screenshot_dialog(), "Screenshot dialog closed before the user could save"
        assert any(
            n.get_role_name() == "text" and Atspi.Text.get_text(n, 0, -1) == "Vollbild"
            for n, _ in nodes("xdg-desktop-portal-kde")
        )
        portal_button("Bildschirmfoto anfordern", "Übernehmen", 2, 3)
        wait_for(save_ready)
        portal_button("Bildschirmfoto anfordern", "Speichern", 0, 3)
        wait_for(lambda: "Lupe 4×" in picker_text(), timeout=5)
        mark("interactive_magnifier", passed=True, delay_s=delay,
             elapsed_s=round(time.monotonic() - start, 2))
        close_picker()

    open_capture()
    portal_button("Bildschirmfoto anfordern", "Abbrechen", 1, 3)
    wait_for(lambda: "nicht verfügbar" in picker_text())
    assert "Lupe 4×" not in picker_text()
    mark("interactive_cancel_fallback", passed=True)
    close_picker()

    open_capture()
    start = time.monotonic()
    wait_for(lambda: "zu lange" in picker_text(), timeout=23)
    wait_for(lambda: not screenshot_dialog())
    elapsed = time.monotonic() - start
    assert 19 <= elapsed <= 23, elapsed
    mark("interactive_timeout_fallback", passed=True,
         elapsed_s=round(elapsed, 2))
    close_picker()


if __name__ == "__main__":
    main()
