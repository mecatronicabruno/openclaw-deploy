#!/usr/bin/env bash
# =============================================================================
# remove-collaborator.sh – Remove instância de um colaborador
# Uso: ./remove-collaborator.sh <nome> [--purge]
# --purge também remove volumes (dados permanentes) e secrets
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $# -lt 1 ]] && error "Uso: $0 <nome> [--purge]"

NAME="${1,,}"
PURGE="${2:-}"
STACK_NAME="openclaw-${NAME}"
STACK_FILE="${SCRIPT_DIR}/stack-${NAME}.yml"

[[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" == "true" ]] \
  || error "Execute no nó manager do Swarm."

docker stack ls --format '{{.Name}}' | grep -q "^${STACK_NAME}$" \
  || error "Stack '${STACK_NAME}' não encontrado."

warn "Isso vai remover a instância de '${NAME}'."
[[ "$PURGE" == "--purge" ]] && warn "Com --purge: volumes e secrets também serão removidos (IRREVERSÍVEL)."
read -rp "Confirmar? (s/N): " confirm
[[ "${confirm,,}" == "s" ]] || { info "Operação cancelada."; exit 0; }

# Remove o stack
docker stack rm "$STACK_NAME"
info "Stack '${STACK_NAME}' removido."

# Aguarda remoção dos containers
info "Aguardando remoção dos containers..."
sleep 5

if [[ "$PURGE" == "--purge" ]]; then
  # Remove volumes (dados do colaborador)
  for vol in config workspace; do
    full="${STACK_NAME}_${vol}"
    if docker volume ls --format '{{.Name}}' | grep -q "^${full}$"; then
      docker volume rm "$full"
      info "Volume '${full}' removido."
    fi
  done

  # Remove secret do gateway token
  secret="${NAME}_gateway_token"
  if docker secret ls --format '{{.Name}}' | grep -q "^${secret}$"; then
    docker secret rm "$secret"
    info "Secret '${secret}' removido."
  fi
fi

# Remove stack file gerado
[[ -f "$STACK_FILE" ]] && rm "$STACK_FILE" && info "Stack file removido."

info "Colaborador '${NAME}' removido com sucesso."
