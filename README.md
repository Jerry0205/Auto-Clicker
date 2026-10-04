# Klickmeister

Ein kleiner Auto Clicker für KDE Plasma 6 unter Wayland.

Klickmeister übernimmt wiederholte Mausklicks für dich – zum Beispiel in Spielen, beim Testen oder bei Aufgaben, bei denen du sonst immer wieder dieselbe Stelle anklicken müsstest.

## „Moment, was macht das Programm genau?“

Du entscheidest, wie geklickt werden soll:

- linke, rechte oder mittlere Maustaste
- Einzel- oder Doppelklick
- an der aktuellen Mausposition oder an einer festen Stelle
- feste Positionen per Vollbild-Positionswähler auf einem ausgewählten Bildschirm
- so lange, bis du stoppst, oder nur eine bestimmte Anzahl von Klickzyklen
- langsam oder bis zu 100 Klickzyklen pro Sekunde

Ein Klickzyklus erzeugt bei „Einfach“ einen Klick, bei „Doppelt“ zwei einzelne Klicks. Bei einem Intervall von 10 ms sind höchstens 100 Zyklen pro Sekunde vorgesehen: 100 einzelne Klicks im Einfachmodus oder 200 im Doppelklickmodus. Die Wiederholungszahl 3 bedeutet drei Zyklen, also im Doppelklickmodus insgesamt sechs einzelne Klicks. Bei Intervallen über einer Sekunde zeigt die Oberfläche stattdessen an, wie viele Sekunden zwischen den Zyklen liegen.

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

`makepkg` lädt dafür den per Prüfsumme gesicherten Quellstand für Version 0.1.2
herunter und baut ihn unter `$srcdir`. Lokale Änderungen im geklonten Verzeichnis
gehen nicht in das Paket ein. Mit `makepkg --allsource --nodeps` kannst du ein
Quellpaket einschließlich des heruntergeladenen Projektarchivs erstellen; es
lässt sich in einem anderen Verzeichnis ohne den ursprünglichen Checkout bauen.
Cargo-Abhängigkeiten werden beim Paketbau weiterhin mit `cargo fetch --locked`
geladen.

Anschließend findest du **Klickmeister** ganz normal im KDE-Anwendungsmenü.

## Erste Schritte

1. Öffne Klickmeister.
2. Wähle Maustaste, Klickart und Geschwindigkeit aus.
3. Entscheide, ob an der aktuellen oder an einer festen Position geklickt werden soll.
4. Starte den Klicker mit dem Hotkey.
5. Drücke den Hotkey erneut, um ihn zu stoppen.

Hotkey-Betätigungen, die sich während eines Laufs angestaut haben, etwa weil KWin einen Klick verzögert bestätigt, können den Lauf noch beenden, aber nach dem Stopp keinen neuen Lauf starten. Die nächste Betätigung danach startet wie gewohnt.

Wenn du mit der Schaltfläche **Starten** an der aktuellen Cursorposition beginnst, startet nach der Wayland-Freigabe ein sichtbarer Countdown von drei Sekunden. Bewege den Mauszeiger in dieser Zeit zum Ziel. **Start abbrechen** oder der globale Hotkey beendet den Countdown ohne Klick. Beim Start per Hotkey und bei einer festen Position beginnt der Klicker nach der Freigabe sofort: Beim Hotkey steht der Zeiger bereits am gewünschten Ort, bei einer festen Position setzt der Klicker ihn selbst auf das Ziel.

Wenn du eine feste Position verwenden möchtest, wählst du zuerst den Bildschirm aus und klickst danach im Vollbild-Positionswähler auf die gewünschte Stelle. Das Hauptfenster wird dafür vorübergehend minimiert; seine bisherige Größe, Position und Maximierung bleiben erhalten. Ein Fadenkreuz zeigt die Koordinaten; Pfeiltasten verschieben das Ziel um eine logische Koordinateneinheit, Umschalt + Pfeiltasten um zehn. Ein Linksklick setzt das Ziel und hält es für die Feineinstellung fest. Enter übernimmt die Position, Esc oder Rechtsklick bricht ab. Mausbewegungen verschieben ein bereits angeklicktes oder per Pfeiltasten korrigiertes Ziel nicht mehr. „Position anzeigen“ markiert das gespeicherte Ziel kurz, ohne zu klicken.

