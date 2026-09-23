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

Wenn du eine feste Position verwenden möchtest, wählst du zuerst den Bildschirm aus und klickst danach im Vollbild-Positionswähler auf die gewünschte Stelle. Das Hauptfenster wird dafür vorübergehend minimiert; seine bisherige Größe, Position und Maximierung bleiben erhalten. Ein Fadenkreuz zeigt die Koordinaten; Pfeiltasten verschieben das Ziel um eine logische Koordinateneinheit, Umschalt + Pfeiltasten um zehn. Ein Linksklick setzt das Ziel und hält es für die Feineinstellung fest. Enter übernimmt die Position, Esc oder Rechtsklick bricht ab. Mausbewegungen verschieben ein bereits angeklicktes oder per Pfeiltasten korrigiertes Ziel nicht mehr. „Position anzeigen“ markiert das gespeicherte Ziel kurz, ohne zu klicken.

Optional verwendet „Mit 4×-Lupe auswählen“ eine über das interaktive Screenshot-Portal freigegebene Bildschirmaufnahme als Standbild. Wähle im KDE-Dialog **Vollbild**, dann **Übernehmen** (je nach Übersetzung „Aufnehmen“) und **Speichern**. Bei Ablehnung, Fehler oder nach spätestens drei Sekunden Wartezeit funktioniert die Auswahl ohne Lupe weiter; die ausstehende Anfrage wird geschlossen. Dieser Ablauf umgeht die blockierende nichtinteraktive Erstfreigabe von xdg-desktop-portal 1.22.1 und wurde mit echten KDE-Dialogen geprüft. Falls dennoch ein alter KDE-Freigabedialog offen bleibt, schließe ihn mit „Deny“/„Verweigern“. Details stehen im [Regressionstestbericht](tests/PORTAL_FIX_REPORT.md). Die Aufnahme ist keine Live-Vorschau.

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
dbus-run-session -- cargo test --locked --all-targets -- --ignored
cargo build --locked --release
bash tests/qml-smoke.sh target/release/klickmeister
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -import tests/qml/mocks -input tests/qml
bash tests/qml-wayland.sh # isolierter KWin mit drei Monitoren (benötigt kscreen-doctor)
KLICKMEISTER_TEST_SCALE=1.5 bash tests/qml-wayland.sh
```

Die QML-Tests verwenden denselben KDE-Control-Stil wie die App und für das Hauptfenster einen Controller-Testersatz. Die separaten D-Bus-Tests prüfen den echten Rust-Worker gegen simulierte Portale, einschließlich Klickfolgen, Stop-Hotkey, Sitzungsende und Button-Release-Fehlern. Sie erzeugen keine tatsächlichen Mausklicks auf dem Desktop. Echte KDE-Freigabedialoge und die Zeigersteuerung auf physischen Monitoren müssen zusätzlich in einer nativen Plasma-Wayland-Sitzung geprüft werden.

Beim Start setzt die App den Qt-Desktop-Dateinamen auf `io.github.jerry0205.klickmeister`, passend zur installierten `.desktop`-Datei. Der QML-Smoke-Test prüft diesen Wert am gebauten Programm. Diese Qt-Einstellung ordnet das Fenster dem Desktop-Eintrag zu; die [Portal-Anwendungs-ID](https://flatpak.github.io/xdg-desktop-portal/docs/api-reference) wird für die separaten D-Bus-Verbindungen anhand des Startkontexts bestimmt. Ein direkter Start der Entwicklungs-Binärdatei kann daher in Portal-Dialogen anders benannt werden als ein Start über das Anwendungsmenü.

Die abgesicherten nativen Testwerkzeuge und ihre Voraussetzungen sind unter [tests/native](tests/native/README.md) dokumentiert.

Mehr über den Aufbau und die Sicherheitsentscheidungen findest du in [ARCHITECTURE.md](ARCHITECTURE.md) und [SECURITY_REVIEW.md](SECURITY_REVIEW.md).

## Lizenz

Klickmeister ist freie Software und steht unter der [MIT-Lizenz](LICENSE).
