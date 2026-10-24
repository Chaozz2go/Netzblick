# Netzblick 0.6.0

**Neu: Kontrollmodus als Testversion.** Neue Verbindungsaufbauten außerhalb dieses PCs zunächst blockieren, Programmanfragen verstehen und ausgehenden Zugriff bewusst nur für diese Sitzung freigeben oder weiter blockieren. Die tatsächliche Netzwerksperre wurde in der Entwicklungsumgebung noch nicht aktiviert oder auf einem Gerät validiert. Details, Grenzen und Testplan: [Version 0.6.0](docs/Version-0.6.0.md).

Beim Schließen oder Absturz von Netzblick endet dieser Kontrollmodus; er ersetzt keinen dauerhaften Firewall-Dienst. Vorhandene Windows-Firewallregeln werden nicht umgeschrieben.

Seit 0.5.0: sichtbarer Prüfablauf mit Prozess-/Fensterstatus, optionalen Reverse-DNS-Namen und vorsichtig formulierten Diensthinweisen. Anleitung und aktueller Prüfstand: [Version 0.5.0](docs/Version-0.5.0.md). DNS-Abfragen sind beim Start ausgeschaltet.

Startkorrektur gegenüber 0.4.0: Die C#-Kompilierung bindet `System.Xml.dll` und `System.Core.dll` unter Windows PowerShell 5.1 ausdrücklich ein. Damit wird die gemeldete fehlende `System.Xml`-Referenz in `InspectionCore.cs` behoben.

Ein Windows-Firewall-Addon mit Programmübersicht, Netzwerksteuerung und Prüfmodus.

## Start

ZIP vollständig in einen eigenen Ordner entpacken, `Start-Netzblick.cmd` starten und die Administratorabfrage bestätigen. Windows 10/11 mit Windows PowerShell 5.1 und .NET Framework 4.8. Das Paket enthält alle zusätzlichen Laufzeitdateien; kein Server und kein Konto sind nötig. Die ExecutionPolicy wird nur für den gestarteten PowerShell-Prozess gesetzt, nicht dauerhaft umgestellt. Unternehmensrichtlinien können den Start oder lokale Firewallregeln einschränken.

## Drei Hauptbereiche

- **Übersicht:** beobachtete Programme, gesendete/empfangene ETW-Bytes seit diesem Start, zuletzt gemessene Raten, gesammelte Hinweise und letzte Änderung mit Rückgängig.
- **Programme:** suchen, Programm auswählen und Netzwerkzustand ändern. Gegenstellen, Weltkarte, Ping/Traceroute, eigene Regeln und Verlauf liegen in den Details. Die Weltkarte kann auch alle Programme anzeigen.
- **Programm prüfen:** eine lokale EXE vorab sperren und blockierte Verbindungsversuche beobachten. Die EXE wird niemals von Netzblick mit dessen Administratorrechten gestartet. Ausführliche Anleitung: `docs/Pruefmodus.md`.

In sekundären Ansichten führt „Zurück zu Programme“ zurück. „Ansicht pausieren“ friert die passive Anzeige ein; die Hintergrundmessung, aktive Diagnose-/Prüfsitzungen und Firewallregeln bleiben aktiv.

## Netzwerkzustände

| Zustand | Bedeutung |
| --- | --- |
| Windows-Standard | Eigene Netzblick-Regeln für den Pfad entfernen. Andere Regeln und Windows-Standardeinstellungen bleiben wirksam. Das ist keine zusätzliche Freigabe. |
| Nur private Netze | Verbindungen außerhalb der unten genannten Adressbereiche ein- und ausgehend sperren. Verbleibender Verkehr unterliegt weiterhin den Windows-Regeln. |
| Netzwerk sperren | Für den vollständigen EXE-Pfad ein- und ausgehend alle Gegenstellen und Protokolle auf allen Profilen sperren. |

Alle Instanzen desselben EXE-Pfads sind betroffen. Ein anderer Pfad ist ein anderes Regelziel. Hilfsprogramme und stellvertretende Windows-Dienste werden nicht automatisch mitgesperrt. Kritische Windows-Sammelprozesse sind von pauschalen Änderungen ausgenommen. Eigene extern veränderte oder unvollständige Regeln werden kenntlich gemacht und nicht stillschweigend überschrieben.

