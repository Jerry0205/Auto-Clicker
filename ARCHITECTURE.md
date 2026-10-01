# Architektur

Klickmeister ist ein einzelner Prozess mit zwei Ausführungskontexten:

1. Der Qt-Thread besitzt das Kirigami-Fenster und alle GUI-Objekte.
2. Ein Rust-Worker besitzt die Portal-Sitzungen, den Zustandsautomaten und den Scheduler.

Zwischen beiden Richtungen laufen begrenzte Nachrichtenkanäle beziehungsweise in den Qt-Event-Loop eingereihte Zustandsupdates. Stop und Shutdown umgehen den begrenzten Befehlskanal über ein Ein-Wert-Signal, das der Worker vor allen anderen Ereignissen prüft; sie kommen deshalb auch bei vollem Kanal an. Startbefehle, die vor einem Stop eingereiht wurden, verwirft der Worker danach. Ein fehlgeschlagener Versand ändert den angezeigten Laufstatus nur, wenn der Worker beendet ist. Alle Startquellen gehen durch denselben Zustandsautomaten; deshalb kann höchstens ein Scheduler aktiv sein.

Jeder Startbefehl liefert die aktuellen, validierten Einstellungen. Eine ausstehende Portal-Aufgabe besitzt diese Einstellungen bis zur Freigabe; weitere Startbefehle können sie nicht überschreiben. Der Worker hält keinen Einstellungs-Cache für spätere Starts.

## Wayland-Backend

- `org.freedesktop.portal.RemoteDesktop`: Fordert ausschließlich `POINTER` an und sendet Linux-evdev-Buttoncodes. Der Modus „aktuelle Cursorposition“ bewegt oder liest den Cursor nicht.
- `org.freedesktop.portal.ScreenCast`: Wird nur für eine feste Position mit genau einem Monitor und verborgenem Cursor kombiniert. Es wird kein PipeWire-Remote geöffnet und kein Bildframe gelesen. Der Stream dient ausschließlich als Koordinatenreferenz für `NotifyPointerMotionAbsolute`.
- `org.freedesktop.portal.GlobalShortcuts`: Bindet eine Toggle-Aktion mit Pause als bevorzugtem Trigger. KWin entscheidet über die tatsächliche Belegung und zeigt seinen eigenen Berechtigungsdialog.

RemoteDesktop und GlobalShortcuts verwenden `ashpd` und jeweils eine eigene D-Bus-Verbindung. Ein Abbruch signalisiert der Startaufgabe die Bereinigung und wartet auf sie: vorhandene Sitzungen werden geschlossen, anschließend wird die Verbindung getrennt (jeweils höchstens eine Sekunde Wartezeit). Das räumt auch Anfragen auf, deren Sitzungshandle noch nicht angekommen ist; verspätet erfolgreiche Starts werden geschlossen und nicht ausgeführt. Der Positionswähler fragt keine Bildschirmaufnahme an, weil das Screenshot-Portal den Ausschnitt einer Aufnahme nicht mitliefert. Es gibt kein X11-Backend, kein `xdotool` und kein `/dev/uinput`.

## Scheduler

`tokio::time::Instant` ist monoton. Der nächste Termin wird vom vorherigen Solltermin abgeleitet. Falls ein Portalaufruf länger als das Intervall dauert, werden verpasste Termine verworfen statt als Burst nachgeholt. Das Mindestintervall beträgt 10 ms (100 Klickzyklen/s). Es gibt keine Busy-Wait-Schleife.

## Lebensdauer

Das Schließen des Fensters fordert über das priorisierte Signal das Ende des Workers an und wartet höchstens 5 Sekunden, bis sein Thread endet. Der Worker verlässt seine Schleife und klickt danach nicht mehr; ein bereits laufender Klick wird noch abgeschlossen. Anschließend bricht er ausstehende Anfragen ab und schließt RemoteDesktop- und GlobalShortcuts-Sitzungen selbst mit begrenzter Wartezeit. Endet er nicht innerhalb der 5 Sekunden, arbeitet der Qt-Thread ohne ihn weiter, und der Worker räumt im Hintergrund zu Ende auf. Seine späten Ereignisse verwirft der Controller über die Worker-Epoche. Das gilt auch, wenn nach einem Speicherfehler „Weiter bearbeiten“ einen neuen Worker startet, während der alte noch aufräumt. Schließt sich das Fenster, beendet das Prozessende auch diesen Thread. Es werden keine Kindprozesse gestartet. Ein Prozessabbruch trennt die D-Bus-Verbindung, wodurch der Portal-Backendbesitzer die Sitzungen ebenfalls verwirft.

## Positionsauswahl

Der Picker blendet das Hauptfenster vorübergehend aus und stellt dessen Fensterzustand anschließend wieder her. Während der Auswahl sind Starts auch über den globalen Hotkey gesperrt. Koordinaten und Monitorgeometrie verwenden logische Desktop-Einheiten. Portal-Position und -Größe müssen vor der Sitzungsnutzung mit der Auswahl übereinstimmen; fehlende Metadaten führen zum Abbruch. Bei geänderter Monitorgeometrie wird die Sitzung nicht wiederverwendet.
