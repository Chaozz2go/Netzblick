# Netzblick 0.10.1 – Windows-EXE, portabel und installierbar

**Entwicklungsversion für lokal bediente Windows-Testgeräte.** Die Oberfläche wurde vereinfacht und die Regelsteuerung in einen eigenen Windows-Dienst verlagert. Kompilierung und Logikprüfungen bestehen; die reale WFP-Sperrwirkung und der Dienstbetrieb müssen vor einem produktiven Einsatz auf Windows geprüft werden. Kein Ersatz für einen Gerätetest, Virenschutz oder eine Sandbox.

## Netzwerkfilter gemeinsam verwenden (0.10.1)

Eine weitere WFP-Ebene mit derselben Priorität deaktiviert Netzblick nicht mehr pauschal. Netzblick prüft seine eigenen Filter weiter vollständig zurück und untersucht bei geplanten Sperren die passenden aktiven Filter auf den betroffenen ALE-Ebenen.

Normale parallele Freigaben und eindeutig andere EXE-Pfade verhindern die Prüfung nicht. Eine statische, nicht übersteuerbare Fremdfreigabe, die sich von der geplanten Sperre nicht eindeutig trennen lässt, wird vor der Änderung mit Ebene und Filtername gemeldet. Unbekannte Bedingungen werden konservativ als mögliche Überschneidung behandelt. Bei dynamischen Treiberentscheidungen bleibt ein Hinweis sichtbar; diese lassen sich ohne eigenen Treiber nicht vollständig vorhersagen. Fremde Regeln werden weder verändert noch entfernt. „Bestätigt“ bezeichnet die eingerichteten und zurückgelesenen Netzblick-Regeln, keine Garantie für jeden fremden Netzwerk-Stack.

Die Windows-Prüfung erzeugt isoliert eine zweite dynamische WFP-Ebene mit maximaler Priorität: leerer Peer, parallele Soft-Permit-Regel, Hard-Permit-Regel für eine andere EXE, echte TCP-Sperre/Freigabe sowie Zurückweisen eines überlappenden Hard Permit. Danach werden unveränderte Peer-Filter und deren eigener Sitzungsabbau geprüft. Release-Pakete werden erst nach den Interaktions- und nativen Diensttests in demselben Build bereitgestellt.

## Neu anfangen, Karte und Tray

**Aktivität → Alles neu prüfen …** zeigt vorab, was zurückgesetzt wird: eigene Netzblick-Freigaben und Sperren, Programm-Prüfsperren, Nachfragemodus, Prüfliste, gemerkter Programmbestand und Sitzungsmessung. Bestätigen erstellt Sicherungen (`control.json.reset-*.bak` beim Dienst; `reset-*.json` bei den Benutzereinstellungen). Danach gilt Beobachten/Zulassen, und auch alle aktuell erfassten Programme kommen erneut in die Prüfliste. Andere Windows-Firewallregeln, Exporte und der GitHub-Zugang bleiben erhalten. Der Reset ist kein Ersatz für eine Fehlerbehebung am Filterdienst; ein unbestätigter Dienststatus wird weiter angezeigt.

**Programm prüfen:** Der Startknopf ist nur bei vorhandenen Dateiangaben und bestätigtem Filterstatus aktiv. Ein gesperrter Start zeigt jetzt den konkreten Grund. **Dienst und Filter erneut prüfen** startet einen gestoppten installierten Dienst und fordert eine erneute native Filterprüfung an. Echte Filterkonflikte werden nicht durch blindes Aktivieren des Knopfs übergangen.

**Weltkarte:** Mausrad zoomt am Mauszeiger von 100 bis 800 Prozent. Bei vergrößerter Karte mit gedrückter linker Maustaste verschieben; **Zoom zurücksetzen** zeigt wieder die ganze Karte. Der Fehler beim Wechsel zu einem Programm mit genau einem Socket und zusätzlichen ETW-Gegenstellen ist korrigiert. Darstellungsfehler werden in der Kartenansicht angezeigt und beenden die App nicht.

**Tray:** **Fenster schließen · im Tray weiter** blendet nur das Fenster aus; Erfassung, Hinweise und Filtersteuerung laufen weiter. **Netzblick vollständig beenden** entfernt auch das Tray und stoppt bei der installierten Version den Dienst. Bei aktiven Regeln wird nachgefragt. Dynamische Netzblick-Filter enden dabei; gespeicherte Regeln werden beim nächsten App-Start wieder geladen. Der installierte Dienst wird beim nächsten Start bei Bedarf wieder gestartet. Der konfigurierte Autostart bleibt bestehen.

## Schnell bewerten

Die Startseite **Aktivität** zeigt neue Programme in einer gespeicherten Prüfliste. Ein optionaler Hinweis bietet **Anzeigen**, **Sperren** und **Später**. Anzeigen öffnet direkt das passende Programm mit Socket-, ETW- und blockierten Gegenstellen. Beendete Programme bleiben in der Prüfliste erhalten. **Als geprüft markieren** entfernt nur den Prüfeintrag und ändert keine Firewallregel.

Standard ist **Zulassen und anschließend prüfen**. Neue Programme können bereits Daten übertragen haben, bevor sie beobachtet werden. Die Erkennung basiert auf dem EXE-Pfad, nicht auf dem Datei-Hash. Beim ersten Start werden 15 Sekunden als Ausgangsbestand erfasst.

Optional: **Unbekannte Verbindungen bis zur Freigabe sperren**. Dieser Modus verwendet die bestehende globale WFP-Grundsperre und die gezielten Freigaben. Das betrifft auch neue Gegenstellen bekannter Programme, DNS und Windows-Dienste. Die Aktivierung fragt nach und verwendet den Zwei-Minuten-Sicherheitsrückweg. Es werden nicht automatisch alle bisherigen Programme freigegeben. Benötigte Regeln und die Bestätigung liegen unter **Einrichten & testen**.

