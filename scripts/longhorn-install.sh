#!/bin/bash

# ==============================================================================
# INSTALAÇÃO INTERATIVA: SUSE Storage (Longhorn)
# ==============================================================================
# Pré-requisitos: cluster K3s ativo (rancher-install.sh já executado),
# kubectl e helm disponíveis, subscrição ativa no SUSE Application Collection.
# Credenciais AC obtidas em: https://apps.rancher.io → User Profile → Tokens
# ==============================================================================

set -eo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

LINUX_IP=$(hostname -I | awk '{print $1}')
MACHINE_HOSTNAME=$(hostname)
LOG_FILE="/var/log/longhorn-install-$(date +%Y%m%d-%H%M%S).log"
AC_REGISTRY="dp.apps.rancher.io"
CHART_OCI="oci://$AC_REGISTRY/charts/longhorn"

exec > >(tee -a "$LOG_FILE") 2>&1

# ── Funções de logging ────────────────────────────────────────────────────────
log()    { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✔  $*${NC}"; }
info()   { echo -e "${BLUE}[$(date +'%H:%M:%S')] →  $*${NC}"; }
warn()   { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠  $*${NC}"; }
error()  { echo -e "${RED}[$(date +'%H:%M:%S')] ✖  $*${NC}"; exit 1; }

section() {
  echo ""
  echo -e "${BOLD}${CYAN}┌──────────────────────────────────────────────────────────────┐${NC}"
  printf "${BOLD}${CYAN}│  %-8s %-52s│${NC}\n" "[$1]" "$2"
  echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

prompt() {
  local __var=$1 __label=$2 __default=$3
  echo -en "${BOLD}  $__label${NC}"
  [ -n "$__default" ] && echo -en " ${DIM}[$__default]${NC}"
  echo -n ": "
  read -r __input
  eval "$__var='${__input:-$__default}'"
}

prompt_secret() {
  local __var=$1 __label=$2
  echo -en "${BOLD}  $__label${NC}: "
  read -rs __input
  echo ""
  eval "$__var='$__input'"
}

confirm() {
  echo -en "${BOLD}$1 (s/N): ${NC}"
  read -r __ans
  [[ "$__ans" =~ ^[sS]$ ]]
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║   INSTALAÇÃO INTERATIVA: SUSE Storage (Longhorn)                ║
║   via SUSE Application Collection                               ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "  ${DIM}Máquina :${NC} ${BOLD}$MACHINE_HOSTNAME${NC} ${DIM}($LINUX_IP)${NC}"
echo -e "  ${DIM}Log     :${NC} ${BOLD}$LOG_FILE${NC}"
echo ""

# ── Verificação de root ───────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && error "Este script deve ser executado como root (sudo)."

# ══════════════════════════════════════════════════════════════════════════════
# PRÉ-REQUISITOS
# ══════════════════════════════════════════════════════════════════════════════
section "PRÉ" "VERIFICAÇÃO DE PRÉ-REQUISITOS"

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

command -v kubectl &>/dev/null || error "kubectl não encontrado. Execute rancher-install.sh primeiro."
command -v helm    &>/dev/null || error "helm não encontrado. Execute rancher-install.sh primeiro."

info "Verificando conectividade com o cluster..."
kubectl cluster-info &>/dev/null || error "Não foi possível conectar ao cluster. Verifique o KUBECONFIG."

# O Longhorn requer open-iscsi no host para volumes iSCSI
if ! command -v iscsiadm &>/dev/null; then
  warn "open-iscsi não encontrado — o Longhorn requer este pacote no host."
  if confirm "  Instalar open-iscsi agora via zypper?"; then
    zypper install -y open-iscsi
    systemctl enable --now iscsid
    log "open-iscsi instalado e ativado."
  else
    warn "Continuando sem open-iscsi. Volumes iSCSI podem não funcionar."
  fi
else
  log "open-iscsi : OK"
fi

log "kubectl : OK"
log "helm    : $(helm version --short)"
log "cluster : $(kubectl get nodes --no-headers 2>/dev/null | wc -l) nó(s) disponíveis"
echo ""
kubectl get nodes
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# COLETA DE VARIÁVEIS
# ══════════════════════════════════════════════════════════════════════════════
section "CONFIG" "CONFIGURAÇÃO DA INSTALAÇÃO"

echo -e "${BOLD}── Application Collection (SUSE) ──────────────────────────────────${NC}"
echo -e "  ${DIM}Acesse https://apps.rancher.io → User Profile → Tokens${NC}"
echo ""
prompt        AC_USER  "Usuário"  "flgussi@suse.com"
prompt_secret AC_PASS  "Senha"
echo ""

echo -e "${BOLD}── SUSE Storage (Longhorn) ────────────────────────────────────────${NC}"
prompt LH_VERSION    "Versão do chart"        "1.8.1"
prompt LH_NAMESPACE  "Namespace"              "longhorn-system"
prompt LH_RELEASE    "Nome do release Helm"   "longhorn"
echo ""

echo -e "${BOLD}── Configuração de Storage ────────────────────────────────────────${NC}"
echo -e "  ${DIM}Réplicas: use 1 para PoC single-node; produção recomenda 3${NC}"
echo -e "  ${YELLOW}  ⚠  Com 1 réplica, dados não são replicados — não use em produção.${NC}"
echo ""
prompt LH_REPLICAS   "Réplicas padrão"             "1"
prompt LH_DATA_PATH  "Caminho de dados no host"    "/var/lib/longhorn"
echo ""

LH_DEFAULT_SC=false
if confirm "  Definir Longhorn como StorageClass padrão do cluster?"; then
  LH_DEFAULT_SC=true
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# RESUMO E CONFIRMAÇÃO FINAL
# ══════════════════════════════════════════════════════════════════════════════
section "RESUMO" "O QUE SERÁ INSTALADO"

echo -e "  ${DIM}Application Collection  :${NC} ${BOLD}$AC_USER @ $AC_REGISTRY${NC}"
echo -e "  ${DIM}Chart OCI               :${NC} ${BOLD}$CHART_OCI${NC}"
echo -e "  ${DIM}Versão                  :${NC} ${BOLD}$LH_VERSION${NC}"
echo -e "  ${DIM}Namespace               :${NC} ${BOLD}$LH_NAMESPACE${NC}"
echo -e "  ${DIM}Release Helm            :${NC} ${BOLD}$LH_RELEASE${NC}"
echo -e "  ${DIM}Réplicas padrão         :${NC} ${BOLD}$LH_REPLICAS${NC}"
echo -e "  ${DIM}Caminho de dados        :${NC} ${BOLD}$LH_DATA_PATH${NC}"
echo -e "  ${DIM}StorageClass padrão     :${NC} ${BOLD}$([ "$LH_DEFAULT_SC" = true ] && echo "sim (longhorn)" || echo "não")${NC}"
echo -e "  ${DIM}Log                     :${NC} ${BOLD}$LOG_FILE${NC}"
echo ""
confirm "  Confirmar e iniciar a instalação?" || { info "Instalação cancelada."; exit 0; }
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 1/4 — NAMESPACE
# ══════════════════════════════════════════════════════════════════════════════
section "1/4" "CRIAÇÃO DO NAMESPACE"

kubectl create namespace "$LH_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
log "Namespace '$LH_NAMESPACE' pronto."

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 2/4 — SECRET DE IMAGEM
# ══════════════════════════════════════════════════════════════════════════════
section "2/4" "SECRET DE IMAGEM (Application Collection)"

info "Criando secret 'application-collection' no namespace '$LH_NAMESPACE'..."
kubectl create secret docker-registry application-collection \
  --docker-server="$AC_REGISTRY" \
  --docker-username="$AC_USER" \
  --docker-password="$AC_PASS" \
  --namespace="$LH_NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Secret 'application-collection' criado em '$LH_NAMESPACE' ✓"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 3/4 — HELM REGISTRY LOGIN
# ══════════════════════════════════════════════════════════════════════════════
section "3/4" "LOGIN NO REGISTRO OCI ($AC_REGISTRY)"

info "Autenticando Helm no Application Collection Registry..."
echo "$AC_PASS" | helm registry login "$AC_REGISTRY" -u "$AC_USER" --password-stdin
log "Login realizado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 4/4 — INSTALAÇÃO VIA HELM
# ══════════════════════════════════════════════════════════════════════════════
section "4/4" "INSTALAÇÃO DO SUSE STORAGE (LONGHORN)"

LH_VERSION_HELM="${LH_VERSION#v}"

info "Chart   : $CHART_OCI"
info "Versão  : $LH_VERSION_HELM"
info "Release : $LH_RELEASE"
info "Iniciando instalação (pode levar vários minutos)..."
echo ""

HELM_OPTS=(
  --namespace "$LH_NAMESPACE"
  --version "$LH_VERSION_HELM"
  --set "global.imagePullSecrets[0].name=application-collection"
  --set defaultSettings.defaultReplicaCount="$LH_REPLICAS"
  --set defaultSettings.defaultDataPath="$LH_DATA_PATH"
  --set persistence.defaultClass="$LH_DEFAULT_SC"
  --set persistence.defaultClassReplicaCount="$LH_REPLICAS"
  --wait
  --timeout 15m
)

helm upgrade --install "$LH_RELEASE" "$CHART_OCI" "${HELM_OPTS[@]}"

log "SUSE Storage (Longhorn) $LH_VERSION instalado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# CONCLUSÃO
# ══════════════════════════════════════════════════════════════════════════════
echo ""
info "Verificando pods do Longhorn..."
kubectl get pods -n "$LH_NAMESPACE"
echo ""
info "StorageClasses disponíveis no cluster:"
kubectl get storageclass
echo ""

echo -e "${BOLD}${GREEN}"
cat << 'DONE'
╔══════════════════════════════════════════════════════════════════╗
║         SUSE STORAGE (LONGHORN) INSTALADO COM SUCESSO!          ║
╚══════════════════════════════════════════════════════════════════╝
DONE
echo -e "${NC}"

echo -e "  ${BOLD}StorageClass criada   :${NC} ${CYAN}longhorn${NC} $([ "$LH_DEFAULT_SC" = true ] && echo "${DIM}(padrão do cluster)${NC}")"
echo ""
echo -e "  ${BOLD}Interface web${NC} ${DIM}(via port-forward):${NC}"
echo -e "    ${DIM}kubectl port-forward service/longhorn-frontend 8080:80 -n $LH_NAMESPACE${NC}"
echo -e "    Acesse: ${CYAN}http://localhost:8080${NC}"
echo ""
echo -e "  ${BOLD}Verificar volumes e storage:${NC}"
echo -e "    ${DIM}kubectl get storageclass${NC}"
echo -e "    ${DIM}kubectl get pv,pvc -A${NC}"
echo -e "    ${DIM}kubectl get nodes.longhorn.io -n $LH_NAMESPACE${NC}"
echo ""
echo -e "  ${BOLD}Log completo:${NC} ${CYAN}$LOG_FILE${NC}"
echo ""
