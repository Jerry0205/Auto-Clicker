# Klickmeister

Automatische Mausklicks für KDE Plasma.

Klickmeister übernimmt wiederholte Mausklicks unter KDE Plasma 6 auf Wayland. Wähle Position, Klickintervall und Wiederholungen. Ein globales Tastenkürzel startet und stoppt das Klicken.

## Funktionen

- Linke, rechte oder mittlere Maustaste
- Einzel- oder Doppelklick
- Aktuelle Mauszeigerposition oder feste Position auf einem ausgewählten Bildschirm
- Positionsauswahl direkt auf dem Desktop, mit Feineinstellung per Pfeiltasten
- Eine festgelegte Anzahl von Klickzyklen oder Klicken bis zum Stopp
- Klickintervalle von 10 Millisekunden bis 24 Stunden

Ein Klickzyklus entspricht einem Einzel- oder Doppelklick. Drei Zyklen erzeugen drei Einzelklicks oder drei Doppelklicks, also sechs einzelne Klicks. Bei 10 ms plant Klickmeister höchstens 100 Zyklen pro Sekunde. Die Oberfläche zeigt die Zyklus- und Klickrate an; bei Intervallen über einer Sekunde zeigt sie den Abstand zwischen den Zyklen.

## Installation

Klickmeister benötigt KDE Plasma 6, eine Wayland-Sitzung und den KDE-Portaldienst. Das mitgelieferte Paket ist für Arch Linux und darauf basierende Distributionen wie CachyOS vorgesehen.

Installiere die Build- und Laufzeitabhängigkeiten:

```bash
sudo pacman -S git rust cargo clang lld pkgconf qt6-base qt6-declarative qt6-tools kirigami xdg-desktop-portal xdg-desktop-portal-kde
```

Lade das Projekt herunter und baue das Paket:

```bash
git clone https://github.com/jerry0205/Auto-Clicker.git
cd Auto-Clicker
makepkg -si
```

Danach ist **Klickmeister** im KDE-Anwendungsmenü verfügbar.

