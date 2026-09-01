# Klickmeister

Klickmeister ist ein kleiner nativer Auto Clicker für KDE Plasma 6 unter Wayland. Er verwendet ausschließlich freedesktop.org-Portale, läuft als einzelner Prozess und installiert weder Daemon noch Service noch Autostart.

## Warum Rust + Qt 6/Kirigami?

Rust übernimmt Validierung, Zustandsautomat, Scheduler und Portalzugriffe. Qt 6/Kirigami liefert unter Plasma die native Breeze-Darstellung, Systemschrift sowie automatische Hell-/Dunkelfarben. CXX-Qt verbindet beide ohne WebView, Electron, Chromium oder Node.js.

## Funktionen

- 10 ms bis 24 Stunden Intervall; hartes Limit von 100 CPS
- linke, rechte oder mittlere Maustaste
- Einfach- und Doppelklick
- bis zum Stoppen oder feste Anzahl
- aktuelle Cursorposition oder feste Position
- Wayland-konformer Vollbild-Positionspicker mit Monitorauswahl
- globaler Start/Stop-Hotkey, bevorzugt Pause
- Stop-Button, Hotkey und vollständiger Shutdown beim Fensterschließen
- kleine TOML-Konfiguration ohne Nutzungsdaten

## Portal-Berechtigungen

Beim ersten Start bindet KWin über das GlobalShortcuts-Portal den Stop-Hotkey. Ohne erfolgreichen globalen Hotkey lässt sich der Klicker aus Sicherheitsgründen nicht starten.

Beim ersten Klickstart fragt KWin nach Zeigersteuerung (`POINTER`). Damit kann die Anwendung Zeiger-Buttonereignisse senden; sie erhält keine Tastatur-, Clipboard- oder Passwortdaten und zeichnet keine Eingaben auf.

Für „Feste Position“ muss zusätzlich genau ein Monitor im ScreenCast-Dialog gewählt werden. Das Portal liefert dadurch zwar einen PipeWire-Streamhandle und die logische Monitorgröße, Klickmeister öffnet den PipeWire-Stream jedoch nicht und kann daher keine Bildframes lesen. Die Freigabe wird allein als Referenz für absolute Zeigerkoordinaten benötigt. Wähle denselben Monitor, auf dem der Vollbildpicker verwendet wurde.

Die Berechtigungen gelten nur während des laufenden Anwendungsprozesses. Beim Schließen werden alle Sitzungen geschlossen.

Spezifikationen: [RemoteDesktop](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.RemoteDesktop.html), [GlobalShortcuts](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html), [ScreenCast](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.ScreenCast.html).

## Abhängigkeiten

Laufzeitpakete auf Arch/CachyOS:

```text
qt6-base qt6-declarative kirigami
xdg-desktop-portal xdg-desktop-portal-kde
```

Buildpakete:

```text
rust cargo clang lld pkgconf qt6-tools
```

Rust-Crates sind in `Cargo.lock` mit Version und Prüfsumme fixiert. Die direkten Crates und Zwecke:

- `cxx`, `cxx-qt`, `cxx-qt-lib`: Qt-6-/QML-Brücke
- `ashpd`: typisierte XDG-Portal-Aufrufe
- `tokio`, `futures-util`: monotoner Timer, begrenzte Kanäle und D-Bus-Signalstreams
- `serde`, `toml`: Konfiguration
- `thiserror`: strukturierte Fehler

Keine Dependency wird für Netzwerkkommunikation der Anwendung verwendet.

## Bauen

```fish
cargo build --locked --release
```

Direkt aus dem Checkout als Arch-Paket:

```fish
makepkg -si
```

Das PKGBUILD ermittelt bei jedem Aufruf mit `nproc` die verfügbaren logischen CPU-Threads und verwendet automatisch die Hälfte davon als parallele Cargo-Jobs, mindestens jedoch einen. Ein Rechner mit 12 Threads baut daher mit 6 Jobs. Diese Einstellung betrifft nur das einmalige Kompilieren, nicht die Laufzeit der Anwendung.

Build und Pakettests verwenden dasselbe Release-Profil, sodass Abhängigkeiten nicht ein zweites Mal im Debug-Profil kompiliert werden. Das Release-Profil verzichtet bewusst auf LTO und verwendet 16 Codegen-Einheiten: Die Anwendung bleibt optimiert und klein, während Erst- und Paket-Build deutlich schneller fertig werden.

Das lokale Entwicklungs-PKGBUILD baut den aktuellen Checkout. `cargo fetch --locked` lädt ausschließlich checksummengeprüfte Rust-Quellen aus `Cargo.lock`; es lädt keine fremden Programm-Binärdateien. Für eine veröffentlichte Distribution sollte ein signierter Source-Tarball verwendet und im PKGBUILD mit BLAKE2-Prüfsumme fixiert werden.

Nach der Paketinstallation erscheint „Klickmeister“ im KDE-Anwendungsmenü.

## Entwicklung und Prüfung

```fish
cargo fmt --all -- --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
cargo build --locked --release
bash tests/qml-smoke.sh target/release/klickmeister
cargo tree --locked
cargo audit
```

`cargo audit` gehört zum separaten Paket/Tool `cargo-audit` und wird nicht automatisch installiert.

## Konfiguration

Es wird nur folgende Datei geschrieben:

```text
$XDG_CONFIG_HOME/klickmeister/config.toml
# sonst ~/.config/klickmeister/config.toml
```

Enthalten sind nur Intervall, Maustaste, Klicktyp, Wiederholung, feste Koordinaten und Hotkey-Anzeige. Es gibt keine Statistiken, Historie oder Telemetrie.

## Bekannte Wayland-Grenzen

- Vor dem Öffnen des Vollbild-Positionspickers wird der gewünschte Monitor ausgewählt. Wayland erlaubt Anwendungen nicht, den globalen Cursor außerhalb eigener Oberflächen heimlich abzufragen.
- Die festen X/Y-Koordinaten beziehen sich auf den im Portal ausgewählten Monitor, nicht auf einen ungeschützten globalen Desktop-Koordinatenraum.
- Die Portal-Dialoge können nicht von der Anwendung umgangen werden. Das ist ein Sicherheitsmerkmal.
- Das Projekt besitzt absichtlich kein X11-/`xdotool`-Fallback.

Weitere Details stehen in [ARCHITECTURE.md](ARCHITECTURE.md) und [SECURITY_REVIEW.md](SECURITY_REVIEW.md).
