# Geräteprüfung auf CachyOS / Plasma Wayland – 13.–14.09.2026

## Stand und Ergebnisgrenze

Geprüft wurde Version **0.1.1**, ausgehend von Commit
`cc1e17d78a6ca283327bd248145883157ec90e7b`, mit den unten beschriebenen lokalen
Korrekturen in diesem Arbeitsbaum. Der Arbeitsbaum war zu Beginn sauber;
es wurden keine AGENTS.md-Dateien im Projekt oder in seinen übergeordneten
Verzeichnissen gefunden. `git fetch origin` und `git pull --ff-only origin main`
ergaben „Already up to date“. Vorhandene Projektänderungen aus der vorherigen
Prüfung sind in diesem Commit enthalten und wurden beibehalten.

**Die automatischen Prüfungen und die unten aufgeführten nativen Klicktests
bestehen. Die Geräteprüfung ist wegen eines reproduzierten Screenshot-Portalfehlers
nicht uneingeschränkt bestanden.** Die zunächst gesperrte Sitzung wurde vom
Benutzer regulär entsperrt. Anschließend wurden das neu gebaute Release-Programm,
die echten KDE-Portale und tatsächliche Mausereignisse geprüft. Nicht verfügbare
Hardwarebedingungen und auf Benutzerwunsch ausgelassene physische Hotkey-Tests
werden unten ausdrücklich getrennt aufgeführt.

Endgültige Release-Binärdatei: SHA-256
`63198218fd27ec87847ae655f3be7b04b5d0788e64c4931615e4c3cf017876c8`.
Der Basiscommit allein beschreibt den geprüften Stand nicht vollständig: Die
nachfolgend beschriebenen Korrekturen gehören dazu. Eine Änderungskopie vom
Abschluss der Geräteprüfung liegt bei den Testartefakten.

## Tatsächliche native Umgebung

| Merkmal | Festgestellt |
| --- | --- |
| Betriebssystem | CachyOS, Kernel 7.2.4-3-cachyos, x86_64 |
| Sitzung | KDE, Wayland, `wayland-0`, nativer Benutzer-Session-Bus |
| Plasma / KWin | 6.7.5 / 6.7.5 |
| Qt | 6.11.2 |
| Kirigami / KDE-Control-Stil | 6.30.0 / qqc2-desktop-style 6.30.0 |
| Rust / Cargo | 1.98.1 / 1.98.1 |
| Portal-Frontend / KDE-Backend | xdg-desktop-portal 1.22.1-2.1 / xdg-desktop-portal-kde 6.7.5-1.1 |
| Physischer Monitor | ein aktivierter interner Ausgang eDP-1 |
| Auflösung und Skalierung | 2880 × 1800 bei 120 Hz; 160 %; logisch 1800 × 1125, Ursprung (0, 0) |
| Compositor-Grafik | Intel Graphics (LNL), Mesa 26.2.2, OpenGL 4.6, EGL |
| Laufende Klickmeister-Instanzen vor / nach dem Test | keine / keine |

Rust, Cargo, Clang, LLD, pkgconf, Qt Base/Declarative/Tools, Kirigami, der
KDE-Control-Stil und beide Portal-Pakete sind installiert. `ldd` meldet keine
fehlende Bibliothek. Der Wayland-Plattformtreiber gehört auf diesem System zu
`qt6-base`; ein eigenständiges Paket `qt6-wayland` ist hier nicht installiert.
Der laufende Desktop, seine Monitoranordnung und Skalierung wurden nicht geändert.

Der echte Portal-Dienst wurde per D-Bus introspektiert. RemoteDesktop v2
(`AvailableDeviceTypes=7`), ScreenCast v5 (`AvailableSourceTypes=7`,
`AvailableCursorModes=7`), GlobalShortcuts v2 und Screenshot v2 sind vorhanden.
Die installierte KDE-Portal-Konfiguration ordnet diese Schnittstellen KDE zu.
Die nachfolgenden nativen Fälle belegen zusätzlich erfolgreiche RemoteDesktop-,
ScreenCast- und Screenshot-Freigaben sowie die Registrierung von GlobalShortcuts.

