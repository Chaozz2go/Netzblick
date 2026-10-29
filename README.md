# Netzblick

**Sehen, welche Programme ins Netzwerk wollen – und selbst entscheiden, was sie dürfen.**

Netzblick ist eine Windows-App, mit der du Netzwerkverbindungen deiner Programme ansehen, Zugriffe sperren oder freigeben und neue Software vor dem ersten Netzwerkzugriff prüfen kannst. Eine Ampel direkt am Programmnamen zeigt den aktuellen Netzblick-Zugriff. Erfasste Blockversuche bleiben sichtbar, damit du nachvollziehen kannst, was gesperrt wurde und warum.

## Download für Windows

**[Neueste Version herunterladen →](https://github.com/Chaozz2go/Netzblick/releases/latest)**

| Variante | Download | Für wen? |
| --- | --- | --- |
| **Installierbar** | [Setup-EXE herunterladen](https://github.com/Chaozz2go/Netzblick/releases/latest/download/Netzblick-Setup-0.18.0-win-x64.exe) | Für die regelmäßige Nutzung: mit Startmenü, Hintergrunddienst und Tray-Autostart. |
| **Portabel** | [Portable ZIP herunterladen](https://github.com/Chaozz2go/Netzblick/releases/latest/download/Netzblick-Portable-0.18.0-win-x64.zip) | Entpacken und `Netzblick.exe` starten. Ohne Installation eines Dienstes oder Autostarts; Einstellungen bleiben im Ordner daneben. |

**Voraussetzungen:** Windows 10/11 mit 64 Bit, .NET Framework 4.8 und Windows PowerShell 5.1. Für Netzwerküberwachung und Firewallsteuerung sind Administratorrechte nötig. Python oder eine zusätzliche PowerShell-Installation werden nicht benötigt.

Die fertigen Pakete findest du unter **Releases**. Der grüne GitHub-Knopf **Code → Download ZIP** lädt den Quellcode herunter.

## Das Dashboard: dein Netzwerk live

Die Startseite zeigt alle aktuell erfassten aktiven Programme mit ihren lokalen EXE-Icons rund um deinen PC. Die Linien führen zu zusammengefassten lokalen oder Internet-Gegenstellen. **Mausrad** zoomt am Mauszeiger, **Ziehen auf freier Fläche** verschiebt die Ansicht. **Alles anzeigen** passt alle aktiven Programme ein; **Auswahl zentrieren** macht die gewählte App lesbar. Die Plätze bleiben während der Sitzung fest und wechseln nicht mit der Datenrate. Zoom und Ausschnitt bleiben bei Live-Updates erhalten. Pfeile zeigen sicher erfassten **ausgehenden oder eingehenden Verbindungsaufbau**; blockierte Versuche erscheinen rot gestrichelt. Ohne sicheren Richtungsnachweis bleibt die Verbindung als unbekannt markiert.

Ein Klick auf ein Programm zeigt seine Ziele, aktuellen Zugriffsstatus, Datenrate und Prüfgründe. **Programmdetails** und **Zeitweise sperren** führen zu den bestehenden Aktionen. Die Zähler öffnen aktive Programme, den letzten erfassten Blockversuch oder die Prüfliste.

Zwei große Graphen zeigen **Empfang und Versand der Netzwerkadapter** für 60 Sekunden, drei oder fünf Minuten. Virtuelle/VPN-Adapter können Daten doppelt zählen; die Programmwerte rechts stammen getrennt aus der ETW-Erfassung. **Einfrieren** hält nur das Dashboard an, Erfassung und Filter laufen weiter. Die Historie liegt begrenzt im Arbeitsspeicher und wird nicht dauerhaft gespeichert.

**Wichtig:** Ein Browser kann eine ausgehende Verbindung aufbauen und darüber Daten empfangen. Empfang/Versand und Verbindungsaufbau sind deshalb getrennte Anzeigen. In der Programmliste steht eine Richtungszusammenfassung; die Verbindungstabelle bietet **Alle, Ausgehend, Eingehend, Lauschend und Unbekannt** als Filter. Ein lauschender Socket ist noch keine eingehende Verbindung. Bereits vor dem Erfassungsstart bestehende TCP-Verbindungen sowie UDP-Beobachtungen können ohne sicheren Aufbau-Nachweis unbekannt bleiben.

## Was kannst du damit machen?

- **Programme und Verbindungen ansehen:** Nach Name oder Dateipfad suchen, aktive Programme finden und Ziele, Ports, Protokolle, Richtung sowie verfügbare Datenmengen prüfen.
- **Sperren und Freigaben schnell ändern:** Gesperrte und noch ungeprüfte Programme filtern. Ein Programm dauerhaft sperren, erlauben oder auf den Windows-Standard zurücksetzen. Die Zähler **Programme**, **gesperrt** und **zu prüfen** filtern die Liste per Klick. Eigene Änderungen lassen sich unter den angezeigten Bedingungen rückgängig machen.
- **Ein Programm zeitweise offline nehmen:** Zum Beispiel Steam für 10, 30 oder 60 Minuten oder bis zur manuellen Aufhebung sperren. Anschließend werden die vorherigen Netzblick-Programmregeln wiederhergestellt. Auch eine Freigabe für zehn Minuten ist möglich.
- **Neue Software vor dem Start prüfen:** Eine EXE auswählen, zuerst sperren und erst danach selbst starten. So kannst du ihre erfassten Netzwerkversuche ansehen und benötigte Verbindungen gezielt freigeben.
- **Neue Programme bewerten:** Optional auf neue Programme hinweisen lassen, direkt zu ihren Details wechseln und sie als geprüft markieren. In derselben Prüfliste stehen auch bekannte Programme mit neuen Zielen oder Blockversuchen. Der konkrete Grund steht beim Namen; **Prüfdetails ansehen** zeigt die ungeprüften Ziele und Versuche. Die Prüfmarke allein verändert keine Netzwerkregel.
- **Erst fragen, dann verbinden:** Optional neue externe Verbindungen ohne passende Netzblick-Freigabe sperren. Anfragen lassen sich nach Programm, Ziel-IP, Richtung, Protokoll und Port prüfen und mit benannten Regeln freigeben. Standardmäßig wird zunächst zugelassen und anschließend geprüft.
- **Sperrgründe nachvollziehen:** Bei erfassten Blockversuchen Ziel, Zeitpunkt, Anzahl und verfügbaren Windows-Filter bzw. Netzblick-Regel ansehen. Fehlende Zuordnungen werden als solche angezeigt.
- **Ziele auf der Weltkarte ansehen:** Grobe Länderzuordnung der Gegenstellen, mit Mausrad-Zoom und Verschieben der Karte. Ping und Traceroute stehen für weitere Prüfungen bereit.
- **Frisch anfangen:** Mit **Alles neu prüfen …** eigene Entscheidungen und Prüfmarken nach Bestätigung zurücksetzen. Vorher werden Sicherungen angelegt; fremde Windows-Firewallregeln bleiben erhalten.
- **Berichte mitnehmen:** Ansichten und Messdaten bei Bedarf exportieren, unter anderem als CSV.

### Die Ampel beim Programmnamen

| Farbe | Bedeutung |
| --- | --- |
| 🟢 Grün | Netzblick lässt den Zugriff durch. Andere Windows- oder Sicherheitsregeln können weiterhin sperren. |
| 🟡 Gelb | Der Zugriff ist teilweise eingeschränkt. |
| 🔴 Rot | Das Programm ist durch Netzblick gesperrt. |
| ⚪ Grau | Der aktuelle Filterstatus ist nicht bestätigt. |

**„Noch ungeprüft“ ist eine eigene Prüfliste.** Ein grüner Status bedeutet weder „sicheres Programm“ noch, dass nie eine Verbindung blockiert wurde. Frühere Blockversuche werden getrennt vom aktuellen Zugriff angezeigt.

## So startest du

1. **Setup installieren** oder die **portable ZIP vollständig entpacken** und `Netzblick.exe` starten. Beide Varianten nicht gleichzeitig verwenden.
2. Unter **Programme** eine App auswählen. **Details öffnen** bzw. die Future-Ansicht zeigt Übersicht, Verbindungen und Regeln.
3. Netzwerkziele und erfasste Blockversuche ansehen. Über **Zugriff ändern** oder die angebotenen Aktionen sperren, erlauben oder zeitweise entscheiden.
4. Wenn du eine neue EXE vorab untersuchen möchtest, **Programm prüfen** öffnen und **Vor dem Start sperren** verwenden. Erst nach bestätigter Sperre das Programm starten.

Der optionale Nachfragemodus unter **Einrichten & testen** betrifft auch LAN, DNS und Windows-Dienste. Er besitzt einen Zwei-Minuten-Sicherheitsrückweg, damit du die Einrichtung zunächst lokal testen kannst. Nach einer Freigabe musst du den vorher gesperrten Verbindungsversuch erneut auslösen.

## Dein Design: Clean oder Future

**Future ist bei einer neuen Einrichtung der Standard.** Eine bereits gespeicherte Designwahl bleibt erhalten. Links unten unter **Design** kannst du jederzeit wählen:

- **Clean:** die schlichte, aufgeräumte Oberfläche.
- **Future:** eine technische Gestaltung mit türkisfarbenen Akzenten, echten Programm-Icons aus den lokalen EXE-Dateien und Programmliste und Details nebeneinander. Dazu kommen Statuskarten und eine kompakte Offline-Weltkarte.

**Hell und Dunkel sind in beiden Designs separat wählbar.** Deine Auswahl bleibt gespeichert. Ein Designwechsel ändert keine Firewallregeln.

## Hintergrundbetrieb und Updates

Fenster schließen oder minimieren blendet Netzblick in den **System-Tray** neben der Windows-Uhr aus. Über das Tray kannst du die Oberfläche wieder öffnen oder **Netzblick vollständig beenden**.

Unter **Updates → Auf Updates prüfen** findet Netzblick öffentliche GitHub-Releases ohne Konto oder Token. Die Prüfung erfolgt auf deinen Klick; die App öffnet die Downloadseite und installiert nichts ungefragt.

Beim Update Netzblick über das Tray vollständig beenden. Danach das neue Setup ausführen bzw. die entpackten portablen Programmdateien ersetzen. Den portablen Ordner **`Netzblick-Daten` behalten**. Auch das Setup erhält bestehende Einstellungen. Prüfsummen stehen bei jeder Veröffentlichung in `SHA256SUMS.txt`.

## Offline und lokal

Die Überwachung, Regelsteuerung und Länderkarte funktionieren ohne Cloudkonto. Netzblick versendet keine Telemetrie. Programm-Icons werden lokal gelesen. Die Updateprüfung benötigt Internet; optionale DNS-Namensauflösung, Ping und Traceroute erzeugen Netzwerkverkehr. Die DNS-Namensauflösung ist zunächst ausgeschaltet.

## Was du wissen solltest

Netzblick hilft dir, Netzwerkzugriffe zu beurteilen und zu steuern. Es ist **kein Virenscanner und keine Sandbox**: Dateien, Browser-Inhalte und der fachliche Zweck einer Verbindung werden dadurch nicht automatisch bewertet.

- Regeln betreffen den **EXE-Pfad**. Hilfsprogramme mit anderen EXE-Dateien werden separat behandelt. Loopback-Verbindungen auf demselben PC bleiben ausgenommen.
- Sperren gelten für neue externe Verbindungen. Bereits offene Verbindungen werden nicht garantiert getrennt. Für einen Offline-Test das Programm nach dem Sperren neu starten.
- Die Netzblick-Filtersteuerung muss laufen. Beim vollständigen Beenden, bei einem Dienstabsturz und vor dem Dienststart besteht keine lückenlose Netzblick-Sperre. Gespeicherte Regeln werden beim nächsten Start wieder geladen.
- Blockanzeige und Datenmessung hängen von der verfügbaren Windows-Erfassung ab. Eine leere Liste beweist nicht, dass keine Verbindung versucht wurde.
- Die Karte zeigt grobe Länderzuordnungen, keine exakten Serverstandorte oder gemessenen Datenwege. Verschlüsselte Inhalte werden nicht entschlüsselt.
- Die veröffentlichten Pakete sind derzeit **noch nicht mit einem Herausgeberzertifikat signiert**. Windows kann deshalb eine SmartScreen-Warnung anzeigen. Eine geplante Codesignatur ist noch kein Bestandteil der Downloads.

Windows-Builds prüfen unter anderem Oberfläche, native Sperr- und Freigabefunktionen, Installation, Update und Deinstallation. Details zu den geprüften Fällen und verbleibenden Grenzen stehen im [Prüfstand](PRUEFSTAND.txt).

## Hilfe, Hintergründe und Entwicklung

- [Bedienung und technische Details](docs/Bedienung-und-Technik.md)
- [Neuerungen in Version 0.18.0](docs/Release-0.18.0.md)
- [Alle Veröffentlichungen](https://github.com/Chaozz2go/Netzblick/releases)
- [Fehler melden oder eine Idee vorschlagen](https://github.com/Chaozz2go/Netzblick/issues)
- [Drittanbieter und Datenlizenzen](THIRD-PARTY-NOTICES.txt)

Für Entwickler: `tools/Build-Desktop.ps1` erstellt die Windows-EXE; `installer/Netzblick.iss` baut mit Inno Setup 6 das Setup. Die automatisierten Prüfungen liegen unter `tools` und in den GitHub-Actions-Workflows. Die Windows-Pakete lassen sich direkt nutzen, ohne das Projekt selbst zu kompilieren.

### Hostprozesse & Dienste (ab 0.17.0)

Eigene Übersicht für laufende Windows-Dienstprozesse mit PID, Startzeit, Dienstnamen, aufklappbaren Windows-Beschreibungen und Prozessverbindungen. Sperrgründe und Regeln bleiben klar als gemeinsame Angaben zum Dateipfad gekennzeichnet. Ohne KI und ohne Cloud-Abhängigkeit. Details: [Release 0.17.0](docs/Release-0.17.0.md).

### Prüfen & Favoriten (ab 0.18.0)

Ein geführter Prüfassistent, angeheftete Programme mit Restzeit zeitweiser Sperren, eine Vorschau vor Regeländerungen und ein lokaler Programm-Zeitstrahl erleichtern die Bewertung. Technische Grenzen und Speicherung: [Release 0.18.0](docs/Release-0.18.0.md).

### In Vorbereitung: klare Bereiche, Programmgruppen und Sicherungen (0.19.0)

Eine kompaktere Hauptnavigation, ausdrücklich bestätigte EXE-Gruppen, lokale Sicherungen mit kategorieweiser Wiederherstellung und Hinweise auf Dateiänderungen erleichtern die tägliche Nutzung. Details und Grenzen: [Release 0.19.0](docs/Release-0.19.0.md). Die Downloadlinks oben zeigen bis zur Veröffentlichung weiter auf 0.18.0.
