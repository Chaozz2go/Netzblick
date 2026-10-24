# Netzblick 0.5.0 – verständlicher Prüfmodus und Gegenstellen

## Programm prüfen
1. EXE auswählen: Dateiinformationen werden gelesen; noch keine neue Sperre.
2. „Sperren und prüfen“: Netzblick prüft die Firewall, setzt eigene Sperren und startet die Beobachtung.
3. Erst nach der Aufforderung das Programm selbst mit normalen Benutzerrechten starten.

Die große Statuskarte unterscheidet Warten, laufenden Prozess, erkanntes sichtbares Fenster, nicht mehr beobachteten Prozess, eingeschränkte Beobachtung und beendete Prüfung. Der Zeitstempel zeigt die Aktualisierung der Ansicht. Der bewegte Balken zeigt eine aktive Beobachtung, keine gemessene Datenübertragung. Ein sichtbares Fenster kann verdeckt sein; es ist kein Nachweis für eine bedienbare oder vollständig geladene Anwendung.

„Dateiinformationen und Prüfschritte“ enthält einen zeitlichen Ablauf mit bis zu 100 Einträgen. Prozesse, Fensterzustand und nicht automatisch gesperrte Hilfsprozesse bleiben getrennt sichtbar. Prozessabfragen erfolgen alle 500 ms; sehr kurzlebige Prozesse und delegierte Dienste können fehlen. „Nicht mehr beobachtet“ ist deshalb eine Beobachtung, keine garantierte Beendigungsdiagnose.

Netzblick startet keine untersuchte EXE mit seinen Administratorrechten. Bei Prüfende bleiben eigene Programmsperren bestehen. Aufheben unter „Programme → Windows-Standard“. Nach einem fehlgeschlagenen Prüfstart kann bereits eine Sperre bestehen; der Hinweis in der Ansicht erklärt dies.

## Wohin verbindet sich ein Programm?
In „Programme“ und „Programm prüfen“ bleiben IP-Adresse und Port sichtbar. Hinzu kommen:
- **Name / Bereich:** optional ein Reverse-DNS-Name oder die Einordnung „Dieser Computer“, „Privates Netz“, „Multicast“ usw.
- **Diensthinweis:** beispielsweise „TCP/443 · HTTPS / TLS möglich“. Das ist eine Port-Vermutung, keine Untersuchung des tatsächlichen Inhalts.
- **Verbindungsdetails:** Erklärung der Beobachtung und ihrer Grenzen.

„DNS-Namen ergänzen“ ist beim Start ausgeschaltet. Nach dem Einschalten fragt Netzblick den von Windows verwendeten DNS-Resolver ab. Diese zusätzlichen Anfragen können die betrachteten IP-Adressen an den konfigurierten DNS-Dienst übermitteln; sie stammen von Netzblick und nicht vom untersuchten Programm. Ausschalten startet keine weiteren Abfragen und blendet die Namen aus; bereits laufende Windows-Abfragen können noch zu Ende laufen. Namen werden nur im Arbeitsspeicher zwischengespeichert.

Pro Ansicht werden bis zu 100 Einträge ergänzt, mit höchstens vier gleichzeitig laufenden Systemabfragen. Der Cache enthält höchstens 256 Adressen für jeweils zehn Minuten. Länger laufende oder fehlgeschlagene Anfragen erscheinen ausdrücklich als offen beziehungsweise nicht verfügbar; sie blockieren die Oberfläche nicht. Multicast-, Broadcast-, Loopback- und unspezifizierte Adressen werden nicht abgefragt.

Ein Reverse-DNS-Name ist nicht automatisch der Domainname, den das Programm aufgerufen hat, und belegt weder Eigentümer noch Sicherheit. Dieselbe IP kann mehrere Kunden, Domains oder CDN-Dienste bedienen. Ein fehlender Name ist kein Verdachtsmerkmal. Ob eine Verbindung ein Update, eine Anmeldung, Inhalte oder Telemetrie betrifft, lässt sich aus IP, PTR und Port allein nicht verlässlich bestimmen.

## Überprüfung
- 2.233 Kernprüfungen mit dem Windows-.NET-Framework-Compiler bestanden, einschließlich DNS-Opt-in, Cache, Nebenläufigkeitslimit, ungültiger DNS-Antworten und bestehender Prüf-/Firewalllogik.
- Alle PowerShell-Dateien mit dem Windows-PowerShell-5.1-Parser geprüft.
- C# mit den tatsächlichen Startreferenzen kompiliert; alle WPF-Panels geladen.
- Fünf Prüfzustände mit Beispieldaten geprüft, Layout in zwei Fenstergrößen gerendert.
- Prozess-/Fensterabfrage ausgeführt; nur zugängliche Prozesse waren sichtbar.
- Der vollständige Starttest war in der eingeschränkten Ausführungsumgebung durch verweigerte Socket-Abfragen blockiert. Echte Firewalländerungen, Audit-Wiederherstellung und die komplette Gerätebedienung wurden für diese Version nicht getestet. Zunächst mit einem bekannten Programm prüfen.