## Automatisch geprüft

| Prüfung am endgültigen Quellstand | Ergebnis |
| --- | --- |
| `cargo fmt --all -- --check` | bestanden |
| `cargo clippy --locked --all-targets -- -D warnings` | bestanden |
| `dbus-run-session -- cargo test --locked --all-targets -- --include-ignored` | 24 Rust-Unit-Tests, 1 Screenshot-D-Bus-Test und 1 Worker-D-Bus-Integrationstest bestanden |
| `cargo build --locked --release` | bestanden |
| `bash tests/qml-smoke.sh target/release/klickmeister` mit Test-Konfigurationsverzeichnis | bestanden; echter eingebetteter Controller, Worker im Smoke-Modus nicht gestartet |
| Neu gebautes Programm: `QT_QPA_PLATFORM=wayland … --smoke-test` | Exit 0; QML-Hauptfenster angelegt, keine visuelle Bedienprüfung |
| QML auf dem nativen Wayland-Desktop bei 160 %, KDE-Stil | 35 bestanden, 0 fehlgeschlagen |
| QML offscreen, Software-Rendering, `org.kde.desktop` | 35 bestanden, 0 fehlgeschlagen |
| Isolierter KWin, drei virtuelle Ausgänge, jeweils 100 % | 35 bestanden, 0 fehlgeschlagen |
| Isolierter KWin, drei virtuelle Ausgänge, jeweils 150 % | 35 bestanden, 0 fehlgeschlagen |
| Isolierter KWin, drei virtuelle Ausgänge, jeweils 160 % | 35 bestanden, 0 fehlgeschlagen |
| Isolierter KWin, gemischt 100 % / 150 % / 160 % | 35 bestanden, 0 fehlgeschlagen |
| `makepkg --noconfirm`, einschließlich `check()` | Paket 0.1.1-1 erfolgreich gebaut; reguläre Release-Tests bestanden, D-Bus-Tests dort absichtlich ignoriert und separat auf privatem Bus ausgeführt |
| Paketinhalt und Smoke-Test der entpackten Paket-Binärdatei | bestanden |
| `desktop-file-validate`, `appstreamcli validate --no-net` | bestanden |
| Shell-Syntax und `git diff --check` | bestanden |

Die QML-Zahlen enthalten Initialisierung und Abschluss. Die Durchläufe wiederholen
dieselben Fälle unter unterschiedlichen Bedingungen. Hauptfenstertests verwenden
den Controller-Testersatz; Positionswähler und Monitorzuordnung sind echte
QML-Komponenten. Geprüft werden unter anderem direkt eingetippte Werte ohne
Fokuswechsel, deaktivierte Einstellungen während eines Laufs, Monitoridentität,
Auswahl auf jedem virtuellen Ausgang, Randkoordinaten, Pfeiltasten mit und ohne
Umschalt, fixiertes Ziel nach Linksklick, Enter, Escape, zusätzlich Rechtsklick,
Vorschau, Fenstergeometrie/Maximierung und Screenshot-Fallback/Timeout/verspätete
Antworten. Die Lupenbilder dieser Tests sind synthetisch.

Die virtuellen Ausgänge liegen bei (0, 1080), (1920, 1080) und (-1920, 0), ohne
Überlappung. Gemischte Skalierung ist reproduzierbar mit:

```bash
KLICKMEISTER_TEST_SCALE_1=1.5 KLICKMEISTER_TEST_SCALE_2=1.6 bash tests/qml-wayland.sh
```

Der Worker-Test verwendet den echten Rust-Worker gegen simulierte Portale auf
einem **privaten** Session-Bus. Er prüft drei Maustasten, Einzel-/Doppelklick,
begrenzte Zyklen, Press/Release einschließlich Release-Fehler, Stop-Befehl,
Hotkey-Signal, doppelte Starts, Hotkey-Sitzungsende, Monitorzuordnung,
Abbruch und Neustart nach widerrufener Maussitzung. Bei drei Doppelklickzyklen
werden sechs Klicks und zwölf Button-Ereignisse erwartet. Nach bestätigtem Stop
kommen keine weiteren Testportal-Button-Ereignisse an.

