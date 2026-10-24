# Netzblick 0.7.0 – Einrichten, testen und entscheiden

**Entwicklungsversion für lokal bediente Windows-Testgeräte.** Die Oberfläche wurde vereinfacht und die Regelsteuerung in einen eigenen Windows-Dienst verlagert. Kompilierung und Logikprüfungen bestehen; die reale WFP-Sperrwirkung und der Dienstbetrieb müssen vor einem produktiven Einsatz auf Windows geprüft werden. Kein Ersatz für einen Gerätetest, Virenschutz oder eine Sandbox.

## Installation und Start

Windows x64, Windows PowerShell 5.1, .NET Framework 4.8 und Administratorrechte. ZIP vollständig entpacken und **Install-Netzblick.cmd** starten. Der Installer kopiert die Laufzeitdateien nach `%ProgramFiles%\Netzblick`, richtet den automatisch startenden Dienst `NetzblickControl` ein und legt einen Tray-Autostart für das installierende Administratorkonto an. Es werden keine Zugangsdaten gespeichert. Erstinstallation startet im Beobachtungsmodus; die globale Sperre wird nicht automatisch aktiviert.

Die installierte Oberfläche öffnen: `%ProgramFiles%\Netzblick\Start-Netzblick.cmd`. Das Schließen oder Minimieren blendet sie ins Tray aus. Im Tray: öffnen, blockierte Versuche oder **Oberfläche beenden – Dienst läuft weiter**. Änderungen bleiben beim Ausblenden aktiv. Ohne angemeldeten Benutzer gibt es keine Tray-Meldungen, der laufende Dienst sammelt weiter Blockereignisse.

Ohne Installation lassen sich die bisherigen passiven Ansichten öffnen; die neuen Prüf-/Freigabefunktionen benötigen den Dienst. Die GUI benötigt derzeit weiterhin Administratorrechte. Bei einem Update bestehende GUI über das Tray beenden, dann den neuen Installer ausführen.

## Die beiden Prüfabläufe

### Programm prüfen

1. Vorhandene lokale EXE auswählen. Dateiangaben und SHA-256 werden gelesen, die Datei nicht gestartet.
2. Laufende Instanzen selbst schließen. **Vor dem Start sperren** richtet beim Dienst eine ein- und ausgehende Prüfsperre für den EXE-Pfad ein und liest die Filter zurück. Bereits gespeicherte Freigaben dieses Pfads oder rechnerweite ICMP-Freigaben müssen vorher zurückgenommen werden.
3. Erst nach der Bestätigung das Programm selbst mit normalen Rechten starten.
4. Blockereignisse beobachten. Doppelklick führt direkt zur gezielten Freigabe.
5. **Prüfung beenden** behält die Prüfsperre. Nur **Prüfsperre entfernen** nimmt sie ausdrücklich zurück. Andere Regeln bleiben wirksam.

Die Sperre ist pfadbezogen und umfasst alle Instanzen. Sie sperrt keine neu gestarteten Hilfsprogramme, Installer, lokalen Proxys oder stellvertretenden Dienste automatisch. Dafür gegebenenfalls zusätzlich den globalen Nachfragemodus verwenden. Lokale Dateizugriffe bleiben möglich. Vorhandene bewusste Freigaben gelten auch während einer laufenden Prüfung.

### Einrichten & testen

**Neue Programme zuerst fragen** aktiviert eine Grundsperre für neue externe Verbindungsaufbauten unter IPv4 und IPv6, ein- und ausgehend. Extern bedeutet hier außerhalb der Loopback-Kommunikation auf demselben PC – auch LAN, DNS und Windows-Dienste sind betroffen. Bereits in Windows erlaubte Apps werden nicht automatisch als vertrauenswürdig übernommen. „Unbekannt“ bedeutet: ohne passende Netzblick-Freigabe.

**Sicherheitsrückweg:** Beim Aktivieren werden vorherige Einstellungen gesichert. Ohne ausdrückliche Bestätigung nach spätestens zwei Minuten stellt der laufende Dienst den vorherigen Regelstand einschließlich der damaligen Einzelregeln wieder her. Auch in dieser Zeit hinzugefügte Regeln werden dabei zurückgenommen. Ein Journal stellt bei einem folgenden Dienststart eine nicht bestätigte Einrichtung zurück. Dieser Rückweg ist kein Ersatz für lokalen Konsolenzugriff.

