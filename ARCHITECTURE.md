# Architektur

Klickmeister ist ein einzelner Prozess mit zwei Ausführungskontexten:

1. Der Qt-Thread besitzt das Kirigami-Fenster und alle GUI-Objekte.
2. Ein Rust-Worker besitzt die Portal-Sitzungen, den Zustandsautomaten und den Scheduler.

Zwischen beiden Richtungen laufen begrenzte Nachrichtenkanäle beziehungsweise in den Qt-Event-Loop eingereihte Zustandsupdates. Alle Startquellen gehen durch denselben Zustandsautomaten; deshalb kann höchstens ein Scheduler aktiv sein.

## Wayland-Backend

- `org.freedesktop.portal.RemoteDesktop`: Fordert ausschließlich `POINTER` an und sendet Linux-evdev-Buttoncodes. Der Modus „aktuelle Cursorposition“ bewegt oder liest den Cursor nicht.
- `org.freedesktop.portal.ScreenCast`: Wird nur für eine feste Position mit genau einem Monitor und verborgenem Cursor kombiniert. Es wird kein PipeWire-Remote geöffnet und kein Bildframe gelesen. Der Stream dient ausschließlich als Koordinatenreferenz für `NotifyPointerMotionAbsolute`.
- `org.freedesktop.portal.Screenshot`: Optional für die 4×-Lupe. Lädt ein Standbild des virtuellen Desktops; die Auswahl und Lupe verwenden dieselbe Aufnahme. Ohne Aufnahme bleibt der transparente Picker nutzbar.
- `org.freedesktop.portal.GlobalShortcuts`: Bindet eine Toggle-Aktion mit Pause als bevorzugtem Trigger. KWin entscheidet über die tatsächliche Belegung und zeigt seinen eigenen Berechtigungsdialog.

RemoteDesktop und GlobalShortcuts verwenden `ashpd` und jeweils eine eigene D-Bus-Verbindung. Ein Abbruch signalisiert der Startaufgabe die Bereinigung und wartet auf sie: vorhandene Sitzungen werden geschlossen, anschließend wird die Verbindung getrennt (jeweils höchstens eine Sekunde Wartezeit). Das räumt auch Anfragen auf, deren Sitzungshandle noch nicht angekommen ist; verspätet erfolgreiche Starts werden geschlossen und nicht ausgeführt. Screenshot nutzt dessen `zbus`-Reexport mit typisierten Antworten und einem vorab bekannten Request-Pfad: ashpd 0.13 gibt den Request erst nach der Antwort zurück und erlaubt damit kein rechtzeitiges `Request.Close` bei Abbruch. Die Screenshot-Verbindung ist separat; Abbruch, Ersetzen und Shutdown versuchen die Anfrage zu schließen und trennen anschließend die Verbindung mit begrenzter Wartezeit. Ein blockierter Portal-Dienst kann die sichtbare Dialogbereinigung trotzdem verhindern; dies wurde für die Screenshot-Erstfreigabe unter xdg-desktop-portal 1.22.1 nativ reproduziert (siehe tests/DEVICE_TEST_REPORT.md). Es gibt kein X11-Backend, kein `xdotool` und kein `/dev/uinput`.

## Scheduler

`tokio::time::Instant` ist monoton. Der nächste Termin wird vom vorherigen Solltermin abgeleitet. Falls ein Portalaufruf länger als das Intervall dauert, werden verpasste Termine verworfen statt als Burst nachgeholt. Das Mindestintervall beträgt 10 ms (100 Klickzyklen/s). Es gibt keine Busy-Wait-Schleife.

## Lebensdauer

Das Schließen des Fensters sendet `Shutdown`, wartet auf den Worker und schließt RemoteDesktop- und GlobalShortcuts-Sitzungen mit begrenzter Wartezeit. Es werden keine Kindprozesse gestartet. Ein Prozessabbruch trennt die D-Bus-Verbindung, wodurch der Portal-Backendbesitzer die Sitzungen ebenfalls verwirft.

## Positionsauswahl

Der Picker blendet das Hauptfenster vorübergehend aus und stellt dessen Fensterzustand anschließend wieder her. Während der Auswahl sind Starts auch über den globalen Hotkey gesperrt. Koordinaten und Monitorgeometrie verwenden logische Desktop-Einheiten. Portal-Position und -Größe müssen vor der Sitzungsnutzung mit der Auswahl übereinstimmen; fehlende Metadaten führen zum Abbruch. Bei geänderter Monitorgeometrie wird die Sitzung nicht wiederverwendet.
