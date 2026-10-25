# Netzblick 0.11.0 – Windows-EXE, portabel und installierbar

**Entwicklungsversion für lokal bediente Windows-Testgeräte.** Die Oberfläche wurde vereinfacht und die Regelsteuerung in einen eigenen Windows-Dienst verlagert. Kompilierung und Logikprüfungen bestehen; die reale WFP-Sperrwirkung und der Dienstbetrieb müssen vor einem produktiven Einsatz auf Windows geprüft werden. Kein Ersatz für einen Gerätetest, Virenschutz oder eine Sandbox.

## Sperren und Freigaben auf einen Blick (0.11.0)

In **Aktivität → Sperren & Freigaben** siehst du auch beendete Programme mit gespeicherten Regeln. Filter: Gesperrt, Teilweise eingeschränkt, Erlaubt, Windows-Standard und Noch ungeprüft. Suche über Name oder EXE-Pfad. Prüfsperren und die globale Sperre ohne Freigabe erscheinen zusätzlich als einzelne Einträge.

- **Programm erlauben** ersetzt nach Bestätigung alle eigenen Dienstregeln und Prüfsperren dieses Pfads durch dauerhafte Freigaben für beide Richtungen, alle Ziele und Protokolle.
- **Programm sperren** setzt eigene ein- und ausgehende Sperren.
- **Auf Standard zurücksetzen** entfernt nur eigene Dienstregeln dieses Pfads. Bei aktivem Nachfragen ist danach wieder eine Freigabe nötig.
- Einzelne Regeln/Prüfsperren lassen sich separat zurücknehmen. Alte Netzblick-Windows-Regeln haben einen eigenen direkten Zugang und werden nicht stillschweigend überschrieben.

Status gilt für neue externe Verbindungen und die eigene Netzblick-Konfiguration. Loopback bleibt ausgenommen. Windows-/Fremdfilter können zusätzlich sperren; vorhandene Verbindungen müssen ggf. neu aufgebaut werden. Bei nicht bestätigtem Dienst wird keine Sperrwirkung behauptet und Änderungen sind deaktiviert. „Noch ungeprüft“ ist unabhängig davon, ob das Programm gesperrt ist.

## Netzwerkfilter gemeinsam verwenden (0.10.1)

Eine weitere WFP-Ebene mit derselben angeforderten Priorität deaktiviert Netzblick nicht mehr pauschal. Windows kann den nächstfreien Prioritätswert vergeben; Netzblick liest diesen nach dem Anlegen seiner leeren Ebene zurück und prüft danach gegen diesen tatsächlichen Wert. Netzblick prüft seine eigenen Filter weiter vollständig zurück und untersucht bei geplanten Sperren die passenden aktiven Filter auf den betroffenen ALE-Ebenen.

Normale parallele Freigaben und eindeutig andere EXE-Pfade verhindern die Prüfung nicht. Eine statische, nicht übersteuerbare Fremdfreigabe, die sich von der geplanten Sperre nicht eindeutig trennen lässt, wird vor der Änderung mit Ebene und Filtername gemeldet. Unbekannte Bedingungen werden konservativ als mögliche Überschneidung behandelt. Bei dynamischen Treiberentscheidungen bleibt ein Hinweis sichtbar; diese lassen sich ohne eigenen Treiber nicht vollständig vorhersagen. Fremde Regeln werden weder verändert noch entfernt. „Bestätigt“ bezeichnet die eingerichteten und zurückgelesenen Netzblick-Regeln, keine Garantie für jeden fremden Netzwerk-Stack.

Die Windows-Prüfung erzeugt isoliert eine zweite dynamische WFP-Ebene mit derselben maximal angeforderten Priorität: leerer Peer, parallele Soft-Permit-Regel, Hard-Permit-Regel für eine andere EXE, echte TCP-Sperre/Freigabe sowie Zurückweisen eines überlappenden Hard Permit. Danach werden unveränderte Peer-Filter und deren eigener Sitzungsabbau geprüft. Release-Pakete werden erst nach den Interaktions- und nativen Diensttests in demselben Build bereitgestellt.

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

Windows 10/11 x64, .NET Framework 4.8 und Windows PowerShell 5.1 (auf unterstützten Windows-Systemen vorhanden). Kein zusätzlicher Download beim Start. Die EXE verwendet den Windows-PowerShell-Motor intern; es öffnet sich kein PowerShell-Fenster. Kernkomponenten sind vorkompiliert. Die bisher…28222 tokens truncated…ortedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>
'@ | Set-Content -LiteralPath ($exe+'.config') -Encoding UTF8
foreach($file in @('README.md','PRUEFSTAND.txt','THIRD-PARTY-NOTICES.txt')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $OutputDirectory}
Copy-Item -LiteralPath (Join-Path $root 'lib') -Destination (Join-Path $OutputDirectory 'licenses') -Recurse -Force
Get-ChildItem -LiteralPath (Join-Path $OutputDirectory 'licenses') -Recurse -File | Where-Object {$_.Extension -in @('.dll','.exe')} | Remove-Item -Force
[void][IO.Directory]::CreateDirectory((Join-Path $OutputDirectory 'lib'))
Copy-Item -LiteralPath (Join-Path $root 'lib\Netzblick.Service.exe') -Destination (Join-Path $OutputDirectory 'lib')
Write-Output ('PASS: Windows x64 EXE mit eingebetteten Komponenten: '+$exe)
