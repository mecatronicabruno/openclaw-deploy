#!/bin/sh
# =============================================================================
# entrypoint.sh – Converte Docker Secrets em variáveis de ambiente
# Padrão seguro: credenciais nunca ficam em texto plano no stack file
# =============================================================================
set -e

load_secret() {
  local file="/run/secrets/$1"
  local varname="$2"
  if [ -f "$file" ]; then
    # trim whitespace/newline do secret
    val="$(tr -d '[:space:]' < "$file")"
    export "$varname=$val"
    echo "[entrypoint] Secret '$1' carregado."
  else
    echo "[entrypoint] Aviso: secret '$1' não encontrado (pode ser opcional)."
  fi
}

# ── Gateway ──────────────────────────────────────────────────────────────────
load_secret "openclaw_gateway_token"   "OPENCLAW_GATEWAY_TOKEN"

# ── Claude (API Key – não expira, crie em console.anthropic.com) ─────────────
load_secret "anthropic_api_key"        "ANTHROPIC_API_KEY"

# ── Provedores gratuitos ──────────────────────────────────────────────────────
# OpenRouter: gratuito para modelos :free — openrouter.ai
load_secret "openrouter_api_key"       "OPENROUTER_API_KEY"

# ── Provedores opcionais ──────────────────────────────────────────────────────
load_secret "openai_api_key"           "OPENAI_API_KEY"
load_secret "brave_api_key"            "BRAVE_API_KEY"

# ── Canais de mensagem ────────────────────────────────────────────────────────
load_secret "telegram_bot_token"       "TELEGRAM_BOT_TOKEN"
load_secret "discord_bot_token"        "DISCORD_BOT_TOKEN"
load_secret "slack_bot_token"          "SLACK_BOT_TOKEN"
load_secret "slack_app_token"          "SLACK_APP_TOKEN"

exec "$@"