GCC 16 gibt beim Kompilieren Warnungen aus Qt/CXX-Qt-Headern
(`-Wsfinae-incomplete`) aus. Diese verhinderten weder Build noch Tests; die
Rust-Clippy-Prüfung mit `-D warnings` besteht. Einzelne isolierte QML-Durchläufe
melden beim Aufräumen eine nicht mehr aktive Testfensterfläche; kein Testfall
schlug dadurch fehl.

## Neu reproduzierte Fehler und Korrekturen

### 1. Offene Mausanfrage blieb nach Stop bestehen

Reproduktion: Das Testportal verzögert die Antwort auf RemoteDesktop.Start;
der Worker erhält Stop. Erwartet sind Session.Close und keine späteren Klicks.
Vorher wurde Running(false) gemeldet, ohne die Sitzung zu schließen. Die neue
Assertion scheiterte mit „Stop must close the pending RemoteDesktop session
before confirming it“.

Ursache: `JoinHandle::abort()` verwirft den Sitzungseigentümer, während ashpd
seine gemeinsame D-Bus-Verbindung weiterhin hält. Das Verwerfen einer
ashpd-Session ruft kein Session.Close auf.

Korrektur: RemoteDesktop und der zugehörige ScreenCast verwenden eine eigene
Verbindung. Ein Abbruchsignal lässt die Startaufgabe Session.Close und anschließend
die Verbindung bereinigen, jeweils mit begrenzter Wartezeit. Stop wartet darauf.
Auch eine unmittelbar zuvor erfolgreich abgeschlossene, inzwischen abgebrochene
Startaufgabe wird geschlossen. Der ursprüngliche Fehlerfall besteht anschließend,
einschließlich verspäteter Antwort und erfolgreichem Neustart.

### 2. Offene Hotkey-Anfrage blieb bei Shutdown bestehen

Reproduktion: BindShortcuts antwortet noch nicht; der Worker wird heruntergefahren.
Vorher scheiterte die neue Assertion „Shutdown must close a pending GlobalShortcuts
session“. Dieselbe Lebensdauerursache wie bei RemoteDesktop.

Korrektur: eigene Hotkey-Verbindung, kooperativer Abbruch und abgewartete
Bereinigung. Die Tests prüfen jetzt Shutdown während beider Freigabearten,
auch mit nicht antwortendem Session.Close. Sie prüfen ausdrücklich, dass der
D-Bus-Verbindungsname anschließend keinen Besitzer mehr hat und eine verspätete
Antwort keinen Lauf startet. Native RemoteDesktop-Dialoge verschwinden jetzt sowohl bei Stop als auch bei
Fenster-Schließen. Shutdown während einer noch offenen Hotkey-Registrierung ist
nur durch den privaten D-Bus-Test eindeutig belegt.

Gemessene Worker-Shutdown-Zeiten in diesem privaten D-Bus-Test:

| Ausstehende Anfrage | Session.Close antwortet | Session.Close hängt |
| --- | --- | --- |
| GlobalShortcuts | 1,63 ms | 1,002 s |
| RemoteDesktop plus eingerichteter Hotkey | 1,41 ms | 2,005 s |

Bei der letzten Zeile hängen beide Session.Close-Aufrufe; daher greifen zwei
Ein-Sekunden-Grenzen. Das sind reale Wartezeitmessungen des Test-Workers,
**keine nativen Stop-Reaktionszeiten oder Echtzeit-Klick-Dauertests**.

### 3. Isolierter KWin-Test hinterließ Portal-Hilfsprozesse

