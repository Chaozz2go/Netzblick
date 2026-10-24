# Netzblick 0.6.0 – erst blockieren, dann entscheiden

**Testversion. Die neue Sperrfunktion wurde hier nicht mit echten Netzwerkfiltern aktiviert.** Logik, Kompilierung und Oberfläche sind geprüft; ein Windows-Gerätetest für die tatsächliche Sperrwirkung und Wiederfreigabe steht aus. Die Anzeige ist kein Sicherheitszertifikat.

## Der neue Ablauf
Die Startansicht „Zugriff entscheiden“ zeigt immer den aktuellen Modus:
- **Beobachten:** Der Kontrollmodus ist aus. Bestehende Windows-Firewallregeln gelten.
- **Kontrollmodus aktiv:** Die eigenen Sitzungsfilter wurden eingerichtet und zuletzt erfolgreich zurückgelesen; die Ereignisanzeige wird geprüft.
- **Mit Freigaben:** Du hast Programmpfade bewusst für ausgehenden Zugriff dieser Sitzung freigegeben.
- **Status / Anzeige nicht bestätigt:** Keine grüne Bestätigung und keine weitere Freigabe. Sperrfilter können noch aktiv sein; beenden und Meldung prüfen.

Der Status bleibt oben in jeder Ansicht sichtbar. Die Buttons zur Entscheidung bleiben auch beim Scrollen der Details im Blick.

## Aktivierung
„Kontrollmodus aktivieren“ zeigt zuerst die konkreten Auswirkungen. Erst deine Bestätigung richtet die Sitzung ein. Es gibt keine automatische Aktivierung beim Start.

Die Sitzung verwendet eigene dynamische Windows-Filtering-Platform-Filter (WFP) an den ALE-Verbindungsautorisierungsschichten für IPv4 und IPv6, ein- und ausgehend. Ohne Freigabe wird Verbindungsaufbau außerhalb desselben PCs zunächst blockiert. Das betrifft auch LAN, DNS, Updates und Windows-Dienste. Loopback-Kommunikation auf diesem PC ist ausdrücklich ausgenommen. Dies ist keine vollständige Isolation von Prozessen, Weiterleitungsdiensten, VMs oder fremden Netzwerk-Stacks.

Vorhandene Windows-Firewallregeln und Profil-Standardaktionen werden nicht umgeschrieben. Die WFP-Sitzungsfilter liegen in einer eigenen Ebene; Programmfreigaben sind in dieser Ebene höher gewichtet als die Grundsperre. Andere Windows-Sperren können eine Freigabe weiterhin verhindern. Eine andere Ebene mit gleicher höchster Priorität verhindert die Bestätigung beziehungsweise Aktivierung.

Die Änderungen werden für IPv4/IPv6 in einer WFP-Transaktion vorgenommen. Die App kontrolliert ihre Filter und Freigaben erneut während der Sitzung. Ein fehlgeschlagener Start versucht, die dynamische Sitzung zu schließen; ein nicht bestätigtes Ende bleibt als Fehler mit Beenden-Möglichkeit sichtbar.

## Anfragen verstehen und entscheiden
Die Ereignisanzeige verwendet neue Windows-Security-Blockereignisse 5157. Dazu wird bei Bedarf vorübergehend die WFP-Fehlerüberwachung systemweit aktiviert. Sie wird beim Sitzungsende zurückgestellt; die vorhandene Wiederherstellungsfunktion behandelt einen vorherigen Absturz beim nächsten Start.

Ausgehende Versuche werden nach vollständigem Programmpfad gesammelt, nicht mit einem Dialog je IP. Pro Karte stehen Programmpfad, letzte Ziel-IP/Port, Adressbereich, möglicher Dienst und die Herkunft des Blocknachweises. Die Filter-ID wird, soweit enthalten, mit den eigenen Grundsperren verglichen. Andere Blockereignisse werden nicht als Beweis für einen eigenen Netzblick-Filter ausgegeben. Eingehende Blockereignisse werden gezählt; sie sind keine ausgehenden Freigabeanfragen.

Du kannst:
1. **Weiter blockieren:** keine Freigabe einrichten. Wiederholungen bleiben gesammelt und verlangen nicht erneut dieselbe Entscheidung.
2. **Für diese Sitzung erlauben:** genau diesen lokalen EXE-Pfad für ausgehende Ziele freigeben. Danach die gewünschte Funktion im Programm erneut ausprobieren.
3. **Freigabe zurücknehmen:** die beiden eigenen ausgehenden IPv4-/IPv6-Freigaben entfernen. Die Grundsperre der aktiven Sitzung bleibt bestehen.

Eine Freigabe betrifft **alle Instanzen dieses EXE-Pfads und alle ausgehenden Ziele**, nicht nur eine angezeigte IP. Sie ist nicht an einen Datei-Hash gebunden. Bei Windows-Sammelprozessen weist die Bestätigung zusätzlich darauf hin, dass mehrere Dienste betroffen sein können. Nicht eindeutig zugeordnete Pfade, UNC-Ziele oder nicht mehr vorhandene Dateien werden nicht pauschal freigegeben.

Ein nach der Freigabe beobachteter neuer Block wird als Hinweis auf eine weitere Sperre sichtbar. Eine Freigabe ist kein Nachweis erfolgreicher Übertragung. Die Rückfrage hält keine Verbindung offen: Ein bereits abgewiesener Verbindungsversuch muss vom Programm erneut versucht werden.

