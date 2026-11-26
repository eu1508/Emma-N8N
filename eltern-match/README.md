# Eltern-Match Wächter

Überwacht das Eltern-Match von Dalino Kids rund um die Uhr und schreibt Emma per Telegram, sobald etwas nicht stimmt.

Datei zum Importieren: `ELTERN_MATCH_WAECHTER.json`

## Was der Wächter macht

| Teil | Wann | Was |
| --- | --- | --- |
| **Regelprüfung** | alle 30 Minuten | Holt die letzten **100** Eltern-Match-Mails (30 Tage) aus info@dalinowellness.de und prüft sie (siehe unten). Bei einem Fund geht eine Telegram-Nachricht an Emma. Jeder Fund wird nur **einmal** gemeldet. |
| **Störungsmelder** | sofort bei jedem Fehler | Error-Trigger: Bricht der Eltern-Match-Workflow (oder ein anderer Workflow, der den Wächter als Error-Workflow nutzt) ab, kommt sofort eine Telegram-Nachricht mit Workflow, Schritt und Fehlertext. |
| **Emma-Qualitätsprüfung** | täglich 8 Uhr | Gemini prüft je Mailtyp eine gesendete Mail der letzten 24 h auf Recht, Stil und Logik. Telegram nur, wenn Emma „PROBLEM“ meldet. |
| **Status für Emma & Jarvis** | auf Abruf | `GET https://<euer-n8n>/webhook/eltern-match-status` liefert den letzten Lauf als JSON (Anzahl Störungen, aktive Profile, bestätigte Opt-ins, noch aktive Testprofile). Zusätzlich landet jeder Lauf in der Metropolis-SQLite-Tabelle `eltern_match_waechter`. |

„Pro 100“ ist so umgesetzt: Jeder Lauf prüft ein Paket von höchstens 100 Mails (Gmail-Limit pro Abruf). Bei mehr Verkehr den Takt verkürzen, nicht das Paket vergrößern.

### Geprüfte Regeln

**Recht (DSGVO/UWG)**
- Werbeblock („Neues aus der Dalino-Welt“, Longevity, HBOT) nur an Adressen mit bestätigtem Double-Opt-in (`NEUIGKEITEN JA`, abgemeldet mit `KEINE WERBUNG`). Verstoß = Störung.
- Jede Mail an Eltern hat Impressum-Link, Datenschutz-Link und den Widerruf „LÖSCHEN“.

**Qualität (alle Mails gleich)**
- Neue Vorlage: Logo, „Dein Dalino-Kids-Team“, Adresse „Kaulbachstr. 51–53“.
- Kein „This email was sent automatically with n8n“, kein „Hallo Kundin“, keine Platzhalter (`{{ }}`, `undefined`, `NaN`).

**Störungen**
- Unzustellbare Mails (mailer-daemon) → Störung, weil das Match sonst hängen bleibt.
- Profil ohne gültige E-Mail-Adresse.
- Kein „Danke für dein Profil“ innerhalb von 30 Minuten nach Anmeldung.
- JA/SCHREIBEN/NEIN nicht innerhalb von 30 Minuten bestätigt.
- `NEUIGKEITEN JA` von einer Adresse, die zu keinem Profil passt.
- Profile kommen rein, aber 24 Stunden geht keine Mail raus → n8n steht.
- Testprofile (test, rueb.eu, +mama, [TEST] …) im System → Störung, bis sie gelöscht sind.
- Altersangabe „0–1 Jahr“ (neues Formular) neben „unter 1 Jahr“ (alt) → Hinweis.

## Einrichten (einmalig, ca. 10 Minuten)

1. In n8n **Workflows → Import from File** → `ELTERN_MATCH_WAECHTER.json`.
2. In beiden Gmail-Knoten das Gmail-Konto **info@dalinowellness.de** auswählen (Platzhalter „BITTE_AUSWAEHLEN“).
3. Telegram: Die Knoten nutzen das vorhandene Credential **„Telegram Metropolis“** und die Chat-ID **5024797685** aus dem Master-Orchestrator. Falls Emma einen anderen Chat nutzt, die Chat-ID in den drei Telegram-Knoten ändern.
4. Gemini: nutzt das vorhandene Credential **„Google Gemini API“**.
5. Im **Eltern-Match-Workflow** unter *Settings → Error Workflow* „ELTERN_MATCH_WAECHTER“ auswählen. Gern auch bei allen anderen wichtigen Workflows.
6. Wächter **aktivieren**. Beim ersten Lauf meldet er alle Altlasten einmal, danach nur noch Neues.

## Testprofile löschen

Der Wächter erkennt Testprofile und meldet sie so lange, bis sie weg sind. Löschen muss man sie dort, wo der Eltern-Match-Workflow seine Profile speichert (der Workflow liegt nicht in diesem Repo). Bekannte Testprofile vom 15.–18.11.2026: **Eugen**, **Juri** (Adresse mit Tippfehler), **Test-Mama** (+mama-Adresse), **Ira** (Probelauf).

## Was im Eltern-Match-Workflow selbst noch repariert werden sollte

- Gmail-Knoten: *Options → Append n8n Attribution* **aus**.
- Werbeblock nur einfügen, wenn das Profil ein bestätigtes Opt-in hat.
- Alle Mails auf die neue Vorlage umstellen (Logo, Impressum/Datenschutz, „Dalino-Kids-Team“, Kaulbachstr. 51–53).
- Anrede ohne Namen: „Hallo,“ statt „Hallo Kundin“.
- Altersgruppen „0–1 Jahr“ und „unter 1 Jahr“ beim Matching gleich behandeln.
- `NEUIGKEITEN JA` über eine Profil-ID im Betreff zuordnen statt über die Absenderadresse (Gmail-Aliasse mit + kommen ohne Alias an).
- Fehlende Mail „Ihr habt beide JA gesagt“ (Vorstellung + Tischreservierung) und Knopf „Neues Kennenlernen“, wie auf der Website versprochen.

## Entwicklung

Die Prüflogik steht lesbar in `regelpruefung.js` und ist 1:1 im Code-Knoten eingebettet. Tests: `node eltern-match/test-regelpruefung.js`.

Jarvis: In den Repos gibt es (noch) keinen Jarvis-Workflow. Jarvis kann den Status-Webhook abfragen oder die Tabelle `eltern_match_waechter` lesen.