Nach den ursprünglichen Durchläufen blieben zwei KDE-Portal-Backendprozesse mit
Adressen der bereits beendeten privaten Session-Busse zurück. Außerdem konnte
das Aufräumen eines temporären Dokumentportal-FUSE-Verzeichnisses mit dessen
asynchronem Abbau kollidieren.

Korrektur im Testskript: eigene Prozessgruppe, begrenztes Beenden der gesamten
Testsitzung, getrennte XDG-Verzeichnisse bereits für den privaten D-Bus und
begrenztes Wiederholen der Verzeichnisbereinigung. Die abschließende komplette
Skalierungsmatrix besteht ohne übrig gebliebene Testprozesse oder diesen
Aufräumfehler. Der native Desktop-Portal-Dienst wurde nicht ersetzt oder beendet.

### 4. Gespeicherte Koordinaten wurden als 0 angezeigt

Native Reproduktion: gültige Konfiguration mit X=80, Y=400 starten. Die beiden
Eingabefelder zeigten 0, während der Controller die gespeicherten Koordinaten
verwendete und tatsächliche Klicks bei (80, 400) ankamen. Erwartet sind identische
Anzeige- und Zielkoordinaten.

Ursache: Die SpinBox begrenzt ihren Anfangswert, bevor die Monitorgröße bekannt
ist. Bei der Monitorinitialisierung bleibt der Controllerwert unverändert und
löst deshalb kein Änderungssignal aus. `syncMonitor()` synchronisiert jetzt
zusätzlich beide Anzeigen. Der neue QML-Regressionstest mit nichtnulligen
Anfangskoordinaten scheiterte vorher (0 statt 80) und besteht danach. Das neu
gebaute Programm zeigt nach Neustart tatsächlich 80 und 400; erneute native
Positionsauswahl und Klickmatrix bestehen.

## Mit echten KDE-Portalen und Mausereignissen geprüft

Das Testziel war ein eigenes Qt-Wayland-Vollbildfenster auf eDP-1. Es protokolliert
Press, DoubleClick und Release mit monotoner Nanosekundenzeit, Taste, lokalen und
globalen Koordinaten sowie verbleibendem Tastenstatus. Ein DoubleClick-Ereignis
zählt dabei als Press. Sämtliche Klickläufe trafen ausschließlich dieses Testziel,
überwiegend bei (80, 400); keine Produktivoberfläche wurde als Klickziel verwendet.

Die Oberfläche wurde über AT-SPI und einen separaten, regulär von KDE freigegebenen
RemoteDesktop-Testtreiber bedient. Dessen Tastatur-/Zeigerfreigabe gehört nur zum
Testwerkzeug, nicht zu Klickmeister. Portal-Zustimmung erfolgte durch Betätigung
der sichtbaren KDE-Schaltflächen; weder PermissionStore-Einträge auf „yes“ gesetzt
noch Portal-Dienste ersetzt. Der zuerst vom Benutzer bestätigte Hotkey „Pause“
wurde bei App-Neustarts von KDE übernommen. Eine physische Betätigung wurde auf
anschließenden ausdrücklichen Benutzerwunsch ausgelassen.