**Sperren** setzt in einer Diensttransaktion zwei dauerhafte Netzblick-Regeln für alle neuen externen Verbindungen des gewählten EXE-Pfads, ein- und ausgehend. Die Prüfliste bleibt offen. Loopback bleibt ausgenommen. Eine bestehende Verbindung wird damit nicht als sicher getrennt bestätigt. System-Sammelprozesse müssen gezielt unter Einrichten & testen bewertet werden. Zum Aufheben beide Regeln unter Regeln zurücknehmen.

## Updates

**Updates → Auf Updates prüfen** vergleicht veröffentlichte GitHub-Releases mit der installierten Version und Buildnummer. Netzwerkzugriff erfolgt nur auf diesen Klick. Testversionen und Entwürfe lassen sich ausdrücklich einschließen. Nur Releases mit einem passenden Windows-Paket zählen. Die App öffnet die gewählte Version im Browser; sie führt keinen Download automatisch aus. Der Installer erhält bestehende Daten.

Das Repository ist privat: Für den Versionsvergleich einen Fine-grained GitHub-Token nur für Netzblick mit **Contents: Read** im Passwortfeld einrichten. Windows verschlüsselt ihn für das aktuelle Benutzerkonto unter `%LOCALAPPDATA%\Netzblick`; er reist nicht im portablen Ordner mit. Schreibrechte sind nicht erforderlich. Für Entwürfe ist zusätzlich entsprechende GitHub-Sichtbarkeit nötig. Ohne Token bleibt **Downloadseite öffnen** über die eigene Browser-Anmeldung möglich. Der Zugang lässt sich jederzeit entfernen. Ein fehlender GitHub-Zugriff wird ausdrücklich angezeigt und nicht als „aktuell“ gewertet.

Die Fehlerauswertung aus 0.8.1 bleibt enthalten: Unterdrückte PowerShell-Meldungen erzeugen keinen falschen Installationsabbruch; echte Fehler liefern Details.

## Installation und Start

Windows 10/11 x64, .NET Framework 4.8 und Windows PowerShell 5.1 (auf unterstützten Windows-Systemen vorhanden). Kein zusätzlicher Download beim Start. Die EXE verwendet den Windows-PowerShell-Motor intern; es öffnet sich kein PowerShell-Fenster. Kernkomponenten sind vorkompiliert. Die bisherige Oberfläche und Funktionen bleiben erhalten.

- **Portabel:** `Netzblick-Portable-0.10.1-win-x64.zip` entpacken, `Netzblick.exe` öffnen. Es werden kein Windows-Dienst und kein Autostart eingerichtet. Regeln, Verlaufseinstellungen und Benachrichtigungen liegen im Ordner `Netzblick-Daten` neben der EXE. Diesen beim Update behalten. Der Ordner benötigt ein lokales Laufwerk mit Windows-Dateiberechtigungen, beispielsweise NTFS. Die portable Filtersteuerung läuft im EXE-Prozess. Beim vollständigen Beenden über das Tray oder einem Prozessabbruch entfallen ihre dynamischen Filter. Gespeicherte Regeln werden beim nächsten Start erneut geladen. Bisherige ausdrücklich gesetzte Windows-Firewallregeln bleiben bestehen.
- **Installiert:** `Netzblick-Setup-0.10.1-win-x64.exe` öffnen. Der Assistent richtet die App unter `%ProgramFiles%\Netzblick`, den Hintergrunddienst und den Tray-Autostart für das installierende Administratorkonto ein. Start über das Startmenü. Einstellungen liegen weiterhin unter `%ProgramData%\Netzblick` und `%LOCALAPPDATA%\Netzblick`. Updates und Deinstallation erhalten diese Daten. Deinstallieren über Windows → Installierte Apps.

Beide Betriebsarten benötigen Administratorrechte für ETW und Firewallsteuerung. Portabel und installiert dürfen nicht gleichzeitig laufen. Vor Installation/Update die laufende Oberfläche über das Tray vollständig beenden. Die portable Version verändert die Konfiguration einer vorhandenen Installation nicht; ein laufender installierter Dienst wird erkannt und der portable Start abgebrochen.

Die EXE enthält ihre verwalteten DLLs und lädt diese aus eigenen Ressourcen in den Speicher. XAML, UI-Skripte, Geodaten und die native ETW-Komponente werden für die Laufzeit in einen geschützten Ordner unter `%ProgramData%\Netzblick.Runtime` geschrieben und nach Möglichkeit beim Beenden entfernt. Die Internetmarkierung der heruntergeladenen EXE muss dafür nicht entfernt werden. Windows kann für unsignierte neue EXE-Dateien weiterhin SmartScreen anzeigen; eine Codesignatur ist noch nicht vorhanden.

Fenster schließen/minimieren blendet ins Tray aus. **Fenster schließen** lässt die Sitzung im Tray weiterlaufen. **Netzblick vollständig beenden** beendet auch die Filtersteuerung und stoppt den installierten Dienst. Ohne angemeldeten Benutzer zeigt die installierte Version keine Tray-Meldungen, der Dienst sammelt weiter Blockereignisse.

Die alten `.ps1`/`.cmd`-Dateien sind nur noch Entwicklungs- und Kompatibilitätseinstiege im Quellrepository, nicht der Startweg der neuen Pakete. Für Entwicklung: `tools/Build-Desktop.ps1`, danach Inno Setup 6 mit `installer/Netzblick.iss` kompilieren. Der Workflow „Windows EXE and installer“ prüft beide Pakete und legt bei Erfolg einen GitHub-Releaseentwurf mit Downloads an.

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

