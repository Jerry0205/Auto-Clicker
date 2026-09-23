# Security Review

Stand: 2026-09-23, Version 0.1.2 (Portal-Bereinigung und priorisierter Stop; native Geräteprüfung siehe Testbericht zu 0.1.1)

## 1. Benötigte Berechtigungen

- Globale Shortcut-Aktion: erforderlich als sofort erreichbarer Start/Stop-Failsafe.
- RemoteDesktop-Gerät `POINTER`: erforderlich, um linke, rechte oder mittlere Button-Ereignisse zu emulieren.
- Ein Monitor als ScreenCast-Koordinatenreferenz: nur bei fester Position erforderlich.
- Screenshot-Freigabe: nur für die ausdrücklich aktivierte Standbild-Lupe.

Nicht angefordert werden `KEYBOARD`, `TOUCHSCREEN`, Clipboard, Kamera, Mikrofon, Dateien, Standort, Benachrichtigungen, Hintergrundausführung oder Netzwerk.

## 2. Verwendete D-Bus-/Portal-Schnittstellen

- `org.freedesktop.portal.GlobalShortcuts`: `CreateSession`, `BindShortcuts`, `ConfigureShortcuts`, `Activated`, `ShortcutsChanged` und `Session.Close`.
- `org.freedesktop.portal.RemoteDesktop`: `CreateSession`, `SelectDevices`, `Start`, `NotifyPointerButton`, optional `NotifyPointerMotionAbsolute` und `Session.Close`.
- `org.freedesktop.portal.Screenshot`: `Screenshot` und `Request.Close`, ausschließlich für die optionale Lupe; nur lokale Datei-URIs werden geladen.
- `org.freedesktop.portal.ScreenCast`: nur `SelectSources` auf derselben RemoteDesktop-Sitzung. `OpenPipeWireRemote` wird nicht aufgerufen.

Sitzungen verwenden `PersistMode::Application`: keine anwendungsseitig gespeicherten Restore-Tokens und keine dauerhafte Berechtigung nach Prozessende.

## 3. Netzwerkzugriffe

Keine. Der Produktionscode enthält keine HTTP-, TCP-, UDP- oder DNS-API. D-Bus nutzt ausschließlich den lokalen Unix-Session-Bus. Cargo kann beim Bauen checksummengeprüften Quellcode beziehen; das ist kein Laufzeitverhalten der Anwendung.

## 4. Gespeicherte Daten

Nur `config.toml` im XDG-Konfigurationsverzeichnis der Anwendung. Gespeichert werden Intervall, Maustaste, Klicktyp, Wiederholungsmodus/-zahl, Positionsmodus, X/Y, Monitoridentität einschließlich Geometrie/Skalierung und sichtbare Hotkeybeschreibung. Der Austausch erfolgt über eine temporäre Datei im selben Verzeichnis und `rename`. Auf Unix wird die Datei mit Modus 0600 erstellt.

Die optionale Lupe lädt eine vom Screenshot-Portal bereitgestellte Bilddatei; das Portal kann diese temporär speichern. Klickmeister leert die Bildquelle beim Beenden der Auswahl und führt kein Screenshot-Archiv.

Keine Eingaben, Klickhistorien, Fenstertitel, Prozessinformationen, Clipboard-Inhalte, Kennwörter oder Portal-Restore-Tokens werden gespeichert.

## 5. Threading-Modell

Der Qt-Main-Thread besitzt die GUI. Genau ein Rust-Workerthread besitzt Zustandsautomat, Scheduler und Portalobjekte. Ein begrenzter Kanal (16 Befehle) verhindert unbeschränktes Anwachsen. Stop und Shutdown verwenden ein priorisiertes Ein-Wert-Signal, damit sie auch bei vollem Befehlskanal ankommen. Zustandsupdates gelangen über die threadsichere CXX-Qt-Queue in den Qt-Event-Loop.

Alle Startpfade verwenden denselben `StateMachine`. `Starting` und `Clicking` weisen weitere Startbefehle ab. Es existiert höchstens ein `ActiveRun` und eine Start-Aufgabe. Abgebrochene Starts werden verworfen.

## 6. Failsafe-Verhalten

- Ohne bestätigten globalen Hotkey wird Start abgewiesen.
- Hotkey und Stop-Button setzen den einzigen aktiven Run auf `Stopped` und entfernen seinen Termin.
- Fenster-Schließen ruft synchron `shutdown` auf, beendet den Worker und schließt beide Portal-Sitzungen. Ausstehende RemoteDesktop- und Hotkey-Anfragen werden kooperativ abgebrochen. Jede Anfrage besitzt ihre D-Bus-Verbindung, die nach begrenztem `Session.Close` ebenfalls getrennt wird; die Bereinigung wird vor der Stop-/Shutdown-Bestätigung abgewartet.
- Ein Prozessende trennt zusätzlich automatisch den D-Bus-Client; es gibt keinen separaten Clickerprozess.
- Nach erfolgreichem Button-Press wird immer ein Release versucht. Schlägt Release fehl, folgt ein zweiter Best-Effort-Release und der Scheduler geht in Fehlerzustand.
- Verpasste Timings werden nicht nachgeholt; dadurch entsteht kein Event-Burst.