**Nur private Netze** ist adressbasiert, keine Erkennung einer vertrauenswürdigen LAN-Schnittstelle. Erlaubnisbereiche der zusätzlichen Einschränkung: IPv4 `10/8`, `100.64/10` (auch manche VPNs), `127/8`, `169.254/16`, `172.16/12`, `192.168/16`, `224.0.0/24`, `239/8`, `255.255.255.255`; IPv6 `::1`, `fc00::/7`, `fe80::/10`, `ff01::/16`, `ff02::/16`. Netzblick sperrt die Komplementbereiche; es kombiniert keine pauschale Blockregel mit einer wirkungslosen Ausnahme-Freigabe. Öffentliche Adressen in einem örtlichen LAN werden ebenfalls eingeschränkt. VPNs, lokale Proxys oder delegierte Dienste können Verkehr weiterleiten; der Modus ist keine Isolationsgarantie.

## Rückgängig

Die letzten 20 erfolgreichen eigenen Zustandsänderungen werden lokal gespeichert. „Letzte Änderung rückgängig“ stellt den vorherigen verwalteten Zustand wieder her, sofern die beiden betroffenen Regeln seitdem noch genau dem aufgezeichneten Ergebnis entsprechen. Spätere fremde Änderungen werden nicht überschrieben. Während einer laufenden Prüfung lassen sich zugehörige Sperren nicht lockern.

Bei Fehlern während einer Änderung wird die Wiederherstellung des vorherigen Zustands versucht. Scheitert sie, zeigt Netzblick das ausdrücklich an. Eine Regeländerung in beide Richtungen ist keine atomare Windows-Transaktion. Fremde Firewallregeln, Profile und globale Standardaktionen werden nicht verändert.

## Was die Datenmessung zeigt

Das enthaltene ETW-Modul erfasst TCP-/UDP-Sende- und Empfangsereignisse unter IPv4/IPv6 und summiert die von Windows gemeldeten Bytewerte pro Programmpfad. Gegenstellen werden ebenfalls aus diesen Ereignissen ergänzt, einschließlich UDP/QUIC. Es werden keine Paketinhalte gespeichert oder TLS-Verbindungen entschlüsselt. Die Werte sind keine Messung entschlüsselter Nutzdaten oder ein Nachweis, dass ein entfernter Server die Daten erhalten hat; TCP-Wiederholungen, Offloading, VPNs und die Erfassungsschicht können den Vergleich mit Dateigrößen oder Adapterzählern beeinflussen.

Die Summen gelten nur seit diesem Netzblick-Start. Raten benötigen zwei Messpunkte. Noch nicht zugeordnete Ereignisse erscheinen getrennt mit PID; eine nach Prozessstart liegende PID-Auflösung wird nicht rückwirkend als Beweis für ältere Ereignisse verwendet. Fehler, Ereignisverluste und Kapazitätsgrenzen werden angezeigt. Ist ETW nicht verfügbar, bleibt die Firewallbedienung nutzbar; fehlende Messwerte erscheinen als fehlend, nicht als bestätigte Null.

Grenzen: maximal 10.000 Messgruppen und 20.000 Gegenstellen im Arbeitsspeicher. Programm- und Gegenstellenlisten enthalten auch in dieser Sitzung beendete Aktivitäten. Die Socket-Liste bleibt eine Zwei-Sekunden-Stichprobe; ETW ist die zusätzliche ereignisbasierte Messung. Die Übersicht aller Adapter bleibt ausdrücklich getrennt beschriftet und kann VPN-/virtuellen Verkehr mehrfach zählen.

Netzblick startet eine eigene, eindeutig benannte ETW-Sitzung und stoppt keine fremden Trace-Sitzungen. Nach einem abrupten Ende können eigene ETW-Sitzungen zunächst weiterlaufen; beim nächsten Start werden nur erkennbar verwaiste Sitzungen mit Netzblick-Namensschema bereinigt. Es wird kein Dienst installiert und keine ETL-Datei geschrieben.

## Neue Programme und Verlauf

„Erstmals beobachtet“ bedeutet: erstmals seit Beginn deiner gespeicherten Beobachtung gesehen, nicht neu installiert oder gefährlich. Bei der ersten Benutzung werden die ersten 15 Sekunden als Ausgangsbestand erfasst. Danach werden neue Programmpfade gesammelt in der Übersicht gemeldet. Es gibt keine Rückfrage für jede IP-Adresse und keine automatische Vorabsperre unbekannter Programme. Eine Meldung kann deshalb erst nach deren Netzwerkaktivität erscheinen.

Unter `%LOCALAPPDATA%\Netzblick\user-state.json` liegen bis zu 10.000 bekannte Pfade und die letzten 20 Zustandsänderungen. Das manuelle Ausgangsland der Karte bleibt in `settings.json`. Diese Dateien enthalten lokale Programmpfade; es findet keine Übertragung an einen Dienst statt. Der Verbindungsverlauf ist auf 500 Einträge dieser Sitzung begrenzt. Prüfberichte und CSV-Exporte werden nur auf Wunsch lokal gespeichert.

