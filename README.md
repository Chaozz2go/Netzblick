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

**Sperren** setzt in einer Diensttransaktion zwei dauerhafte Netzblick-Regeln für alle neuen externen Verbindungen des gewählten EXE-Pfad…29222 tokens truncated…APS zum DC",Path=path,Direction="Ausgehend",Address="10.0.0.10",Protocol=6,Port=636,Action="Allow",ExpiresUtc=DateTime.UtcNow.AddMinutes(5)});status.RecoveryUtc=DateTime.UtcNow.AddMinutes(2);}
  }
  public static SetupStatus Send(SetupCommand command){
   LastOperation=command.Operation;
   if(command.Operation=="Status"||command.Operation=="Recheck")return status;
   if(command.Operation=="Watch"){if(!status.Verified)throw new InvalidOperationException("Test: Filterprüfung fehlgeschlagen");status.Config.WatchedPaths.Add(command.Path);return status;}
   if(command.Operation=="AllowProgram"){SetupChanges.AllowProgram(status.Config,command.Path);return status;}
   if(command.Operation=="BlockProgram"){SetupChanges.BlockProgram(status.Config,command.Path);return status;}
   if(command.Operation=="ProgramDefault"){SetupChanges.ProgramDefault(status.Config,command.Path);return status;}
   if(command.Operation=="Unwatch"){status.Config.WatchedPaths.Remove(command.Path);return status;}
   if(command.Operation=="Remove"){status.Config.Rules.RemoveAll(r=>r.Id==command.RuleId);return status;}
   if(command.Operation=="Ask"){status.Config.Ask=command.Enabled;return status;}
   if(command.Operation=="Reset"){status.Config=new SetupConfig();status.Attempts.Clear();status.History.Clear();return status;}
   throw new InvalidOperationException("UI-Fixture erlaubt diesen Befehl nicht.");
  }
 }
}

