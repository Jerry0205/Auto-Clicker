# Testprotokoll vom 13.09.2026

Die erreichbare Gerätesitzung verwendet Ubuntu 26.04.1, XFCE und X11. Rust, Qt und KWin waren dort nicht installiert. Die Prüfung erfolgte deshalb auf demselben Gerät in einem separaten Ubuntu-26.04-Container mit Rust 1.93.1, Qt 6.10.2 und KWin 6.6.6. Der laufende Desktop wurde nicht umgestellt. Computersteuerung war nicht erforderlich.

## Ergebnisse

| Prüfung | Ergebnis |
| --- | --- |
| Rust-Unit-Tests | 24 bestanden |
| Screenshot-Abbruch über echten privaten D-Bus | Bestanden |
| Echter Rust-Worker gegen simulierte D-Bus-Portale | Bestanden |
| Laden des eingebetteten Hauptfensters im gebauten Programm | Bestanden |
| QML mit KDE-Stil, ohne Bildschirm | 33 bestanden |
| QML unter isoliertem KWin, drei virtuelle Monitore, 100 % | 33 bestanden |
| QML unter isoliertem KWin, drei virtuelle Monitore, 150 % | 33 bestanden |
| Clippy für alle Targets mit `-D warnings` | Bestanden |
| Rust-Formatierung, Shell-Syntax und `git diff --check` | Bestanden |

Die QML-Zahlen schließen Qt-Testinitialisierung und -abschluss ein. Die wiederholten Durchläufe sind dieselben Testfälle unter verschiedenen Bedingungen, keine unterschiedlichen Tests. Der Hauptfenstertest verwendet einen Controller-Testersatz; der Programm-Ladetest verwendet den echten eingebetteten Controller.

Geprüft wurden Einstellungen und Validierungsgrenzen, Konfigurations-Roundtrip, Monitorzuordnung, Positionsauswahl auf jedem virtuellen Monitor, Maus-/Tastaturkorrektur, Abbruch, Vorschau, Fenstergeometrie und Maximierung sowie Lupe, Screenshot-Timeout und verspätete Antworten. Der Scheduler enthält außerdem eine simulierte Zehn-Minuten-Prüfung bei 1, 10, 50 und 100 CPS; dies ist kein Echtzeit-Dauertest.

Der Worker-Test prüft alle drei Maustasten, Einzel- und Doppelklick, genau drei Wiederholungszyklen, vollständige Press-/Release-Folgen, einen fehlgeschlagenen Release samt Wiederholung, Hotkey-Startanforderung, Hotkey-Stopp, Stop-Befehl, doppelte Startbefehle, Hotkey-Sitzungsende und Shutdown. Zusätzlich prüft er absolute Koordinaten am Monitorrand einschließlich Stream-ID, die Ablehnung eines falsch freigegebenen Monitors vor dem ersten Klick, verspätete Antworten auf abgebrochene Starts sowie einen erfolgreichen Neustart nach Abbruch und nach Widerruf einer Maussitzung. Nach dem bestätigten Stop bzw. Sitzungsende dürfen keine weiteren Button-Ereignisse ankommen. Diese Ereignisse gehen ausschließlich an Testportale.

## Behobene Fehler

1. Ein weiterer Startbefehl konnte die Einstellungen einer noch laufenden Berechtigungsanfrage überschreiben. Ein ungültiger weiterer Start konnte sogar den Zustandsautomaten in `Error` versetzen, während der bestehende Scheduler weiterlief; ein nachfolgender Stop griff dann nicht mehr. Doppelte Starts werden jetzt vor Validierung und Einstellungsübernahme verworfen.
2. Das `Closed`-Signal der GlobalShortcuts-Sitzung wurde nicht beobachtet. Der Worker überwacht diese Sitzung jetzt vor Freigabe des Starts und beendet beim Sitzungsende den laufenden Klicker bzw. eine ausstehende Startaufgabe.
3. Nach Widerruf einer Maussitzung wurde beim erneuten Start dieselbe ungültige Sitzung wiederverwendet. Der neue Regressionstest reproduzierte diesen Fehler. Nach einem Klickfehler wird die Sitzung jetzt geschlossen und verworfen, damit der nächste Start eine neue Freigabe anfordert.
4. Im CodeRabbit-Review wurde eine unbegrenzte Wartezeit beim Anmelden der Hotkey-Sitzungsüberwachung gefunden. Die Registrierung ist jetzt auf eine Sekunde begrenzt. Drei zusätzliche Tests prüfen Timeout, eine bereits beendete Sitzung und die weiterhin funktionierende Überwachung nach erfolgreicher Registrierung.

Die Eingabe- und Skalierungsprüfungen deckten zusätzlich Fehler in der Testumgebung auf: einen vom Programm abweichenden Qt-Control-Stil und überlappende virtuelle Ausgänge bei erhöhter Skalierung. Die Tests verwenden jetzt explizit den App-Stil und konfigurieren die Ausgabeskalierung. Der Picker-Test wartet außerdem auf Fensteraktivierung und die asynchrone Bestätigung unter Wayland. Am Verhalten der Eingabefelder und des Positionswählers waren dafür keine Änderungen erforderlich.

## Grenzen

Nicht geprüft sind reale KDE-Berechtigungsdialoge, physische Hotkey-Betätigung, echte Zeigerinjektion, Grafiktreiber, physische Monitorwechsel oder gemischte Skalierungen verschiedener Monitore. Auch Arch-Paketinstallation und ein Release-Build waren nicht Bestandteil dieses Durchlaufs. Ein fehlerfreier Betrieb auf einer nativen Plasma-Wayland-Sitzung ist damit noch nicht vollständig nachgewiesen. Unter der vorhandenen XFCE/X11-Sitzung ist die Wayland-App nicht bestimmungsgemäß nutzbar.

Die reproduzierbaren Testbefehle stehen in der README. `tests/qml-wayland.sh` verwendet einen eigenen Session-Bus, Konfigurationsordner und virtuellen Compositor.
