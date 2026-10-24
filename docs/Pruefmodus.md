## Programm vorab sperren und prüfen

Im Reiter **Programm prüfen** wird eine lokale EXE ausgewählt und vor ihrem ersten Teststart gesperrt. Netzblick startet die Datei niemals selbst. So wird ein fremdes Programm nicht versehentlich mit den Administratorrechten der Beobachtungsoberfläche ausgeführt.

1. EXE auswählen. Netzblick liest Hersteller-/Versionsangaben der Datei, den SHA-256 und einen gegebenenfalls eingebetteten Zertifikatsunterzeichner. Herstellerangaben sind selbst deklarierte Dateimetadaten. Ein ausgelesener Unterzeichner ist **keine** Prüfung von Vertrauen, Gültigkeit oder Unbedenklichkeit; Katalogsignaturen werden nicht geprüft. Der Hash gehört zur Datei zum Auswahlzeitpunkt.
2. **Sperren und prüfen** anklicken. Das Programm muss vorher geschlossen sein. Netzblick prüft die aktiven Firewallprofile und die Verwendbarkeit lokaler Regeln, setzt zwei dauerhafte Regeln für den EXE-Pfad und aktiviert für die Sitzung die Windows-Fehlerüberwachung „Filtering Platform Connection“. Die bisherige Erfolgsüberwachung bleibt dabei erhalten. Wenn eine bestehende eigene Regel verändert oder die lokale Richtlinie eingeschränkt ist, wird der Prüfstart abgebrochen.
3. Die EXE anschließend selbst aus einem normalen Explorer starten, ohne zusätzliche Administratorrechte. Netzblick zeigt zugeordnete blockierte Verbindungsversuche als rote gestrichelte Beziehungen, Länderkarte und Zeitverlauf. Das Security-Ereignis 5157 enthält unter anderem Anwendung, PID, Richtung, Quell- und Zieladresse sowie Protokoll. Es enthält keine übertragenen Nutzdatenmengen.
4. Hilfsprozesse erscheinen in einer eingerückten Prozessübersicht. Sie sind zunächst nur beobachtet und ausdrücklich **nicht automatisch durch die EXE-Sperre geschützt**. Mit **Gewählten Prozesspfad sperren** kann ein solcher Pfad nach Bestätigung zusätzlich gesperrt werden. Vor der Erkennung kann er bereits kommuniziert haben; die Regel betrifft alle Instanzen der gewählten Datei.
5. **Prüfung beenden** beendet die Erfassung und stellt die zuvor gesicherte Audit-Einstellung wieder her. Alle gesetzten Programmsperren bleiben aktiv. Während einer Prüfung verhindert Netzblick das Aufheben zugehöriger Sperren über seine eigene Oberfläche. Nach dem Beenden können sie unter **Programme → Eigene Regeln** wieder entfernt werden.
6. **Bericht** speichert Metadaten, Zeitrahmen, Status, Zähler, Prozessübersicht und die letzten 2000 zugeordneten Ereignisse als lokale JSON-Datei. Der globale CSV-Export exportiert in diesem Reiter die Ereignistabelle. Ohne Export ist die Prüfsitzung nach dem Schließen nicht mehr verfügbar.

**Wichtige Unterscheidung:** Ein WFP-Block ist ein blockierter Versuch, keine bestätigte Übertragung. Die Ansicht zeigt gesendete und empfangene Bytes deshalb als **nicht gemessen**; sie behauptet nicht „0 Bytes“ oder „sicher“. Ein leerer Verlauf bedeutet nur, dass keine passenden Ereignisse erfasst wurden. Aus der Zahl lässt sich kein Nachweis ableiten, dass niemals Daten den PC verlassen haben.

**Grenzen der Zuordnung:** Prozessbeziehungen werden alle 500 ms beobachtet und mit PID plus Startzeit verfolgt, um die Wiederverwendung von PIDs zu berücksichtigen. Sehr kurzlebige Prozesse, schon wieder beendete Eltern, nicht auslesbare Prozesse oder an vorhandene Dienste delegierte Aufgaben können fehlen. Dazu gehört insbesondere Verkehr, den ein Windows-Dienst stellvertretend erzeugt. Die Sperre eines Pfads ist daher keine vollständige Isolation eines ganzen Programmsystems und keine Sandbox. Bei ernsthaft verdächtiger Software eine isolierte Testumgebung verwenden.