| Nativer Fall am neu gebauten Programm | Ergebnis |
| --- | --- |
| Fehlende Konfiguration | Standardwerte sichtbar, kein automatischer Klickstart |
| Unvollständige Konfiguration | Intervall 222 ms geladen, übrige Werte ergänzt |
| Ungültige Konfiguration (`interval_ms = "fast"`) | Verständlicher TOML-Konfigurationsfehler, sichere Standardwerte; nach UI-Korrektur erfolgreicher begrenzter Lauf |
| Einstellungen speichern und neu laden | Beim Start gespeicherte Werte und Pause nach Neustart wiederhergestellt; feste Koordinaten nach Korrektur auch richtig angezeigt |
| Echte Tastatureingabe ohne Fokuswechsel vor Start | Geänderte Intervalle, Anzahl und Klickvarianten tatsächlich verwendet und gespeichert |
| RemoteDesktop/ScreenCast eDP-1 freigeben | Logische Streamgeometrie 1800 × 1125 akzeptiert; erste drei linken Einzelzyklen bei 1 s genau sechs Ereignisse |
| Maustasten links/rechts/mitte × einfach/doppelt | Je drei Zyklen bei 100 ms: sechs bzw. zwölf Ereignisse, richtige Taste und vollständige Press-/Release-Paare |
| Intervalle 1000 / 100 / 20 / 10 ms | Begrenzte native Läufe bestanden; exakte Zykluszahlen |
| Aktuelle Cursorposition | Drei Zyklen am vorhandenen Zeigerort; sechs Button-Aufrufe, keine PointerMotion-Aufrufe im überwachten App-Verkehr |
| Stop während Lauf | Ca. 5,94 ms bei 1 s bzw. 6,95 ms bei 10 ms bis sichtbare Stop-Bestätigung; danach für 1,2 s bzw. 1 s keine weiteren Ereignisse |
| Zehn schnelle Start-/Stop-Folgen | Jeweils tatsächlichen Lauf und Stop bestätigt; keine späteren Ereignisse während der Nachbeobachtung |
| Stop während offener Mausfreigabe | Dialog, Request und ausstehende Maussitzung verschwinden, keine Klicks; erneuter Start möglich |
| Mausfreigabe verweigern, erneut starten und freigeben | Fehler ohne Klicks; anschließend genau drei erfolgreiche Zyklen |
| Hauptfenster während Lauf schließen | Prozess endet regulär; keine weiteren Ereignisse im Nachbeobachtungsfenster |
| Hauptfenster bei offener Mausfreigabe schließen | Prozess endet nach ca. 0,207 s inklusive Teststeuerung; Dialog und Sitzungen verschwinden, keine Klicks |
| Positionswähler | Linksklick fixiert, Bewegung ändert Ziel danach nicht; Pfeil +1, Umschalt+Pfeil +10; Enter übernimmt, Escape/Rechtsklick verwerfen |
| Ränder auf eDP-1 | (0, 0) und (1799, 1124), Pfeilkorrektur bleibt innerhalb der Grenzen |
| Vorschau / Start während Auswahl | Vorschau verändert keine Koordinate; Start-Aktion bei offener Auswahl erzeugt keine Zielereignisse |
| Hauptfensterrückkehr | Normale Geometrie (636, 182, 528 × 760) bleibt erhalten; maximiert vorher/nachher identische KWin-Geometrie 1800 × 1124,75 |
| Screenshot-Zustimmung | Reguläre KDE-Freigabe erfolgreich; sichtbare 4×-Lupe zeigt den Ring des Testziels zentriert bei (80, 400) |
| Screenshot-Verweigerung | Auswahl ohne Lupe funktioniert; Escape beendet sie |
| Unbeantwortete Screenshot-Erstfreigabe | App zeigt nach 3 s Auswahl ohne Lupe; **KDE-Dialog bleibt offen und weitere Portal-Aufrufe blockieren**, siehe unten |

Die Stop-Zeitmessung umfasst die automatisierte UI-Betätigung und Statusabfrage;
sie ist keine garantierte maximale Stop-Latenz. Ein früher Versuch schneller
Start-/Stop-Betätigung las noch den alten Stop-Status vor dem Start. Der korrigierte
Test wartet auf den tatsächlich sichtbaren Laufzustand vor dem Stop. Ebenso wurden
offene KDE-Kombomenüs und nicht nutzeräquivalente AT-SPI-Value-Setter im Testtreiber
korrigiert; daraus abgeleitete Fehlversuche wurden nicht als Produktfehler gewertet.

### Echtzeit-Dauerbetrieb und Verzögerung

- **12.000 Einzelklickzyklen, 24.000 Button-Ereignisse**, alle vollständig am
  Testpunkt, Intervall 10 ms. Zwischen erstem und letztem Zyklus
  **119,991903456 s**, entsprechend **100,0032 Zyklen/s** über 11.999 Abstände.
