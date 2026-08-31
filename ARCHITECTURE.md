# Architektur

Klickmeister ist ein einzelner Prozess mit zwei Ausführungskontexten:

1. Der Qt-Thread besitzt das Kirigami-Fenster und alle GUI-Objekte.
2. Ein Rust-Worker besitzt die Portal-Sitzungen, den Zustandsautomaten und den Scheduler.

Zwischen beiden Richtungen laufen begrenzte Nachrichtenkanäle beziehungsweise in den Qt-Event-Loop eingereihte Zustandsupdates. Alle Startquellen gehen durch denselben Zustandsautomaten; deshalb kann höchstens ein Scheduler aktiv sein.

## Wayland-Backend

- `org.freedesktop.portal.RemoteDesktop`: Fordert ausschließlich `POINTER` an und sendet Linux-evdev-Buttoncodes. Der Modus „aktuelle Cursorposition“ bewegt oder liest den Cursor nicht.
- `org.freedesktop.portal.ScreenCast`: Wird nur für eine feste Position mit genau einem Monitor und verborgenem Cursor kombiniert. Es wird kein PipeWire-Remote geöffnet und kein Bildframe gelesen. Der Stream dient ausschließlich als Koordinatenreferenz für `NotifyPointerMotionAbsolute`.
- `org.freedesktop.portal.GlobalShortcuts`: Bindet eine Toggle-Aktion mit Pause als bevorzugtem Trigger. KWin entscheidet über die tatsächliche Belegung und zeigt seinen eigenen Berechtigungsdialog.

Die D-Bus-Aufrufe sind über `ashpd` typisiert. Es gibt kein X11-Backend, kein `xdotool` und kein `/dev/uinput`.

## Scheduler

`tokio::time::Instant` ist monoton. Der nächste Termin wird vom vorherigen Solltermin abgeleitet. Falls ein Portalaufruf länger als das Intervall dauert, werden verpasste Termine verworfen statt als Burst nachgeholt. Das Mindestintervall beträgt 10 ms (100 CPS). Es gibt keine Busy-Wait-Schleife.

## Lebensdauer

Das Schließen des Fensters sendet `Shutdown`, wartet auf den Worker und schließt RemoteDesktop- und GlobalShortcuts-Sitzungen mit begrenzter Wartezeit. Es werden keine Kindprozesse gestartet. Ein Prozessabbruch trennt die D-Bus-Verbindung, wodurch der Portal-Backendbesitzer die Sitzungen ebenfalls verwirft.
