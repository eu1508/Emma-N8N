# Security Incident Response: Leaked API Keys / n8n Tokens

## Sofortmaßnahme

Wenn ein API-Key, n8n-JWT, Google-Key, Airtable-Token, Anthropic-Key, OpenRouter-Key oder OpenAI-Key in Chat, Git, Screenshots oder Logs gepostet wurde, gilt er als kompromittiert.

**Nicht weiterverwenden. Sofort rotieren.**

## Reihenfolge

1. **Alle geposteten Keys in den jeweiligen Anbieter-Dashboards widerrufen/löschen.**
   - n8n: API-Key/JWT/MCP-Token neu erzeugen.
   - OpenAI: Project Keys und Service Account Keys löschen und neu erstellen.
   - Anthropic: API Keys löschen und neu erstellen.
   - Google: API Key löschen oder stark einschränken und neu erstellen.
   - Airtable: PAT löschen und neu erstellen.
   - OpenRouter: API Key löschen und neu erstellen.
2. **Neue Keys nur in n8n Credentials oder in eine lokale `.env.n8n` eintragen.**
3. **Keine echten Keys in Chat, JSON-Workflow-Dateien, Docs oder Git committen.**
4. **Vor Deployment prüfen:**

```bash
python3 tools/scan_secrets.py
python3 tools/validate_n8n_workflows.py
```

5. **Danach erst deployen:**

```bash
python3 tools/deploy_n8n_bundle.py --apply
```

## Warum ich gepostete Secrets nicht direkt verwenden darf

Live-Secrets in einem Chat gelten als offengelegt. Würde ich sie in Dateien schreiben oder für API-Aufrufe benutzen, könnten sie in Logs, Prozesshistorie oder Git landen. Deshalb wird nur mit lokal gepflegter `.env.n8n` oder n8n Credentials gearbeitet.

## Sichere Ablage

- `.env.n8n` ist in `.gitignore` ausgeschlossen.
- `.env.n8n.example` enthält nur Platzhalter.
- Workflow-JSONs sollen Credential-Namen referenzieren, aber niemals Roh-Tokens enthalten.
