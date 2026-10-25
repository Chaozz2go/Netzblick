Netzblick für Windows 10/11 x64: Programme beobachten, neue externe Verbindungen prüfen und gezielt sperren oder freigeben.

- Ampel direkt am Programmnamen in Aktivität und Programme: Rot gesperrt, Gelb teilweise eingeschränkt, Grün von Netzblick durchgelassen, Grau unbestätigt. Prüfstatus bleibt separat.
- Gespeicherte Sperren, Freigaben und Prüfsperren gemeinsam verwalten; einzelne Entscheidungen zurücknehmen oder Programme auf Standard zurücksetzen.
- Öffentliche Updateprüfung ohne GitHub-Konto/Token. Prüfung auf Klick; Installation bleibt eine bewusste Aktion.
- Mausrad-Zoom auf der Offline-Weltkarte, frischer Prüfstart und getrenntes Fenster-Schließen/Programm-Beenden im Tray.
- Windows-Filterkoexistenz, echte TCP-Sperre/Freigabe/Rücknahme sowie Setup/Update/Deinstallation in der Windows-Pipeline geprüft. Details: PRUEFSTAND.txt.

**Download:** `Netzblick-Setup-0.11.1-win-x64.exe` zum Installieren oder `Netzblick-Portable-0.11.1-win-x64.zip` zum Entpacken. `SHA256SUMS.txt` enthält die SHA-256-Prüfsummen. Vor Updates Netzblick im Tray vollständig beenden; Einstellungen und den portablen Datenordner behalten.

Entwicklungsversion (0.x), Administratorrechte erforderlich. Pakete sind derzeit nicht codesigniert. Dynamische Netzblick-Filter entfallen beim vollständigen Beenden des Dienstes bzw. der portablen App; Einstellungen werden beim nächsten Start geladen. Keine Sandbox und keine Inhaltsentschlüsselung. Andere Firewall-/VPN-/Sicherheitsregeln können zusätzlich wirken. Bestehende Verbindungen werden nicht zuverlässig durch eine neue Sperre beendet.