Eine Lupe gibt es derzeit nicht. Das Screenshot-Portal teilt der App nicht mit, welchen Ausschnitt eine Aufnahme zeigt. Ein vergrößertes Standbild könnte deshalb an der falschen Desktopposition erscheinen. Der Positionswähler arbeitet daher ohne Bildschirmaufnahme direkt über dem sichtbaren Desktop.

Beim Start fragt KDE, auf welchem Bildschirm geklickt werden darf. Wähle dort denselben Bildschirm aus. Position und Größe des freigegebenen Monitors werden vor dem ersten Klick geprüft. Ein anderer Monitor oder fehlende Zuordnungsdaten führen zu einer Fehlermeldung. Nach einem Monitorwechsel wird eine passende Freigabe erneut angefragt. Monitoridentität, Größe und Skalierung werden mit den Koordinaten gespeichert. Nach einem Neustart wird nur eine eindeutige Übereinstimmung wiederhergestellt; andernfalls müssen Monitor und Koordinaten bestätigt oder neu gewählt werden.

## Warum fragt KDE nach Berechtigungen?

Wayland erlaubt Programmen nicht, ohne Erlaubnis deine Maus zu steuern oder globale Tastenkürzel zu verwenden. Deshalb zeigt KDE beim ersten Start einige eigene Sicherheitsdialoge an.

Klickmeister benötigt die Erlaubnis:

- den Start-/Stop-Hotkey systemweit zu erkennen
- Mausklicks auszuführen
- bei einer festen Position den ausgewählten Bildschirm zuzuordnen

Das Programm liest keine Tastatureingaben, Passwörter oder Zwischenablagen mit. Klickmeister fordert keine Screenshots an. Die Bildschirmfreigabe bei fester Position dient nur der Koordinatenzuordnung; dabei wird weder ein Bild noch ein Video gelesen. Alle Freigaben enden, sobald du Klickmeister schließt.

Ohne funktionierenden Stop-Hotkey startet der Auto Clicker absichtlich nicht. So kannst du ihn immer sicher anhalten.
Wenn du die Hotkey-Freigabe ablehnst, die Stop-Taste entfernst oder KDE die Hotkey-Sitzung beendet, kannst du sie im Abschnitt „Globaler Hotkey“ mit „Erneut versuchen“ neu einrichten, ohne Klickmeister neu zu starten.

## Gut zu wissen

- Das kleinste Intervall beträgt 10 Millisekunden. Der Scheduler plant höchstens 100 Klickzyklen pro Sekunde; im Doppelklickmodus sind das bis zu 200 einzelne Klicks pro Sekunde.
- Eine feste Position gilt immer für den Bildschirm, den du im KDE-Dialog ausgewählt hast.
- Die Monitorauswahl zeigt Hersteller und Modell aus den Systemdaten. Bei gleichen Modellen oder fehlenden Modellangaben wird der Anschluss zur Unterscheidung ergänzt.
- Der Positionswähler öffnet sich auf dem Bildschirm, den du zuvor in Klickmeister ausgewählt hast.
- Klickmeister ist nur für Wayland gedacht. Ein X11- oder `xdotool`-Ersatz ist nicht eingebaut.
- Gespeichert werden nur deine Einstellungen. Es gibt keine Statistiken, keine Nutzungsdaten und keine Telemetrie.
- Änderungen an den Einstellungen werden beim Schließen gespeichert, auch wenn du keinen Klicklauf gestartet hast. Falls das Speichern fehlschlägt, kannst du weiterarbeiten oder ausdrücklich ohne Speichern schließen.
- Fehlt der Monitor einer gespeicherten festen Position beim Start, bleibt diese Position samt Monitor-Zuordnung gespeichert, bis du selbst eine neue Position wählst oder einen Monitor bestätigst. Wählst du ihren Monitor später wieder aus, erscheint die gespeicherte Position erneut.

## Für Entwickler

Du möchtest Klickmeister selbst bauen, verändern oder überprüfen? Die wichtigsten Befehle sind:

Die folgenden Cargo-Befehle verwenden den aktuellen Checkout einschließlich
lokaler Änderungen. `makepkg` verwendet dagegen den oben genannten Quellstand.