Die Ereignisüberwachung selbst arbeitet ereignisbasiert, auch für UDP-Blockversuche; sie ist nicht die Zwei-Sekunden-TCP-Liste. Unzugeordnete Ereignisse werden nur kurz im Arbeitsspeicher gepuffert und nicht in den Bericht übernommen. Prozesshistorie: maximal 1024 Instanzen. Die Anzeige behält die letzten 2000 zugeordneten Ereignisse, während die Sitzungszähler weiterlaufen. Volle Erfassungspuffer, Lesefehler, eine geänderte Audit-Einstellung oder eine verlorene eigene Sperre werden als Einschränkung angezeigt. Die Diagramme beruhen auf den behaltenen Ereignissen und sind keine Paket- oder Bytezählung.

Die Kartenpositionen sind weiterhin Länderpunkte. Eine rote Linie bedeutet einen blockierten Zielversuch, keinen geografisch gemessenen Leitungsweg. Quelle der Länderzuordnung: DB-IP Country Lite, CC BY 4.0; Umrisse/Länderpunkte: Natural Earth.

### Audit-Wiederherstellung

Windows protokolliert während dieser Sitzung systemweit fehlgeschlagene WFP-Verbindungen im vorhandenen Security-Protokoll; nur die Netzblick-Anzeige wird auf die Prüfsitzung gefiltert. Das Systemprotokoll kann dabei wachsen. Netzblick löscht oder leert das Security-Protokoll nicht. Wenn Fehlerüberwachung schon aktiv war, ändert Netzblick sie nicht.

Nur wenn Netzblick die Einstellung ändern muss, speichert es vorher Original- und angewandte Flags atomar als `State` (Binärwert) unter `HKLM\SOFTWARE\Netzblick\InspectionAuditRecovery` in der 64-Bit-Registry. Das ist eine Wiederherstellungsnotiz, kein Autostart und kein installierter Dienst. Ein benannter Mutex verhindert parallele Prüfungen durch mehrere Netzblick-Instanzen.

Nach einem Absturz wird die Notiz beim nächsten Netzblick-Start erkannt und die alte Einstellung wiederhergestellt, wenn die aktuelle Einstellung der von Netzblick gesetzten oder bereits ursprünglichen Einstellung entspricht. **Bis zu diesem nächsten Start kann die zusätzliche Fehlerüberwachung aktiv bleiben.** Programmsperren sind davon unabhängig und bleiben bestehen.

Wenn zwischenzeitlich eine Gruppenrichtlinie oder eine andere Administration die Einstellung verändert hat, überschreibt Netzblick diese Änderung nicht. Die Oberfläche meldet die gesicherte, gesetzte und aktuelle Flag-Kombination; die Wiederherstellungsnotiz bleibt zur manuellen Klärung erhalten. Erfolgs-/Fehlerflags: Erfolg `1`, Fehler `2`, beide `3`, keine Überwachung `4` (kanonische Darstellung). Es wird niemals die gesamte Audit-Richtlinie zurückgesetzt.

Zum Anzeigen der aktuellen Unterkategorie in einer administrativen Konsole:

```text
auditpol /get /subcategory:"{0CCE9226-69AE-11D9-BED3-505054503030}"
```

Bei einem Konflikt zuerst die im Netzblick-Hinweis genannten Werte und etwaige Unternehmensrichtlinien prüfen. Keine pauschale Deaktivierung oder Rücksetzung vornehmen. Nach manueller Wiederherstellung auf die ursprüngliche Einstellung Netzblick erneut starten; die bereits richtige Einstellung wird erkannt und die erledigte Wiederherstellungsnotiz entfernt. Scheitert das Wiederherstellen selbst, nennt die Oberfläche den Fehler und der Zustand bleibt nachvollziehbar.

