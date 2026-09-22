# Korrekturen aus OFFENE_FIXES.md – erledigt

Stand: 22.09.2026. Grundlage war die Aufgabenliste aus Arbeitsbaum
`t3code-643a0acf` zum Basiscommit `ab35282e17bafe93405fb427982b1d2c8531e08d`.

- [x] Blockierende Screenshot-Erstfreigabe durch einen nativ geprüften interaktiven
  Portal-Ablauf umgangen. Kein Portal-Patch erforderlich für diesen App-Ausweichweg.
- [x] Ursache im Portal-Quellcode geprüft; Systemdienst selbst bleibt unverändert.
- [x] Begrenzte Wartezeit, Auswahl ohne Lupe und explizite Anfragebereinigung erhalten.
- [x] Timeout-Hinweis erklärt „Deny“/„Verweigern“ für einen verbliebenen KDE-Dialog.
- [x] Unbeantwortete Anfrage, Ablehnung, Zustimmung/Lupe, unabhängiger Portal-Client,
  App-Schließen, anschließende Klicks und Start/Stop mit echten KDE-Dialogen geprüft.
- [x] Verspätete Antworten/geschlossene Picker weiter durch Regressionstests abgesichert.
- [x] Korrigierte native Hilfsfunktionen im Repository gesichert: dauerhaftes
  Klickziel, PID-gerichtetes App-Schließen, sichtbare ComboBox-Einträge,
  fixierte und vor dem Start geprüfte Koordinaten.
- [x] Zielausfall führt zum unmittelbaren Beenden der eigenen Test-App;
  automatisch mit laufendem Ersatz-Erzeuger und nativ bei ruhendem Klicker geprüft.

Nachweise und Prüfgrenzen: [Portal-Fix-Bericht](tests/PORTAL_FIX_REPORT.md).
Wiederverwendung: [native Testwerkzeuge](tests/native/README.md).

Der upstream nichtinteraktive Portal-Pfad wurde nicht repariert. Klickmeister
verwendet ihn für die Lupe nicht mehr. Physische Hotkey-Betätigung, weitere echte
Monitore und längerer Dauerbetrieb bleiben außerhalb dieser Regression.