`makepkg` baut den mit Prüfsumme gesicherten Quellstand für Version 0.1.2. Änderungen im lokalen Checkout werden dabei nicht übernommen. Die Befehle zum Bauen des aktuellen Checkouts stehen unter [Entwicklung](#entwicklung).

## Erste Schritte

1. Öffne Klickmeister und bestätige im KDE-Dialog das Tastenkürzel für Start und Stopp.
2. Wähle Maustaste, Klickart und Klickintervall.
3. Lege die Wiederholungen und die Klickposition fest.
4. Drücke das Tastenkürzel oder wähle **Starten**. Bestätige die Freigabe für die Maussteuerung im KDE-Dialog.
5. Drücke das Tastenkürzel erneut oder wähle **Stoppen**, um das Klicken zu beenden.

Als Tastenkürzel wird `Pause` vorgeschlagen. Das aktive Kürzel steht im Abschnitt **Tastenkürzel**; mit **Ändern …** lässt es sich im KDE-Dialog anpassen. Klickmeister startet erst, wenn ein Tastenkürzel für Start und Stopp eingerichtet ist.

### Start an der Mauszeigerposition

Bei **Aktuelle Mauszeigerposition** folgt jeder Klick dem Mauszeiger. Beim Start über die Schaltfläche beginnt nach der Freigabe ein Countdown von drei Sekunden. Bewege den Mauszeiger in dieser Zeit zum Ziel. **Start abbrechen** oder das Tastenkürzel beendet den Countdown ohne Klick.

Beim Start per Tastenkürzel beginnt das Klicken nach der Freigabe sofort. Das gilt auch beim Start an einer festen Position.

### Feste Position wählen

1. Wähle **Feste Position** und den gewünschten **Bildschirm**.
2. Wähle **Position wählen …**. Die Positionsauswahl öffnet sich auf diesem Bildschirm.
3. Setze die Position mit einem Linksklick. Mit den Pfeiltasten verschiebst du sie um einen Schritt, mit `Umschalt` + Pfeiltasten um zehn Schritte.
4. Bestätige mit `Enter`. `Esc` oder ein Rechtsklick bricht die Auswahl ab.

Nach einem Linksklick oder einer Korrektur per Pfeiltasten bleibt die Position fixiert; Mausbewegungen verändern sie dann nicht mehr. **Position anzeigen** markiert das gespeicherte Ziel kurz, ohne zu klicken.

Das Hauptfenster wird während der Auswahl minimiert und danach mit seiner bisherigen Größe, Position und Maximierung wiederhergestellt. Die Auswahl liegt direkt über dem Desktop. Sie erstellt keine Bildschirmaufnahme und verwendet keine Lupe.

Gib beim Start im KDE-Dialog denselben Bildschirm frei, den du in Klickmeister ausgewählt hast. Klickmeister prüft die Zuordnung vor dem ersten Klick. Bei einem anderen Bildschirm oder einer uneindeutigen Zuordnung wird der Start abgebrochen.

Eine feste Position bleibt mit ihrem Bildschirm gespeichert. Ändern sich Auflösung oder Skalierung, muss sie erneut bestätigt werden. Ist der Bildschirm nicht verfügbar oder nicht eindeutig wiederzuerkennen, prüfe Bildschirm und Koordinaten und wähle **Position bestätigen** oder eine neue Position. Die gespeicherte Position bleibt erhalten, bis du sie bestätigst oder ersetzt.

## Freigaben und Datenschutz

KDE fragt nach Freigaben für das globale Tastenkürzel und die Maussteuerung. Bei einer festen Position kommt eine Bildschirmfreigabe hinzu, damit Klickmeister die Koordinaten zuordnen kann. Dabei werden keine Bild- oder Videodaten gelesen.

Klickmeister liest keine Tastatureingaben, Passwörter oder Zwischenablagen und fordert keine Screenshots an. Gespeichert werden nur die Einstellungen. Die Anwendung erfasst keine Nutzungsdaten oder Telemetrie und benötigt keinen Netzwerkzugriff.

Mit dem Schließen des Fensters endet die Anwendung einschließlich ihrer Freigaben. Es gibt keinen Hintergrunddienst und keinen Autostart.

## Häufige Fragen

### Warum ist „Starten“ nicht verfügbar?

Für jeden Lauf muss das Tastenkürzel für Start und Stopp eingerichtet sein. Falls die Freigabe abgelehnt, die Taste entfernt oder die Freigabe beendet wurde, wähle im Abschnitt **Tastenkürzel** die Schaltfläche **Erneut versuchen**. Ein Neustart ist dafür nicht nötig.

### Warum wird eine feste Position nicht übernommen?

Eine feste Position gilt nur für ihren ausgewählten Bildschirm. Gib im KDE-Dialog denselben Bildschirm frei. Nach Änderungen an Auflösung oder Skalierung sowie bei einer fehlenden Bildschirmzuordnung muss die Position in Klickmeister geprüft und bestätigt werden.

### Wann werden die Einstellungen gespeichert?

Die Einstellungen werden beim Start eines Klicklaufs und beim Schließen gespeichert. Änderungen werden auch übernommen, wenn kein Lauf gestartet wurde. Schlägt das Speichern beim Schließen fehl, kannst du zur Anwendung zurückkehren oder **Ohne Speichern schließen** wählen. Beim Zurückkehren werden die Freigaben erneut angefragt: das Tastenkürzel sofort, die Maussteuerung beim nächsten Start.

### Funktioniert Klickmeister unter X11?

Klickmeister ist für KDE Plasma unter Wayland ausgelegt. X11 wird nicht unterstützt.

## Entwicklung

Cargo-Befehle bauen den aktuellen Checkout einschließlich lokaler Änderungen. `makepkg` verwendet den oben genannten, festgelegten Quellstand. Mit `makepkg --allsource --nodeps` lässt sich ein Quellpaket einschließlich des Projektarchivs erstellen und in einem anderen Verzeichnis bauen. Cargo-Abhängigkeiten werden beim Paketbau mit `cargo fetch --locked` geladen.

### Bauen und prüfen

```bash
cargo fmt --all -- --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
dbus-run-session -- cargo test --locked --all-targets -- --ignored
cargo build --locked --release
bash tests/qml-smoke.sh target/release/klickmeister
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QUICK_CONTROLS_STYLE=org.kde.desktop /usr/lib/qt6/bin/qmltestrunner -import tests/qml/mocks -input tests/qml
python tests/check_coordinate_accessibility.py # grafische Sitzung mit AT-SPI und PyGObject
bash tests/qml-wayland.sh # isolierter KWin mit drei Bildschirmen, benötigt kscreen-doctor
KLICKMEISTER_TEST_SCALE=1.5 bash tests/qml-wayland.sh
```

Die QML-Tests verwenden den KDE-Control-Stil und einen Controller-Testersatz. Die AT-SPI-Prüfung startet das Hauptfenster ohne Worker und prüft die zugänglichen Namen der Koordinatenfelder und ihrer Texteingaben. Die D-Bus-Tests prüfen den Rust-Worker gegen simulierte Portale. Dazu gehören Klickfolgen, Stopps, verzögerte Tastenkürzel-Signale, Sitzungsende und Fehler beim Loslassen einer Maustaste. Diese Tests erzeugen keine Mausklicks auf dem Desktop.

Tastenkürzel-Signale, die sich während eines Laufs angestaut haben, dürfen diesen noch stoppen, danach aber keinen neuen Lauf starten. Eine neue Betätigung nach dem Stopp startet wie gewohnt.

Echte KDE-Dialoge und die Zeigersteuerung auf physischen Bildschirmen werden zusätzlich in einer nativen Plasma-Wayland-Sitzung geprüft. Die Werkzeuge und Voraussetzungen dafür sind unter [tests/native](tests/native/README.md) dokumentiert.

Prüfe den Start-Countdown manuell an einem eigenen Testziel: Vor Ablauf der drei Sekunden darf kein Klick erfolgen. **Start abbrechen** und das Tastenkürzel müssen den Countdown ohne Klick beenden. Wiederhole die Prüfung mit bereits erteilter Freigabe. Starts per Tastenkürzel und mit fester Position müssen ohne Countdown beginnen.

GitHub Actions führt Formatierung, Clippy, Rust- und Portaltests, QML-Tests im KDE-Stil, Python-Tests sowie Desktop- und AppStream-Validierung aus. Danach folgen Release-Build und QML-Smoke-Test. Ein separater Job prüft die QML-Oberfläche unter einem virtuellen KWin mit drei Bildschirmen. Beide Jobs verwenden Arch-Linux-Container und die Cargo-Lockdatei; native Tests mit echten KDE-Dialogen bleiben eine manuelle Prüfung.

### QML-Sprachserver

Führe zuerst `cargo build --locked` und danach `bash scripts/setup-qmlls.sh` aus. Das Skript ermittelt das aktive Cargo-Buildverzeichnis, auch bei `CARGO_TARGET_DIR` oder `build.target-dir`, und schreibt die von Git ignorierte `.qmlls.ini`. Nach einem Wechsel des Buildverzeichnisses muss das Skript erneut ausgeführt werden. Python 3 ist erforderlich.

`python tests/check_qmlls_checkout.py` prüft den committeten Stand in einem frischen Checkout mit anderem Pfad und fragt die `AppController`-Eigenschaften direkt beim QML-Sprachserver ab.

### Desktop-Integration

Der Qt-Desktop-Dateiname lautet `io.github.jerry0205.klickmeister` und entspricht der installierten `.desktop`-Datei. Der QML-Smoke-Test prüft diesen Wert. Die [Portal-Anwendungs-ID](https://flatpak.github.io/xdg-desktop-portal/docs/api-reference) wird für die separaten D-Bus-Verbindungen aus dem Startkontext bestimmt. Eine direkt gestartete Entwicklungs-Binärdatei kann deshalb in KDE-Freigabedialogen anders benannt werden als die über das Anwendungsmenü gestartete Anwendung.

Details zum Aufbau und zu Sicherheitsentscheidungen stehen in [ARCHITECTURE.md](ARCHITECTURE.md) und [SECURITY_REVIEW.md](SECURITY_REVIEW.md).

## Lizenz

Klickmeister ist freie Software unter der [MIT-Lizenz](LICENSE).