- CPU-Verbrauch im Messfenster: **4,12 % eines CPU-Kerns**. RSS: anfangs
  **160.412 KiB**, am Ende **160.452 KiB**, Minimum/Maximum ebenfalls diese Werte.
  Keine stetige Zunahme in diesem begrenzten Lauf; keine Aussage über Stundenbetrieb.
- Nach begrenztem Laufende eine Sekunde lang keine weiteren Ereignisse; keine
  Hinweise auf einen zweiten Scheduler. Zielereignisse und Ressourcenstichproben
  sind getrennt protokolliert.
- Separater Lauf: 40 Zyklen bei 20 ms, App für 250 ms per SIGSTOP angehalten und
  garantiert per SIGCONT fortgesetzt. Gemessene Klicklücke 266,02 ms; folgende
  Abstände 24,29 / 20,04 / 19,26 / 20,62 / 20,81 ms. Keine Nachholbursts,
  abschließend genau 80 Ereignisse.

Diese Messungen sind echte Laufzeit-/Mausmessungen. Die vorhandene zehnminütige
Schedulerprüfung bleibt dagegen eine Simulation.

## Verbleibender reproduzierter Desktopfehler

**Offene Screenshot-Erstfreigabe wird auf dieser Portal-Version nicht bereinigt.**
Reproduktion: Screenshot-Berechtigung für die App noch nicht gesetzt, Lupe
aktivieren, Positionsauswahl starten und den KDE-Dialog länger als drei Sekunden
unbeantwortet lassen. Erwartet: Auswahl ohne Lupe und geschlossener Request/Dialog.
Tatsächlich: Picker-Fallback erscheint korrekt und die separate App-Verbindung
verschwindet, aber Request und KDE-Dialog bleiben bestehen. Ein unabhängiger,
bereits freigegebener Testtreiber erhält anschließend bei Portal-Eingabeaufrufen
Timeouts. Reguläres „Deny“ am verbliebenen Dialog löst die Blockade und entfernt
Request sowie verwaiste Sitzung. Kein Klicklauf war dabei aktiv.

