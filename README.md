# Klickmeister

Ein kleiner Auto Clicker für KDE Plasma 6 unter Wayland.

Klickmeister übernimmt wiederholte Mausklicks für dich – zum Beispiel in Spielen, beim Testen oder bei Aufgaben, bei denen du sonst immer wieder dieselbe Stelle anklicken müsstest.

## „Moment, was macht das Programm genau?“

Du entscheidest, wie geklickt werden soll:

- linke, rechte oder mittlere Maustaste
- Einzel- oder Doppelklick
- an der aktuellen Mausposition oder an einer festen Stelle
- feste Positionen per Vollbild-Positionswähler auf einem ausgewählten Bildschirm
- so lange, bis du stoppst, oder nur eine bestimmte Anzahl
- langsam oder bis zu 100 Klicks pro Sekunde

Gestartet und gestoppt wird Klickmeister über einen globalen Hotkey. Standardmäßig ist dafür die `Pause`-Taste vorgesehen. Du kannst den Klicker jederzeit über den Hotkey oder den Stop-Button beenden.

Klickmeister wurde speziell für KDE Plasma unter Wayland gebaut. Es gibt keinen Hintergrunddienst, keinen Autostart und keine versteckten Prozesse. Wenn du das Fenster schließt, ist das Programm wirklich beendet.

## Installation

Klickmeister ist aktuell für Arch Linux und darauf basierende Systeme wie CachyOS gedacht.

Zuerst werden die benötigten Pakete installiert:

```bash
sudo pacman -S git rust cargo clang lld pkgconf qt6-base qt6-declarative qt6-tools kirigami xdg-desktop-portal xdg-desktop-portal-kde
```

Danach kannst du das Projekt herunterladen und installieren:

```bash
git clone https://github.com/jerry0205/Auto-Clicker.git
cd Auto-Clicker
makepkg -si
```

Anschließend findest du **Klickmeister** ganz normal im KDE-Anwendungsmenü.

## Erste Schritte

1. Öffne Klickmeister.
2. Wähle Maustaste, Klickart und Geschwindigkeit aus.
3. Entscheide, ob an der aktuellen oder an einer festen Position geklickt werden soll.
4. Starte den Klicker mit dem Hotkey.
5. Drücke den Hotkey erneut, um ihn zu stoppen.

Wenn du eine feste Position verwenden möchtest, wählst du zuerst den Bildschirm aus und klickst danach im Vollbild-Positionswähler auf die gewünschte Stelle. Das Hauptfenster wird dafür ausgeblendet. Ein Fadenkreuz zeigt die Koordinaten; Pfeiltasten verschieben das Ziel um eine logische Koordinateneinheit, Umschalt + Pfeiltasten um zehn. Klicken oder Enter übernimmt die Position, Esc oder Rechtsklick bricht ab. „Position anzeigen“ markiert das gespeicherte Ziel kurz, ohne zu klicken.

Optional verwendet „Mit 4×-Lupe auswählen“ eine über das Screenshot-Portal freigegebene Bildschirmaufnahme als Standbild. Bei Ablehnung, Fehler oder nach spätestens drei Sekunden Wartezeit funktioniert die Auswahl ohne Lupe weiter. Ausstehende Screenshot-Anfragen werden dabei geschlossen. Die Aufnahme ist keine Live-Vorschau.

Beim Start fragt KDE, auf welchem Bildschirm geklickt werden darf. Wähle dort denselben Bildschirm aus. Position und Größe des freigegebenen Monitors werden vor dem ersten Klick geprüft. Ein anderer Monitor oder fehlende Zuordnungsdaten führen zu einer Fehlermeldung. Nach einem Monitorwechsel wird eine passende Freigabe erneut angefragt. Monitoridentität, Größe und Skalierung werden mit den Koordinaten gespeichert. Nach einem Neustart wird nur eine eindeutige Übereinstimmung wiederhergestellt; andernfalls müssen Monitor und Koordinaten bestätigt oder neu gewählt werden.

## Warum fragt KDE nach Berechtigungen?

Wayland erlaubt Programmen nicht, ohne Erlaubnis deine Maus zu steuern oder globale Tastenkürzel zu verwenden. Deshalb zeigt KDE beim ersten Start einige eigene Sicherheitsdialoge an.

Klickmeister benötigt die Erlaubnis:

- den Start-/Stop-Hotkey systemweit zu erkennen
- Mausklicks auszuführen
- bei einer festen Position den ausgewählten Bildschirm zuzuordnen

Das Programm liest keine Tastatureingaben, Passwörter oder Zwischenablagen mit. Nur die optional aktivierte Lupe lädt eine Bildschirmaufnahme über das Screenshot-Portal. Diese wird nach der Auswahl aus der Anzeige entfernt; das Portal kann dafür eine temporäre Bilddatei erzeugen. Es wird kein Bildschirmvideo aufgenommen. Alle Freigaben enden, sobald du Klickmeister schließt.

Ohne funktionierenden Stop-Hotkey startet der Auto Clicker absichtlich nicht. So kannst du ihn immer sicher anhalten.

## Gut zu wissen

- Das kleinste Intervall beträgt 10 Millisekunden. Mehr als 100 Klicks pro Sekunde sind nicht möglich.
- Eine feste Position gilt immer für den Bildschirm, den du im KDE-Dialog ausgewählt hast.
- Die Monitorauswahl zeigt Hersteller und Modell aus den Systemdaten. Bei gleichen Modellen oder fehlenden Modellangaben wird der Anschluss zur Unterscheidung ergänzt.
- Der Positionswähler öffnet sich auf dem Bildschirm, den du zuvor in Klickmeister ausgewählt hast.
- Klickmeister ist nur für Wayland gedacht. Ein X11- oder `xdotool`-Ersatz ist nicht eingebaut.
- Gespeichert werden nur deine Einstellungen. Es gibt keine Statistiken, keine Nutzungsdaten und keine Telemetrie.

## Für Entwickler

Du möchtest Klickmeister selbst bauen, verändern oder überprüfen? Die wichtigsten Befehle sind:

```bash
cargo fmt --all -- --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
dbus-run-session -- cargo test --locked closes_real_dbus_request -- --ignored
cargo build --locked --release
bash tests/qml-smoke.sh target/release/klickmeister
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input tests/qml
```

Mehr über den Aufbau und die Sicherheitsentscheidungen findest du in [ARCHITECTURE.md](ARCHITECTURE.md) und [SECURITY_REVIEW.md](SECURITY_REVIEW.md).

## Lizenz

Klickmeister ist freie Software und steht unter der [MIT-Lizenz](LICENSE).
