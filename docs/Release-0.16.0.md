# Netzblick 0.16.0 – Netzwerk-Dashboard und klare Verbindungsrichtungen

- Dashboard als neue Startseite, in Clean/Future und Hell/Dunkel. Bis zu sechs aktive Programme mit lokalen EXE-Icons und zusammengefassten Gegenstellen. Programm anklicken für Status, Datenrate, Prüfgrund und bestehende Detail-/Sperraktionen.
- Linien mit Pfeilspitzen für sicher erfassten Verbindungsaufbau; unbekannte Richtung ohne Pfeil. Jüngste blockierte Versuche rot gestrichelt. Keine Ableitung der Richtung aus Ports oder Download/Upload.
- Getrennte große Adaptergraphen für Empfang und Versand, 60 Sekunden / 3 Minuten / 5 Minuten. Begrenzte Historie im Speicher; keine erfundenen Messpunkte. Adapterwerte können bei VPNs/virtuellen Adaptern doppelt zählen. Die Programmwerte stammen separat aus ETW.
- Dashboard einfrieren und fortsetzen, während Erfassung und Firewallsteuerung weiterlaufen. In der eingefrorenen Ansicht ist die Sperraktion deaktiviert, damit keine veraltete Auswahl verwendet wird.
- Richtungsübersicht direkt bei den Programmen und Filter für ausgehend, eingehend, lauschend und unbekannt in den Verbindungen. Empfang ist kein eingehender Verbindungsaufbau.
- TCP-Connect-/Accept-Ereignisse werden nach EXE, PID, Prozessstart und beiden Endpunkten zugeordnet. Disconnect entfernt die Zuordnung. Nicht sicher erfasster Aufbau, UDP und mehrdeutige Rollen bleiben unbekannt. Die Richtung blockierter Versuche stammt aus dem Windows-Blockereignis.

Setup und portable ZIP behalten vorhandene Daten. Die bisherigen Grenzen von Erfassung, pfadbezogenen Regeln und dynamischen Filtern bleiben bestehen. Die App benötigt weiterhin Administratorrechte. Die Darstellung enthält ausschließlich lokal erfasste Daten; für Dashboard und Icons ist kein Cloudzugriff nötig.
