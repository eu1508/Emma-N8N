# Kostenlose LLM-Anbieter & API-Keys (Projekt 3)

Auszug aus dem Verzeichnis [freellm.net](https://freellm.net/) /
[awesome-freellm-apis](https://github.com/open-free-llm-api/awesome-freellm-apis)
(Stand Oktober 2026 – Limits ändern sich häufig, aktuelle Werte immer dort prüfen).

> **Wichtig:** Nur Keys von **kostenlosen** Konten verwenden. Ein Key an einem
> bezahlten Konto kann Kosten verursachen.

## Empfohlen für den Start

| Anbieter | Variable | Key holen | Genutzt von |
|---|---|---|---|
| Google Gemini (AI Studio) | `GEMINI_API_KEY` | https://aistudio.google.com/app/apikey | Proxy + FreeLLMAPI |
| Groq | `GROQ_API_KEY` | https://console.groq.com/keys | Proxy + FreeLLMAPI |
| OpenRouter | `OPENROUTER_API_KEY` | https://openrouter.ai/workspaces/default/keys | FreeLLMAPI |
| Mistral AI | `MISTRAL_API_KEY` | https://console.mistral.ai/api-keys | FreeLLMAPI |
| Cerebras | `CEREBRAS_API_KEY` | https://cloud.cerebras.ai/ | FreeLLMAPI |
| NVIDIA NIM | `NVIDIA_API_KEY` | https://build.nvidia.com/settings/api-keys | FreeLLMAPI |
| Cohere | `COHERE_API_KEY` | https://dashboard.cohere.com/api-keys | FreeLLMAPI |
| Hugging Face | `HF_TOKEN` | https://huggingface.co/settings/tokens | FreeLLMAPI |

Weitere Anbieter (Cloudflare, Ollama Cloud, LLM7, Kilo Code, …) lassen sich im
FreeLLMAPI-Dashboard unter **Keys** eintragen.

## Direkt nutzen (ohne Proxy)

Alle diese Anbieter sind OpenAI-kompatibel und funktionieren auch direkt, z. B. in n8n:

| Anbieter | Basis-URL |
|---|---|
| Groq | `https://api.groq.com/openai/v1` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` |
| OpenRouter | `https://openrouter.ai/api/v1` |
| Mistral AI | `https://api.mistral.ai/v1` |
| NVIDIA NIM | `https://integrate.api.nvidia.com/v1` |
| Cerebras | `https://api.cerebras.ai/v1` |

Der Vorteil von Projekt 1/2: **ein** Endpunkt für alle, mit automatischem
Wechsel zum nächsten Anbieter, wenn ein Gratis-Limit erreicht ist.
