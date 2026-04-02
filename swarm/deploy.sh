#!/usr/bin/env bash
# =============================================================================
# deploy.sh – Deploy do OpenClaw no Docker Swarm
# Execute na máquina manager do seu Swarm
# =============================================================================
set -euo pipefail

STACK_NAME="openclaw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Cores para output ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Verificações básicas ──────────────────────────────────────────────────────
docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active" \
  || error "Este nó não faz parte de um Docker Swarm ativo."

[[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" == "true" ]] \
  || error "Execute este script no nó manager do Swarm."

# ── Rede pública (Traefik) ────────────────────────────────────────────────────
if ! docker network ls --format '{{.Name}}' | grep -q "^traefik_public$"; then
  warn "Rede 'traefik_public' não encontrada. Criando..."
  docker network create --driver overlay --attachable traefik_public
  info "Rede 'traefik_public' criada."
fi

# ── Criar Docker Secrets ──────────────────────────────────────────────────────
create_secret() {
  local name="$1"
  local prompt="$2"
  local optional="${3:-false}"

  if docker secret ls --format '{{.Name}}' | grep -q "^${name}$"; then
    info "Secret '$name' já existe. Pulando."
    return
  fi

  if [[ "$optional" == "true" ]]; then
    read -rsp "$(echo -e "${YELLOW}[OPT]${NC} $prompt (Enter para pular): ")" value
    echo
    [[ -z "$value" ]] && { warn "Secret opcional '$name' ignorado."; return; }
  else
    while true; do
      read -rsp "$(echo -e "${GREEN}[REQ]${NC} $prompt: ")" value
      echo
      [[ -n "$value" ]] && break
      warn "Valor obrigatório. Tente novamente."
    done
  fi

  echo -n "$value" | docker secret create "$name" -
  info "Secret '$name' criado."
}

echo
info "=== Configurando Docker Secrets ==="
create_secret "openclaw_gateway_token" \
  "Token do gateway OpenClaw (ex: gere com: openssl rand -hex 32)"
info "Claude: API Key (não expira – crie em console.anthropic.com/settings/api-keys)"
info "Dica: defina um spending limit em console.anthropic.com/settings/limits"
create_secret "anthropic_api_key" \
  "Anthropic API Key (sk-ant-...)"
create_secret "openrouter_api_key" \
  "OpenRouter API Key – crie grátis em openrouter.ai (Tier 3 gratuito)"
create_secret "openai_api_key" \
  "OpenAI API Key (opcional, começa com sk-...)" true
create_secret "telegram_bot_token" \
  "Telegram Bot Token (opcional)" true
create_secret "discord_bot_token" \
  "Discord Bot Token (opcional)" true
create_secret "slack_bot_token" \
  "Slack Bot Token (opcional)" true
create_secret "slack_app_token" \
  "Slack App Token (opcional, começa com xapp-...)" true

# ── Build da imagem com entrypoint de secrets ─────────────────────────────────
echo
info "=== Build da imagem ==="

IMAGE_TAG="openclaw-swarm:local"

# Se quiser usar a imagem oficial sem build, comente o bloco abaixo
# e altere a imagem no stack file para ghcr.io/openclaw/openclaw:latest
# ajustando o entrypoint via um initContainer ou similar.

docker build \
  --file "${SCRIPT_DIR}/Dockerfile.swarm" \
  --tag "${IMAGE_TAG}" \
  "${SCRIPT_DIR}"

info "Imagem '${IMAGE_TAG}' construída."

# Atualiza o stack file para usar a imagem local
export OPENCLAW_IMAGE="${IMAGE_TAG}"

# ── Deploy do stack ───────────────────────────────────────────────────────────
echo
info "=== Deploy do stack '${STACK_NAME}' ==="

docker stack deploy \
  --compose-file "${SCRIPT_DIR}/openclaw-stack.yml" \
  --with-registry-auth \
  "${STACK_NAME}"

echo
info "=== Status dos serviços ==="
sleep 3
docker stack services "${STACK_NAME}"

echo
info "Deploy concluído!"
info "Aguarde ~40s e verifique a saúde: docker service ls"
info "Logs: docker service logs -f ${STACK_NAME}_gateway"