Versuche werden nach Programm, Richtung, genauer Gegenstellen-IP, Protokoll und Dienstport gesammelt. Ausgehend ist der Zielport gemeint, eingehend der lokale Dienstport. Wechselnde Quellports eines Clients erzeugen keine einzelne Rückfrage. Du kannst:

- eine **benannte Freigabe für fünf Minuten** testen;
- eine **benannte Regel speichern**;
- eine **Sperrentscheidung speichern**;
- jede eigene Regel unter **Regeln & Freigaben** zurücknehmen.

Standard: nur Programm, Richtung, genaue IP und Dienst. Die zweite Option erlaubt ausdrücklich **alle ausgehenden Ziele und Protokolle dieses EXE-Pfads**. ICMP-Regeln verwenden keine TCP-/UDP-Ports und gelten derzeit für alle ICMP-Typen zum gewählten Ziel. Falls keine EXE zuordenbar ist, ist für ICMP eine ausdrücklich bestätigte Regel für den ganzen Rechner möglich. Hostnamen, CIDR-Netze, ICMP-Echo-Untertypen und Dienst-SIDs werden noch nicht als Regelbedingungen angeboten.

Ein abgewiesener Versuch wird nicht angehalten: Nach einer Freigabe die Aktion erneut ausführen. IP, DNS-Name, Port und Signatur beweisen keinen Verbindungszweck. Bei Windows-Sammelprozessen können mehrere Dienste denselben EXE-Pfad nutzen. Regeln sind nicht an einen Datei-Hash gebunden.

**Nachfragen ausschalten** nimmt nur die globale Grundsperre zurück. Gespeicherte Einzelregeln und Prüfsperren bleiben aktiv. Eine Freigabe ohne passende Grund-/Prüfsperre erzeugt keine zusätzliche Netzwerksperre.

## Tray-Hinweise

Meldungen bei neuen Programmen sind optional. Neue Ziele bereits bekannter Programme können separat eingeschaltet werden. Wiederholungen werden gesammelt; höchstens eine Tray-Meldung in 15 Sekunden. Ein Klick öffnet die zugehörige Anfrage. Alle Anfragen bleiben unabhängig von Meldungen in der Übersicht. Windows kann Benachrichtigungen unterdrücken. Ohne sichtbare Meldung wird nicht automatisch freigegeben.

## Schutz und Grenzen des Dienstes

Eigene dynamische WFP-Filter werden in einer eigenen Ebene und in Transaktionen geändert und zurückgelesen. Gespeicherte Konfiguration wird nur nach erfolgreicher Filteränderung geschrieben; bei Fehlern wird eine Rücknahme versucht. Unbestätigter Filterstatus sperrt weitere Freigaben. Fremde Windows-Firewallregeln und Profil-Standardaktionen werden nicht überschrieben.

**Wichtig:** Die Freigaben betreffen die Netzblick-Ebene. Andere Windows-Regeln, insbesondere der Windows-Standardblock für eingehende Verbindungen, können weiterhin sperren. Netzblick erzeugt noch keine zusätzlichen Windows-Firewall-Zulassungsregeln, um diesen Standardblock zu öffnen. Eine Netzblick-Freigabe für eingehendes Ping/LDAP ist deshalb allein keine Garantie der Erreichbarkeit. Bestehende manuelle Netzblick-Regeln aus älteren Versionen können ebenfalls weiter sperren; sie stehen unter Programme → eigene Regeln.

Der Dienst läuft unabhängig vom Fenster. **Bei Dienstende oder Prozessabbruch entfernt Windows die dynamischen Netzblick-Filter. Vor dem Dienststart nach einem Neustart und während eines Dienstabsturzes gibt es deshalb keine lückenlose Netzblick-Sperre.** Die Wiederanlaufkonfiguration versucht einen Neustart nach 2/5/10 Sekunden. Gespeicherte Regeln werden dann wieder geladen und abgelaufene Freigaben nicht erneut installiert. Ein ausgefallener Dienst kann temporäre Regeln nicht weiter prüfen. Das ist noch kein dauerhafter Schutz gegen Manipulation oder einen Administrator.

Bereits offene Verbindungen werden nicht allein durch die Socket-Anzeige als sicher getrennt bestätigt. VPNs, lokale Vermittler, VMs und andere Netzwerk-Stacks benötigen eigene Tests. Erfassung und Filterstatus werden getrennt angezeigt. Ein leeres Ereignisprotokoll beweist keinen fehlenden Netzwerkzugriff.

