Korrektur für gesperrte Programme, die aus Aktivität und Programme verschwanden.

- Gespeicherte Sperren/Prüfsperren und erfasste Blockversuche bleiben unabhängig von sichtbaren Sockets und gemessenen Bytes in der Programmliste.
- Anzahl blockierter Versuche und letzter Zeitpunkt direkt beim Programm; Ziel, Richtung, Protokoll und Nachweis in den Details.
- Blockanzeige aktualisiert sich auch bei pausierter Socket-Messung. Historische Versuche werden nach einer Freigabe nicht zu erfolgreichen Verbindungen umgedeutet.
- Blockereignisbeobachtung auch für ältere eigene Netzblick-Regeln der Windows-Firewall, ohne deren Sperre zu lockern.
- WPF-Fixtures und echter Windows-Diensttest prüfen den Fall „WFP-Blockversuch vorhanden, kein Socket sichtbar“.

Installer: `Netzblick-Setup-0.11.2-win-x64.exe`. Portabel: `Netzblick-Portable-0.11.2-win-x64.zip`. Prüfsummen: `SHA256SUMS.txt`.

Netzblick vor dem Update vollständig beenden. Einstellungen und den portablen Datenordner behalten. Vorhandene historische Blockzähler werden bei einem Dienstneustart geleert. Eine leere Liste ist kein Beweis, dass ein Programm keine Versuche macht; Warnungen zur Windows-Ereigniserfassung beachten. Die rote Ampel beschreibt die aktuelle Netzblick-Sperre, die aufgeführten Blockereignisse bereits erfasste Versuche.

Entwicklungsversion (0.x), Administratorrechte erforderlich, derzeit ohne Codesignatur. Dynamische Filter entfallen beim vollständigen Beenden der Steuerung; gespeicherte Regeln werden beim nächsten Start geladen. Keine Sandbox/Inhaltsentschlüsselung; fremde Sicherheitsregeln können zusätzlich wirken.