## Warum möchte ein Programm ins Netz?
Die Oberfläche führt durch drei Fragen:
- Habe ich gerade eine Online-Funktion benutzt?
- Funktioniert das, was ich brauche, auch mit blockiertem Zugriff?
- Fehlt etwas, das ich durch eine zeitweise Freigabe gezielt ausprobieren möchte?

DNS-Name und Port können Hinweise geben, beweisen aber nicht Update, Anmeldung, Inhalte oder Telemetrie. Diensthinweise bleiben als „möglich“ gekennzeichnet. DNS-Namen sind optional; ihre Abfragen stammen von Netzblick und können im Kontrollmodus selbst blockiert werden oder zusätzliche Anfragen erzeugen. Netzblick erhält dafür keine automatische Ausnahme.

## Aktive und neue Verbindungen
„Beobachtete Verbindungen“ zeigt Socket-Einträge getrennt von den blockierten Anfragen. Neu in der Stichprobe auftauchende Einträge sind kurz als **neu beobachtet** markiert. Das ist keine garantierte Erfassung jedes Verbindungsstarts. Ein TCP-Socketstatus „Verbunden“ ist keine Messung laufender Datenübertragung.

Vor der Aktivierung vorhandene Einträge werden entsprechend gekennzeichnet. Änderungen an ALE-Filtern führen laut Windows-Dokumentation zur erneuten Autorisierung bestehender Flows bei einem folgenden Paket. Netzblick zeigt bestehende Verbindungen dennoch nicht ohne tatsächlichen Gerätetest als sicher getrennt an. Die Liste ersetzt keine Paketprüfung.

Die Aktivitäts-Pause friert die passive Socket-Anzeige ein. Kontrollmodus, seine Statusprüfung und neue Blockanfragen aktualisieren weiter. Die Liste kennzeichnet eine pausierte Anzeige ausdrücklich.

## Sitzungsende und Grenzen
„Zurück zu Windows-Standard“ beendet nur die eigenen vorübergehenden WFP-Sperren und -Freigaben; vorhandene Windows-Firewallregeln bleiben maßgeblich. Dauerhafte manuell gesetzte Netzblick-Programmsperren bleiben ebenfalls bestehen. Beim Schließen fragt Netzblick wegen des aktiven Kontrollmodus nach.

Dynamische WFP-Objekte werden von Windows auch beim Ende des besitzenden Prozesses entfernt. **Nach Beenden, Absturz oder Neustart ist dieser Kontrollmodus deshalb nicht mehr aktiv.** Er ersetzt keinen permanenten Firewall-Dienst. Eine Audit-Wiederherstellung nach einem Absturz kann beim nächsten Netzblick-Start noch erforderlich sein.

Maximal 512 Programmanfragen, 20 Beispielziele je Programm und 4096 ungearbeitete Blockereignisse. Fehlende Zuordnungen, Pufferverluste oder die Programmgrenze führen zu einem Hinweis statt einer vollständigen Schutzbestätigung. Socket-Ansicht: bis 1000 Einträge. Die Funktion benötigt 64-Bit-Windows-PowerShell und Administratorrechte.

## Geprüft / noch zu prüfen
Bestanden:
- 2.256 Kernprüfungen mit dem Windows-.NET-Framework-Compiler, einschließlich Gruppierung, Freigabe/Rücknahme, verspäteter Ereignisse, Pfadgrenzen und Kapazitätsmeldungen.
- PowerShell-Syntax, C#-Kompilierung mit den tatsächlichen Startreferenzen und Laden aller WPF-Panels.
- Windows-x64-Strukturlayout der verwendeten WFP-API.
- UI-Ablauf mit Fakes: aus, blockierte Anfragen, Freigabe, Rücknahme, unbestätigter Filter, fehlgeschlagener und erfolgreicher Sitzungsabschluss.
- Gerenderte Ansichten in zwei Fenstergrößen.
- Reproduzierbar: tools/Test-UI.ps1 verwendet nur Beispieldaten/Fakes für den Kontrollmodus und richtet keine WFP-Filter oder Audit-Sitzung ein.

**Nicht geprüft:** echte WFP-Filterinstallation, Sperrwirkung für TCP/UDP/IPv4/IPv6, reale Ereigniszustellung, echte Freigabe/Rücknahme, bestehende Verbindungen, Zusammenspiel mit VPNs/fremden Filtern und Sitzungsbereinigung bei einem echten Prozessabbruch. Der vollständige Geräte-Test ist erforderlich, bevor man sich auf die neue Funktion verlässt.

Für den ersten Gerätetest einen lokal bedienten Testrechner verwenden, keine Fernwartungssitzung. Ein bekanntes Testprogramm zu einem kontrollierten Testziel verbinden lassen, dann ohne Freigabe, mit Sitzungsfreigabe, nach Rücknahme und nach Modusende vergleichen. Die tatsächliche Kommunikation auch auf der Gegenstelle beziehungsweise mit einem unabhängigen Mitschnitt prüfen. IPv4, IPv6 und UDP separat prüfen; fehlende IPv6-Konnektivität nicht als erfolgreiche IPv6-Sperre werten.

## Microsoft-Referenzen
- [WFP-Objekte und dynamische Sitzungen](https://learn.microsoft.com/en-us/windows/win32/fwp/object-management)
- [Filterreihenfolge und Freigabe-/Sperrentscheidungen](https://learn.microsoft.com/en-us/windows/win32/fwp/filter-arbitration)
- [Erneute Autorisierung bestehender Verbindungen](https://learn.microsoft.com/en-us/windows/win32/fwp/ale-re-authorization)
- [Windows-SDK-Definitionen](https://github.com/microsoft/win32metadata/tree/main/generation/WinSDK/RecompiledIdlHeaders)
