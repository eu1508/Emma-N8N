# FreeLLM für Emma-N8N

Kostenlose KI-Modelle (Gemini, Llama, Mistral, …) über **eine** OpenAI-kompatible
Adresse – für n8n, Skripte und KI-Tools. Hier sind alle drei FreeLLM-Projekte eingebunden:

| | Projekt | Was es macht | Adresse |
|---|---|---|---|
| 1 | [FreeLLM](https://github.com/CezaryChodun/FreeLLM) (`freellm-proxy/`) | LiteLLM-Proxy, verteilt Anfragen auf Gemini- und Groq-Gratiskontingente | `http://localhost:3000/v1` |
| 2 | [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi) (`freellmapi/`) | 30+ Gratis-Anbieter, Dashboard, automatischer Anbieterwechsel | `http://localhost:3001/v1` |
| 3 | [freellm.net](https://freellm.net/) (`ANBIETER-KEYS.md`) | Verzeichnis: wo es die kostenlosen API-Keys gibt | – |

**Empfehlung:** Für den Anfang reicht **Projekt 2 (FreeLLMAPI)** – es kann am meisten
und hat eine Weboberfläche. Projekt 1 ist schlanker, kann aber nur Gemini + Groq.

---

## 1. Kostenlose API-Keys besorgen

Mindestens einen, besser zwei bis drei – siehe [ANBIETER-KEYS.md](ANBIETER-KEYS.md).
Am einfachsten: **Google AI Studio** (Gemini) und **Groq**, beide ohne Kreditkarte.

Keys **nie** ins Repo schreiben. Die `.env`-Dateien sind per `.gitignore` ausgeschlossen.

## 2. Auf eigenem Rechner / Server starten (mit Docker)

```bash
cd freellm
export GEMINI_API_KEY=...   # deine Keys
export GROQ_API_KEY=...
./scripts/install.sh        # startet Projekt 1 + 2
# oder nur eins davon:
./scripts/install.sh api    # nur FreeLLMAPI
./scripts/install.sh proxy  # nur FreeLLM-Proxy
./scripts/install.sh status
./scripts/install.sh stop
```

Das Skript legt die `.env`-Dateien an, erzeugt alle Passwörter/Schlüssel automatisch
und trägt deine Keys ein.

- **FreeLLMAPI:** http://localhost:3001 öffnen → Konto anlegen → unter **Keys** weitere
  Anbieter eintragen → oben den **Unified API Key** (`freellmapi-…`) kopieren.
- **FreeLLM-Proxy:** API-Key ist der `LITELLM_MASTER_KEY` aus `freellm-proxy/.env`.

Standardmäßig ist alles nur lokal erreichbar. Läuft n8n auf einem anderen Rechner,
in der jeweiligen `.env` `HOST_BIND=0.0.0.0` setzen (nur im vertrauenswürdigen Netz).

## 3. Ohne Docker (z. B. in jedem Claude-Code-Cloud-Chat)

```bash
./scripts/install.sh native     # = scripts/cloud-setup.sh
```

Baut FreeLLMAPI direkt mit Node.js (20+), startet es auf `http://127.0.0.1:3001/v1`
und legt den API-Key in `~/.freellm/unified-key` ab.

**Damit es in jedem neuen Claude-Code-Chat automatisch da ist:**

1. In Claude Code (Web/App) das Umgebungsmenü in der Titelleiste öffnen → **Edit**.
2. Unter **Setup script** den kompletten Inhalt von
   [`scripts/cloud-setup.sh`](scripts/cloud-setup.sh) einfügen.
3. Deine Keys als Umgebungsvariablen/Secrets hinterlegen
   (`GEMINI_API_KEY`, `GROQ_API_KEY`, … – Namen siehe [ANBIETER-KEYS.md](ANBIETER-KEYS.md)).
4. Neuen Chat starten – FreeLLMAPI wird beim Start installiert und gestartet.

> Hinweis: Diese Cloud-Umgebung kann keine Docker-Images von ghcr.io/Docker Hub laden,
> deshalb dort die Variante ohne Docker. Claude selbst läuft dadurch **nicht** auf den
> Gratis-Modellen – FreeLLM steht in den Chats als Werkzeug zur Verfügung (z. B. um
> Workflows/Skripte damit zu testen).

## 4. In n8n verwenden

In n8n eine **OpenAI-Credential** anlegen:

| Feld | FreeLLMAPI | FreeLLM-Proxy |
|---|---|---|
| API Key | Unified API Key (`freellmapi-…`) | `LITELLM_MASTER_KEY` |
| Base URL | `http://<host>:3001/v1` | `http://<host>:3000/v1` |
| Modell | `auto` (Router wählt) | z. B. `flash` oder `large` (Modellgruppen) |

Läuft n8n selbst in Docker auf demselben Rechner, als Host `host.docker.internal` verwenden.

Test per Kommandozeile:

```bash
curl http://localhost:3001/v1/chat/completions \
  -H "Authorization: Bearer $(cat ~/.freellm/unified-key)" \
  -H "Content-Type: application/json" \
  -d '{"model":"auto","messages":[{"role":"user","content":"Hallo!"}]}'
```

## Lizenzen

- `freellm-proxy/` basiert auf dem Docker-Compose-Beispiel von
  [CezaryChodun/FreeLLM](https://github.com/CezaryChodun/FreeLLM) (GPL-3.0).
- FreeLLMAPI wird zur Laufzeit von
  [tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi) geladen (MIT).
- FreeLLMAPI ist laut Hersteller für den persönlichen Gebrauch gedacht.
