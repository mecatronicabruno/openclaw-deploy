#!/usr/bin/env bash
# =============================================================================
# add-collaborator.sh – Provisiona uma instância OpenClaw para um colaborador
# Uso: ./add-collaborator.sh <nome> [subdomínio]
# Ex:  ./add-collaborator.sh alice alice.openclaw.seudominio.com
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/collaborator.template.yml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Validação dos argumentos ──────────────────────────────────────────────────
[[ $# -lt 1 ]] && error "Uso: $0 <nome> [subdomínio]\nEx: $0 alice alice.openclaw.seudominio.com"

NAME="${1,,}"  # lowercase
[[ "$NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$|^[a-z]$ ]] \
  || error "Nome inválido '$NAME'. Use apenas letras minúsculas, números e hifens."

SUBDOMAIN="${2:-${NAME}.openclaw.seudominio.com}"
STACK_NAME="openclaw-${NAME}"
SECRET_NAME="${NAME}_gateway_token"
STACK_FILE="${SCRIPT_DIR}/stack-${NAME}.yml"

# ── Verificações de Swarm ─────────────────────────────────────────────────────
docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active" \
  || error "Este nó não faz parte de um Docker Swarm ativo."
[[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" == "true" ]] \
  || error "Execute no nó manager do Swarm."

# ── Verificar se stack já existe ──────────────────────────────────────────────
if docker stack ls --format '{{.Name}}' | grep -q "^${STACK_NAME}$"; then
  warn "Stack '${STACK_NAME}' já existe."
  read -rp "Recriar/atualizar? (s/N): " confirm
  [[ "${confirm,,}" == "s" ]] || { info "Operação cancelada."; exit 0; }
fi

# ── Verificar secrets compartilhados ─────────────────────────────────────────
for shared in shared_anthropic_api_key shared_openrouter_api_key; do
  docker secret ls --format '{{.Name}}' | grep -q "^${shared}$" \
    || error "Secret compartilhado '$shared' não encontrado. Execute deploy.sh primeiro."
done

# ── Criar gateway token do colaborador ───────────────────────────────────────
if docker secret ls --format '{{.Name}}' | grep -q "^${SECRET_NAME}$"; then
  info "Secret '${SECRET_NAME}' já existe. Reutilizando."
  TOKEN="(existente – recupere via: docker secret inspect ${SECRET_NAME})"
else
  TOKEN="$(openssl rand -hex 32)"
  echo -n "$TOKEN" | docker secret create "$SECRET_NAME" -
  info "Secret '${SECRET_NAME}' criado."
fi

# ── Gerar stack file a partir do template ─────────────────────────────────────
info "Gerando stack file: ${STACK_FILE}"
sed \
  -e "s|{{NAME}}|${NAME}|g" \
  -e "s|{{SUBDOMAIN}}|${SUBDOMAIN}|g" \
  "$TEMPLATE" > "$STACK_FILE"

# ── Deploy do stack ───────────────────────────────────────────────────────────
info "Fazendo deploy do stack '${STACK_NAME}'..."
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-openclaw-swarm:local}" \
docker stack deploy \
  --compose-file "$STACK_FILE" \
  --with-registry-auth \
  "$STACK_NAME"

# ── Resultado ─────────────────────────────────────────────────────────────────
echo
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} Colaborador provisionado: ${NAME}${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo -e "  Stack       : ${STACK_NAME}"
echo -e "  URL         : https://${SUBDOMAIN}"
if [[ "$TOKEN" != "(existente"* ]]; then
  echo -e "  Gateway token: ${TOKEN}"
  echo -e "  ${YELLOW}Guarde este token! Não será exibido novamente.${NC}"
fi
echo -e "  Logs        : docker service logs -f ${STACK_NAME}_gateway"
echo -e "  Status      : docker stack services ${STACK_NAME}"
echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"
echo
info "Aguarde ~40s para o healthcheck passar."