## Lokale Daten und Überwachung

Regeldatei: `%ProgramData%\Netzblick\control.json`, Sicherheitsrückweg daneben. Nur SYSTEM/Administratoren dürfen diese Daten schreiben und lesen; Kommunikation mit dem Dienst ist auf lokale Administratoren/SYSTEM beschränkt und lehnt Netzwerkzugriffe ab. Die GUI vergleicht den Pipe-Serverprozess mit dem Windows-Dienstprozess.

Blockierte Versuche: Windows-Security-Ereignisse 5157. Während einer aktiven Grundsperre, Prüfsperre oder gespeicherten Einzelsperre aktiviert der Dienst bei Bedarf vorübergehend die systemweite WFP-Fehlerüberwachung. Das kann die Menge des Security-Protokolls erhöhen. Bestehende Erfolgeinstellungen bleiben erhalten; Audit-Konflikte und Wiederherstellung werden gemeldet. Es werden keine Security-Protokolle gelöscht. Der Dienst hält höchstens 512 Gegenstellen-/Dienstgruppen und 100 Änderungsmeldungen seit seinem Start im Speicher; Erfassungslücken erscheinen als Hinweis.

Benachrichtigungsoptionen und bisherige bekannte Programmpfade liegen unter `%LOCALAPPDATA%\Netzblick`. Es gibt keine Cloudpflicht oder Telemetrie. Die optionale DNS-Namensauflösung ist standardmäßig ausgeschaltet. Berichte und CSV-Dateien werden nur auf Wunsch exportiert.

Die bestehende ETW-Datenmessung, Socket-Ansicht, Offline-Weltkarte und Ping/Traceroute bleiben als Details verfügbar. ETW-Bytewerte gelten seit dem Start der Oberfläche; nach deren ausdrücklichem Beenden misst der Dienst keine Bytehistorie. TLS-Inhalte werden nicht entschlüsselt, Browser-Tabs und übertragene Dokumente werden nicht identifiziert. Länder sind geschätzt und keine Gefahrenbewertung. Daten/Lizenzen: THIRD-PARTY-NOTICES.txt und lib/dependencies.json.

## Deinstallation

In einer administrativen Windows PowerShell:

```powershell
& "$env:ProgramFiles\Netzblick\Install-Netzblick.ps1" -Uninstall
```

Das stoppt und entfernt den Dienst sowie den Tray-Autostart des aufrufenden Kontos. Dateien und gespeicherte Einstellungen bleiben als Sicherung erhalten. Bereits laufende GUI über das Tray beenden. Alte Windows-Firewallregeln werden nicht gelöscht. Bei mehreren installierenden Konten deren Tray-Aufgaben separat prüfen.

## Entwicklung und Prüfung

GitHub: https://github.com/Chaozz2go/Netzblick. Frühere Stände und zusätzliche ursprüngliche Historie bleiben erhalten. Dienstquellen: src/ServiceHost.cs, SetupCore.cs, SetupTransport.cs, WindowsAccess.cs; offline mit tools/Build-Service.ps1 kompilierbar. Das ETW-Modul ist separat unter tools/Capture.csproj beschrieben.

- `dotnet run --project tools/CoreChecks.csproj -- data`: Kernlogik ohne Firewalländerungen.
- `Test-Netzblick.ps1`: Syntax, echte Startreferenzen, XAML, Geodaten und Socket-Abfrage; keine Filterinstallation oder Audit-Änderung.
- `tools/Test-UI.ps1`: vier UI-Zustände und acht Renderings ausschließlich mit Fake-Dienstantworten. In einem frischen PowerShell-Prozess ausführen.
- GitHub Actions führt diese Windows-Prüfungen zusätzlich aus. Auf dem isolierten Runner kommt ein Dienst-/IPv4-TCP-Test mit einer eigenen Fixture hinzu: vorab sperren, Blockereignis, gezielt erlauben, zurücknehmen. Ohne erreichbare Baseline wird dieser Netzwerktest ausdrücklich übersprungen. Der globale Nachfragemodus wird dabei nicht aktiviert. Das ersetzt weder IPv6-/UDP-/ICMP-Tests noch den Gerätetest.

Genauer aktueller Prüfstand und Gerätetest: PRUEFSTAND.txt. Frühere Versionsdokumente sind historische Beschreibungen.