Die eingegrenzte Ursache liegt im installierten xdg-desktop-portal 1.22.1:
Die nichtinteraktive Screenshot-Erstfreigabe hält während eines synchronen
AccessDialog-Aufrufs den Request-Lock; Request.Close und die Verarbeitung eines
Client-Verbindungsabbruchs benötigen denselben Lock. Das erklärt die beobachtete
Blockade; es ist eine aus Quellcode und Messung abgeleitete Ursachenanalyse, kein
Test eines gepatchten Portal-Dienstes. Quellen:
[screenshot.c, Version 1.22.1](https://github.com/flatpak/xdg-desktop-portal/blob/1.22.1/src/screenshot.c)
und [xdp-request.c, Version 1.22.1](https://github.com/flatpak/xdg-desktop-portal/blob/1.22.1/src/xdp-request.c).

Klickmeister kann die App-seitige Wartezeit begrenzen, aber nicht zuverlässig einen
im Portal blockierten Dialog schließen. Der Systemdienst wurde nicht gepatcht oder
neu gestartet; die Sicherheitsgrenzen und das Eingabebackend der App bleiben
unverändert. Erfolgreiche Zustimmung vor dem Timeout und Auswahl mit abgeschalteter
Lupe funktionieren. Der offene Befund verhindert ein uneingeschränktes
„fertig getestet für dieses Gerät“.

## Nicht nativ nachgewiesen / nicht verfügbar

- Physischer globaler Hotkey bei fremdem Fokus, Wechsel auf eine andere Taste,
  Entfernen des Hotkeys und Schließen einer noch offenen Hotkey-Registrierung:
  Benutzer wünschte ausdrücklich Code-/Testprüfung statt weiterer Hotkey-Bedienung.
  Registrierung und Wiederherstellung von Pause sind nativ belegt; Aktivierung,
  aktuelle Einstellungen beider Startpfade, Auswahl-Sperre und Sitzungsende durch
  Worker-/QML-Tests, nicht durch physische Hotkey-Ereignisse.
- Widerruf einer bereits freigegebenen Maussitzung und anschließende erneute
  Freigabe: durch Worker-Integrationstest belegt, nicht nativ widerrufen.
- Zweiter physischer Monitor, falscher im Dialog gewählter Monitor, gemischte
  physische Skalierung, Abziehen, Umordnen und Geometriewechsel. Nur eDP-1 vorhanden;
  keine störende Desktop-Umstellung durchgeführt. Die virtuelle Matrix ersetzt
  diese Hardwarefälle nicht.
- Sämtliche numerischen Maximalwerte wurden durch automatische Tests, nicht
  zusätzlich als native Klickläufe geprüft. Ein Mindestintervall von 10 ms und
  beide nativen Monitorränder sind tatsächlich geprüft.
- Späte Screenshot-Antworten und Schließen während einer offenen Screenshot-Anfrage
  sind automatisch geprüft. Native vollständige Dialogbereinigung ist wegen des
  oben reproduzierten Portalfehlers ausdrücklich nicht bestanden; ein verspätetes
  Wiederöffnen des Pickers wurde nicht als bestandener nativer Fall verbucht.
- Dauerbetrieb über zwei Minuten hinaus und andere Grafiktreiber/Hardware.
- Systemweite Arch-Paketinstallation per pacman. Der endgültige Quellstand wurde
  mit makepkg einschließlich Release-Tests gebaut; Inhalt, Metadaten und Smoke-Test
  des daraus entpackten, beim Paketbau gestrippten Programms bestehen.

## Bereinigung und Artefakte

Alle selbst gestarteten App-, Eingabetreiber-, Monitor- und Testzielprozesse wurden
beendet. Es bleiben nur die zuvor vorhandenen nativen KWin-/Portalprozesse; keine
Test-Requests oder -Sitzungen im nativen Portal. Eine persönliche
`~/.config/klickmeister/config.toml` existierte zu Beginn nicht und wurde nicht
angelegt. App- und QML-Tests verwendeten getrennte Konfigurationsverzeichnisse,
die nachher entfernt wurden. Monitoranordnung und Skalierung blieben unverändert.

Der für AT-SPI vorübergehend aktivierte Status `org.a11y.Status.IsEnabled` wurde
auf seinen ursprünglichen Wert `false` zurückgesetzt; ScreenReaderEnabled blieb
unverändert. Ausschließlich der im Screenshot-Test neu entstandene PermissionStore-
Eintrag für `t3code` wurde entfernt (ursprünglich nicht gesetzt); keine Freigabe
wurde über diesen Speicher erteilt. Die vom Benutzer bestätigte KDE-Hotkeyzuordnung
Pause bleibt erhalten. Wegen der Startumgebung ordnet KDE sie unter **T3 Code**
(`t3code`, Aktion `toggle-clicking`) zu; nach App-Ende gibt es dazu keine aktive
Portal-Sitzung.

Build-Artefakte liegen in `target/`, Testprotokolle, Hilfsskripte und die erzeugten
Pakete unter `/tmp/klickmeister-device-b60e7a62/`. Der Unterordner `native/`
enthält unter anderem `results.jsonl`, `mouse-events.jsonl`,
`resource-samples.json`, die finalen automatischen Testlogs und den dokumentierenden
Lupenscreenshot. Protokollierte Restore-Tokens wurden vor Abschluss redigiert.
Aktive Testeinstellungen, Socket und entpackte Paket-Testumgebung wurden entfernt.
Zum Abschluss der Geräteprüfung waren die Änderungen noch nicht committed oder
gepusht. Die anschließende Veröffentlichung als PR wurde vom Benutzer beauftragt.

---

# Archiv: frühere Prüfung auf Ubuntu / XFCE

Die folgende Dokumentation beschreibt den früheren Containerdurchlauf und
ist **keine Beschreibung der oben geprüften nativen CachyOS-Sitzung**.

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