## Weltkarte und Diagnose

Die Weltkarte nutzt DB-IP Country Lite, Oktober 2026, und Natural Earth lokal ohne API-Schlüssel. Sie zeigt geschätzte Länder anhand schematischer Länderpunkte, keine exakten Serverstandorte oder Kabelwege. Browser-Tabs und vollständige HTTP-Anfragen werden nicht zugeordnet. Für nicht verortbare, private und lokale Adressen werden keine Standorte erfunden.

Im Diagnosebereich: `ping example.org`, `ping -6 ::1`, `tracert example.org` oder `traceroute -6 example.org`. Zehn Ping-Proben beziehungsweise maximal 30 Traceroute-Hops mit bis zu drei ICMP-Proben je Hop. Stoppen, laufende Textausgabe, Karte und Antwortzeitdiagramm sind vorhanden. Keine allgemeine Shell. Ein Timeout ist kein Beweis eines ausgefallenen Ziels. Eine angeforderte Diagnose mit Hostnamen nutzt normale DNS-Auflösung; die passive Kartenanzeige führt keine IP-Abfragen aus.

## Prüfmodus und Grenzen

Die Prüfung verwendet echte Security-Ereignisse 5157 für blockierte Versuche. Dazu wird bei Bedarf vorübergehend die systemweite Fehlerüberwachung der betreffenden WFP-Unterkategorie aktiviert und der vorherige Zustand gesichert. Beenden stellt ihn wieder her, soweit zwischenzeitliche Änderungen dem nicht entgegenstehen; eine Crash-Wiederherstellung erfolgt beim nächsten Start. Details und Konfliktbehandlung in `docs/Pruefmodus.md`.

Ein Blockereignis ist keine Byte-Messung. Die separate Prüfansicht weist deshalb weiterhin keine gesendeten Bytes aus; gemeldete Verkehrswerte stehen unter Programme. Weder eine leere Liste noch eine ETW-Null ist ein Sicherheitsnachweis. Die App ist keine Sandbox. Kurzlebige Hilfsprozesse, delegierte Dienste und Erfassungslücken können fehlen.

## Git und Entwicklung

Der Projektordner ist ein lokales Git-Repository auf Branch `main`. Der Ausgangsstand 0.3.0 und die Weiterentwicklung sind als Commits enthalten. Das ZIP enthält den Git-Verlauf; nach dem Entpacken sind beispielsweise `git status` und `git log --oneline` direkt im Ordner Netzblick nutzbar. GitHub: https://github.com/Chaozz2go/Netzblick. Der ursprüngliche Verlauf bis 0.4.1 liegt zusätzlich als Netzblick-history.bundle im GitHub-Repository; der neue GitHub-Verlauf wurde separat begonnen.

Die Oberfläche und Windows-Dienstezugriffe liegen als PowerShell-/C#-Quellen vor. Das separat kompilierte ETW-Modul liegt unter `lib/Netzblick.Capture.dll`; Quellen `src/TrafficCore.cs` und `src/WindowsTraffic.cs`, Buildprojekt `tools/Capture.csproj`. Mit .NET-SDK: `dotnet build tools/Capture.csproj -c Release` (beim ersten Build wird das .NET-Framework-Referenzpaket benötigt). Die App selbst benötigt kein SDK.

`Test-Netzblick.ps1` prüft unter Windows Syntax, C#-Kompilierung, XAML, Geo-Daten und Socket-Erfassung ohne Firewall-/Audit-Änderungen oder ETW-Start. `tools/CoreChecks.csproj` enthält die plattformunabhängigen Kernprüfungen. Drittanbieter-Versionen und Lizenzen: `lib/dependencies.json`, zugehörige Lizenzdateien und `THIRD-PARTY-NOTICES.txt`.

## Teststand

7.219 Kernprüfungen, C#-Kompilierung gegen .NET Framework 4.8, nativer PowerShell-Syntaxparser und XML-/UI-Verweisprüfungen bestanden. Die Entwicklung erfolgte unter Linux. Für Version 0.5.0 bestehen 2.233 Kernprüfungen sowie die Windows-Kompilierung, das Laden der WPF-Panels und fünf mit Beispieldaten geprüfte UI-Zustände. Der vollständige Starttest ist in der eingeschränkten Ausführungsumgebung bei den Socket-Abfragen blockiert. Ein vollständiger Windows-Gerätetest für ETW-Messwerte, COM-Regeländerung/Rückgängig und Audit-Wiederherstellung steht weiterhin aus. Bitte zuerst mit einem bekannten, entbehrlichen Programm auf einem Testrechner prüfen. Genauer Umfang: `PRUEFSTAND.txt`.
