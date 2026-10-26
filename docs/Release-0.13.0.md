Netzblick übersichtlicher und mit Dark Mode:

- Eine zentrale Programmliste mit Suche, Filtern Alle/Gesperrt/Zu prüfen/Gerade aktiv und letzter beobachteter Aktivität.
- Details in drei Bereichen: Übersicht, Verbindungen und Regeln. Die Karte ist ein aufklappbarer Zusatz.
- Verständliche Beschreibung des aktuellen Zugriffs und getrennte Erklärung der aufgezeichneten Blockversuche.
- Blockzähler öffnet direkt die Sperrziele und verfügbaren Filterursachen. Eigene und fremde Filter werden anhand des Ereignisses unterschieden; fehlende Angaben bleiben ausdrücklich unbekannt.
- Direkte Aktionen für ausgewählte Programme: Sperren, Erlauben, 10 Minuten erlauben, geprüft markieren und Rückgängig. Umfang wird vor einer Änderung angezeigt. Zeitweise Freigaben stellen vorherige Regeln automatisch wieder her, auch nach einem Neustart. Veraltetes Rückgängig überschreibt keine neueren Regeln.
- Neue Programme und neue Ziele (IP, Protokoll, Port) sichtbar hervorgehoben. Prüfmarken bleiben gespeichert; weitere Blockversuche sind von neuen Zielen getrennt. Wiederholte Sperren bleiben mit Anzahl und Filtergrund zusammengefasst.
- Dark Mode über den Schalter oben. Einstellung gespeichert; Tabellen, Eingaben, Auswahlmenüs und Statusfarben wechseln mit. Dunkel ist die Vorgabe ohne gespeicherte Auswahl.

Installer: `Netzblick-Setup-0.13.0-win-x64.exe`. Portabel: `Netzblick-Portable-0.13.0-win-x64.zip`. Prüfsummen: `SHA256SUMS.txt`. Vor dem Update Netzblick vollständig beenden, Einstellungen und den portablen Datenordner behalten.

Entwicklungsversion (0.x), Administratorrechte erforderlich, derzeit ohne Codesignatur. Dynamische Filter entfallen beim vollständigen Beenden der Steuerung; gespeicherte Regeln werden beim nächsten Start geladen. Ereignisse gelten seit Dienststart und belegen keinen fachlichen Verbindungszweck. Keine Sandbox oder Inhaltsentschlüsselung; andere Sicherheitsregeln können zusätzlich wirken.
