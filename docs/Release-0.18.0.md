# Netzblick 0.18.0 – Prüfen und Entscheiden

- Neuer Prüfassistent mit fester Reihenfolge, nachvollziehbaren Prüfgründen und einer ausdrücklich angezeigten Momentaufnahme. Als geprüft werden nur die gezeigten Ziele und gezählten Blockversuche bestätigt; neue Beobachtungen bleiben offen.
- Bis zu 50 lokal gespeicherte Favoriten mit Programmsymbol, Ampel, zeitweiser Sperre/Freigabe und Restzeit. Inaktive Favoriten bleiben auffindbar.
- Regelvorschau vor Programm- und Einzelregeländerungen: passende beobachtete Ziele, Netzblick-Regeln davor/danach, entfernte/ersetzte Regeln und Reichweite. Der Dienst lehnt Änderungen ab, wenn sich die Konfiguration seit der Vorschau geändert hat. Unbekannte Verbindungsrichtungen werden nicht geraten.
- Lokal gespeicherter Zeitstrahl je Programm für beobachtete Sockets/Ziele, gezählte Blockversuche, bestätigte Programm-/Einzelregeländerungen, Prüfungen und Erfassungshinweise. Maximal 400 Ereignisse für alle Programme zusammen; älteste Einträge entfallen.

## Grenzen

Die Vorschau berechnet nur Netzblicks Dienstregeln für vorhandene Beobachtungen. Sie simuliert keine fremden Windows-/Sicherheitsfilter, keine bestehende Verbindung und keinen zukünftigen Verkehr. Eingehend gilt der lokale Dienstport. Hostprozess-Regeln können mehrere Dienste/Instanzen treffen. Ein Zeitstrahl ist kein vollständiges Sicherheitsprotokoll und beweist keine Ursache; Lücken durch Pausen, Neustarts und Erfassungsfehler sind möglich.

Favoriten und Zeitstrahl liegen in `experience-state.json` neben dem bisherigen Benutzerzustand, bei portabler Nutzung im Datenordner. Schreiben erfolgt atomar mit Sicherung. Lesefehler verhindern ein Überschreiben dieser Datei. Beim vollständigen Zurücksetzen wird sie mit gesichert; der Zeitstrahl wird gelöscht, Favoriten bleiben erhalten. Keine KI, Cloud oder Telemetrie.
