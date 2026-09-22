# Screenshot-Portal: native Regression vom 22.09.2026

Die Korrektur umgeht den blockierenden Erstfreigabe-Pfad über
`Screenshot(interactive=true)`. Sie ist auf dem betroffenen Gerät mit
**xdg-desktop-portal 1.22.1-2.1 und KDE-Backend 6.7.5-1.1** nativ nachgewiesen.
Der Systemdienst wurde weder gepatcht noch neu gestartet. Die vorherige
Ursachenanalyse bleibt für **nichtinteraktive** Erstfreigaben gültig.

## Ursache und Änderung

In [screenshot.c (1.22.1)](https://github.com/flatpak/xdg-desktop-portal/blob/1.22.1/src/screenshot.c)
hält `handle_screenshot_in_thread_func` den Request-Lock und ruft nur für
`interactive=false` die synchrone erste Access-Freigabe auf. Das Schließen und die
Verbindungsbereinigung brauchen denselben Lock. Mit `interactive=true` entfällt
dieser Aufruf; stattdessen öffnet das KDE-Backend seinen asynchronen,
[explizit schließbaren ScreenshotDialog](https://github.com/KDE/xdg-desktop-portal-kde/blob/v6.7.5/src/screenshot.cpp).

Die App behält die eigene D-Bus-Verbindung, Request.Close, die begrenzte Bereinigung,
den 30-s-Rust-Timeout und den früheren **3-s-QML-Fallback** bei. Im Timeout-Hinweis
steht zusätzlich, wie ein gegebenenfalls übrig gebliebener alter Access-Dialog
über „Deny“/„Verweigern“ geschlossen wird. Eine Änderung nur der Zeitgrenzen ist
nicht Bestandteil dieses Fixes.

Der interaktive Ablauf erfordert in KDE „Vollbild“, „Übernehmen“/„Aufnehmen“, dann
„Speichern“ innerhalb der Wartezeit. Teilbilder sind keine geeignete Grundlage
für die Lupe; die vorhandene Prüfung der Bildproportionen bleibt aktiv. Die kurze
Wartezeit bleibt eine Bediengrenze. Sie wurde gemäß bestehendem Fallback beibehalten.

## Nachweise

CachyOS, echte Plasma-Wayland-Sitzung, ein Monitor eDP-1, logisch 1800 × 1125,
Skalierung 160 %. Eigenes Vollbild-Testziel, gesonderter freigegebener
RemoteDesktop-Testtreiber. Keine erzwungenen PermissionStore-Einträge.
Alle Button-Ereignisse wurden am Testziel aufgezeichnet.

Reproduzierbarer Lauf:
`python tests/native/run.py tests/native/portal_cases.py`.
Vollständige lokale Artefakte: `/tmp/klickmeister-native-84jf_pzd/`.
Die wichtigen Belege sind im Repository gesichert:
[Ergebnisse](native/evidence/portal-results.jsonl),
[echter KDE-Dialog](native/evidence/screenshot-dialog.png),
[echte Lupe am Testkreuz](native/evidence/magnifier.png).

| Fall | Ergebnis |
| --- | --- |
| Unbeantworteter Screenshot-Dialog | nach 3-s-Fallback geschlossen; Auswahl ohne Lupe |
| Unabhängiger bereits freigegebener Portal-Client | antwortet während des Dialogs und nach Timeout/Ablehnung/Shutdown |
| Screenshot ablehnen | Auswahl ohne Lupe benutzbar, Escape beendet sie |
| Screenshot rechtzeitig bestätigen | echtes Bild; 4×-Lupe visuell am Kreuz bei (80, 400) geprüft |
| App bei offener Screenshot-Anfrage schließen | Prozess und Dialog verschwinden, ca. 249 ms inklusive Teststeuerung |
| Klicks nach Fehlerfällen | drei Zyklen mit sechs passenden Button-Ereignissen |
| Start/Stop nach Fehlerfällen | Stop bestätigt, danach 300 ms ohne weiteres Ereignis |
| Links/rechts/mitte × einfach/doppelt | je drei Zyklen; 6 bzw. 12 Ereignisse und richtige Koordinaten |
| Alt+F4 am Testziel | Ziel bleibt sichtbar |
| Verspätete Antworten | bestehende QML-Tests: geschlossener Picker bleibt geschlossen, alte IDs werden ignoriert |

Der separate native Ausfalltest `target_loss.py` beendet absichtlich das echte
Testziel bei ruhendem Klicker. Der Starter erkannte den Ausfall und beendete alle
eigenen Prozesse mit Fehlerstatus (`/tmp/klickmeister-native-ep4269b8/`, anschließend
alle PIDs geprüft). Vier Wächter-Regressionstests prüfen zusätzlich einen laufenden
Ereigniserzeuger, verschwundenes Ziel und Szenariofehler sowie mitbeendete Kindprozesse ohne reale Desktop-Klicks.
Die Sichtbarkeitsprüfung ist begrenzt, aber keine Echtzeitgarantie gegen jeden
zusätzlichen Klick bei einem abrupten Prozessausfall.

## Automatische Prüfungen

- `cargo fmt --all -- --check`: bestanden.
- `cargo clippy --locked --all-targets -- -D warnings`: bestanden.
- `dbus-run-session -- cargo test --locked --all-targets -- --include-ignored`:
  25 Unit-Tests inklusive Screenshot-D-Bus-Test, 1 Worker-Integrationstest bestanden.
- Release-Build und `tests/qml-smoke.sh`: bestanden.
- QML offscreen und isolierter KWin mit drei virtuellen Monitoren: jeweils
  35 bestanden, kein Fehler. Synthetische Bilder nur in diesen QML-Tests.
- `python -m unittest discover -s tests/native -p test_guard.py`: 4 bestanden.

Qt/CXX-Qt-Headerwarnungen bleiben unverändert. Physischer Hotkey, weitere echte
Monitore, Stundenbetrieb und Paketinstallation wurden für diesen Fix nicht neu
geprüft. Frühere fehlgeschlagene Teststeuerungsversuche sind keine Erfolgsnachweise.
