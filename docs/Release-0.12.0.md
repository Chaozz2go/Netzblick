Blockversuche nachvollziehen statt nur zählen:

- Blockzähler beim Programmnamen anklicken: direkt zur Ansicht „Nur blockierte Versuche“.
- Eigene Netzblick-Regel, Prüfsperre oder Nachfragemodus als aufgezeichnete Ursache; bei anderen Windows-Netzwerkfiltern die verfügbaren Filter-/Ebenennamen.
- Sperrgrund, Ziel, Protokoll, Richtung, Anzahl, letzter Zeitpunkt und Filter-ID direkt in den Details. Fehlende Zuordnungen werden als unbekannt ausgewiesen.
- Aktueller grüner Programmstatus bleibt von früheren oder fremden Sperrereignissen getrennt. Verschiedene Sperrfilter zum selben Ziel überschreiben einander nicht mehr.

Installer: `Netzblick-Setup-0.12.0-win-x64.exe`. Portabel: `Netzblick-Portable-0.12.0-win-x64.zip`. Prüfsummen: `SHA256SUMS.txt`. Netzblick vor dem Update vollständig beenden; Einstellungen und portablen Datenordner behalten.

Die Ursache ist eine technische Filterentscheidung. Wofür Spotify oder eine andere App die Verbindung nutzen wollte, lässt sich daraus nicht sicher ablesen. Bereits vor dem Update erfasste Ereignisse erhalten keine nachträglich erfundenen Regelnamen. Ereigniszähler gelten seit Dienststart. Entwicklungsversion (0.x), Administratorrechte, derzeit ohne Codesignatur. Keine Sandbox oder Inhaltsentschlüsselung; fremde Sicherheitsregeln können zusätzlich wirken.