Für die QML-Codevervollständigung und Fehleranzeige mit `qmlls` zuerst `cargo build --locked` ausführen und danach `bash scripts/setup-qmlls.sh`. Das Skript ermittelt das wirksame Cargo-Buildverzeichnis (auch bei `CARGO_TARGET_DIR` oder `build.target-dir`) und schreibt die lokale, von Git ignorierte `.qmlls.ini`. Nach einem Wechsel des Buildverzeichnisses das Skript erneut ausführen. Für das Skript und den folgenden Test wird Python 3 benötigt. `python tests/check_qmlls_checkout.py` prüft den committeten Stand in einem frischen Checkout mit einem anderen Pfad und fragt die `AppController`-Eigenschaften direkt beim QML-Sprachserver ab.

```bash
cargo fmt --all -- --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
dbus-run-session -- cargo test --locked --all-targets -- --ignored
cargo build --locked --release
bash tests/qml-smoke.sh target/release/klickmeister
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -import tests/qml/mocks -input tests/qml
python tests/check_coordinate_accessibility.py # in einer grafischen Sitzung mit AT-SPI und PyGObject
bash tests/qml-wayland.sh # isolierter KWin mit drei Monitoren (benötigt kscreen-doctor)
KLICKMEISTER_TEST_SCALE=1.5 bash tests/qml-wayland.sh
```

Die QML-Tests verwenden denselben KDE-Control-Stil wie die App und für das Hauptfenster einen Controller-Testersatz. Die AT-SPI-Prüfung startet dieses Hauptfenster ohne Worker und bestätigt die zugänglichen Namen der X-/Y-SpinBoxen sowie ihrer Texteingaben im Accessibility-Baum. Die separaten D-Bus-Tests prüfen den echten Rust-Worker gegen simulierte Portale, einschließlich Klickfolgen, Stop-Hotkey, angestauter Hotkey-Signale nach einem Stopp, Sitzungsende und Button-Release-Fehlern. Sie erzeugen keine tatsächlichen Mausklicks auf dem Desktop. Echte KDE-Freigabedialoge und die Zeigersteuerung auf physischen Monitoren müssen zusätzlich in einer nativen Plasma-Wayland-Sitzung geprüft werden.

Beim Start setzt die App den Qt-Desktop-Dateinamen auf `io.github.jerry0205.klickmeister`, passend zur installierten `.desktop`-Datei. Der QML-Smoke-Test prüft diesen Wert am gebauten Programm. Diese Qt-Einstellung ordnet das Fenster dem Desktop-Eintrag zu; die [Portal-Anwendungs-ID](https://flatpak.github.io/xdg-desktop-portal/docs/api-reference) wird für die separaten D-Bus-Verbindungen anhand des Startkontexts bestimmt. Ein direkter Start der Entwicklungs-Binärdatei kann daher in Portal-Dialogen anders benannt werden als ein Start über das Anwendungsmenü.

GitHub Actions führt bei Pull Requests und Änderungen an `main` Formatierung, Clippy, Rust-Tests, die ignorierten Portaltests auf einem privaten D-Bus, QML-Tests im KDE-Stil, Python-Wächtertests und die Desktop-/AppStream-Validierung aus. Anschließend wird das Release-Programm gebaut und mit `tests/qml-smoke.sh` geprüft. Ein eigener Job führt die QML-Tests unter einem isolierten virtuellen KWin mit drei Monitoren aus. Beide Jobs verwenden ein Arch-Linux-Containerimage und die Cargo-Lockdatei; native Tests mit echten KDE-Dialogen bleiben eine manuelle Prüfung.

Für die manuelle Prüfung des Start-Countdowns: Wähle „Aktuelle Cursorposition“, starte über die Schaltfläche und bewege den Zeiger auf ein unkritisches eigenes Testziel. Prüfe, dass vor Ablauf der drei Sekunden kein Klick erfolgt und sowohl **Start abbrechen** als auch der globale Hotkey den Countdown ohne Klick beenden. Wiederhole den Start bei bereits erteilter Wayland-Freigabe. Ein Start per Hotkey und ein Start mit fester Position beginnen dagegen ohne Countdown.

Die abgesicherten nativen Testwerkzeuge und ihre Voraussetzungen sind unter [tests/native](tests/native/README.md) dokumentiert.

Mehr über den Aufbau und die Sicherheitsentscheidungen findest du in [ARCHITECTURE.md](ARCHITECTURE.md) und [SECURITY_REVIEW.md](SECURITY_REVIEW.md).

## Lizenz

Klickmeister ist freie Software und steht unter der [MIT-Lizenz](LICENSE).