## 7. Bekannte Einschränkungen

- Ein echtes globales Auslesen der Cursorposition ist unter Wayland absichtlich nicht möglich. Der Picker nutzt ein eigenes Vollbildfenster.
- Für absolute Positionen muss der Benutzer im KWin-Dialog denselben Monitor wählen. Position und Größe werden vor Nutzung mit der Auswahl abgeglichen; fehlende Metadaten verhindern den Start. Displayänderungen können die Sitzung ungültig machen und führen dann zum Stop mit Fehlermeldung.
- Portal-Dialoge sind derzeit nicht an einen exportierten Wayland-Fensterhandle gekoppelt und können daher als separates KWin-Dialogfenster erscheinen.
- Auf dem früher geprüften xdg-desktop-portal 1.22.1 konnte eine unbeantwortete nichtinteraktive Screenshot-Erstfreigabe trotz Request.Close und getrennter App-Verbindung offen bleiben und weitere Portal-Aufrufe blockieren. Die Lupe verwendet inzwischen die interaktive Freigabe; der Picker fällt nach 20 Sekunden ab Anfrage auf Auswahl ohne Lupe zurück und versucht, die Anfrage zu schließen. Bleibt ein alter KDE-Dialog dennoch offen, muss er regulär abgelehnt werden. Die ursprüngliche Desktop-Einschränkung ist mit Reproduktion und Quellen in [DEVICE_TEST_REPORT.md](tests/DEVICE_TEST_REPORT.md) dokumentiert.
- `SIGKILL` verhindert anwendungsseitiges RAII-Cleanup; der D-Bus-Verbindungsabbruch beendet die compositorseitige Sitzung dennoch.
- Die D-Bus-Notify-Methode ist bei 100 CPS bewusst konservativer als das empfohlene EIS-Protokoll. Sie vermeidet eine weitere native FFI-Abhängigkeit und ist für das gesetzte Limit ausreichend.

## 8. Dependency-Liste

Direkt: `ashpd`, `cxx`, `cxx-qt`, `cxx-qt-lib`, `futures-util`, `serde`, `thiserror`, `tokio`, `toml`; Build: `cxx-qt-build`. Die vollständige transitive Liste ist mit `cargo tree --locked` reproduzierbar. Qt/Kirigami und xdg-desktop-portal-kde kommen aus den signierten Arch-Repositories.

`cargo tree --locked` wurde für diesen Stand erfolgreich ausgeführt. `cargo-audit` war im Prüfsystem nicht installiert; entsprechend wurde nichts ungefragt installiert. Nach Installation des Arch-Pakets `cargo-audit` ist `cargo audit` der dokumentierte Prüfbefehl.

CXX-Qt erzeugt die notwendige Qt-FFI und enthält intern `unsafe`; der handgeschriebene Scheduler-, Konfigurations- und Portalcode enthält keine `unsafe`-Blöcke. Die beiden `unsafe extern "C++"`-Deklarationen in `controller.rs` und `qml_runtime.rs` sind ausschließlich typisierte CXX-Brücken zu Qt. Der kleine QML-Ladehelfer liest nur `QQmlApplicationEngine::rootObjects().isEmpty()` und verändert keinen fremden Zustand.

## 9. Mögliche Sicherheitsrisiken

- Pointer-Steuerung ist eine wirkungsvolle Berechtigung. Ein Fehler könnte in der aktiven Sitzung auf falsche Oberflächen klicken. Begrenzung, Portalbestätigung, Einzel-Scheduler und mehrere Stopwege reduzieren das Risiko.
- Eine kompromittierte Portal-/Compositorimplementierung liegt außerhalb der Vertrauensgrenze der Anwendung.
- Bei fester Position stellt das Portal prinzipiell einen Streamhandle bereit. Klickmeister öffnet ihn nicht; eine spätere Codeänderung an diesem Punkt muss erneut geprüft werden.
- Abhängigkeiten bilden Supply-Chain-Risiken. `Cargo.lock`, Arch-Paketsignaturen, `cargo audit` und Review von Dependency-Änderungen sind die vorgesehenen Kontrollen.
- Doppelklick erzeugt pro begrenztem Scheduler-Tick zwei Press/Release-Paare. Damit liegt die Zyklusrate bei höchstens 100 CPS, die Button-Ereigniszahl naturgemäß höher. Es gibt weiterhin keine ungebremste Schleife.

## Review-Checkliste

- Netzwerk-APIs im Produktionscode: keine gefunden.
- Shellausführung oder Befehlszusammensetzung: keine gefunden.
- Root, sudo, `/dev/uinput`: keine Verwendung.
- systemd, Autostart, Daemon oder Prozess-Fork/-Spawn: keine Verwendung. Der einzige `std::thread` bleibt Bestandteil desselben Prozesses.
- Fremdprozesse, Clipboard, Tastaturmitschnitt: keine Verwendung.
- Busy-Wait oder Intervall 0: durch Design und Validierung ausgeschlossen.
- Unbegrenzte Queue oder parallele Click-Loops: ausgeschlossen.
