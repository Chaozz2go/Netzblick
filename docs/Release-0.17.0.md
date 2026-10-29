# Netzblick 0.17.0 – Hostprozesse & Dienste

- Neuer Reiter für laufende Windows-Dienstprozesse, auch ohne sichtbaren Netzwerk-Socket.
- Getrennte Instanzen nach PID und Startzeit; Suche nach Prozess, PID, Dienstname und Windows-Beschreibung.
- Aufklappbare Dienste mit lokal gelesenen Windows-Namen, Status und Beschreibung. Keine KI oder Cloud-Anbindung.
- Prozessgenaue Socketansicht mit eingehendem/ausgehendem Aufbau, lauschenden und unbekannten Verbindungen.
- Filter für sichtbare Sockets, gesperrte/eingeschränkte Dateipfade und offene Prüfungen.
- Gemeinsame Sperrereignisse mit aufgezeichnetem Grund und Verweis auf bestehende Regelverwaltung.

## Grenzen

Die Dienstliste zeigt, welche Dienste Windows einem Prozess zuordnet. Sie belegt nicht, welcher Dienst eine einzelne Verbindung verursacht hat. Regeln, Byte-Messungen, Prüfstatus und die bisherigen Sperrereignisse beziehen sich auf den Dateipfad und können mehrere Instanzen betreffen. Diese Grenzen werden in der Oberfläche ausdrücklich angezeigt. Keine neuen pauschalen Host-Sperren oder Dienststeuerung.

Die Dienstliste wird beim Öffnen asynchron und danach etwa alle zehn Sekunden aktualisiert, Sockets im bestehenden Messtakt. Alle Angaben sind Momentaufnahmen. Nicht lesbare Pfade/Beschreibungen und Erfassungsfehler werden angezeigt. Andere gemeinsam genutzte Hosts ohne registrierte Windows-Dienste sind nicht Teil dieses Reiters.
