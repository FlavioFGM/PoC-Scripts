#!/bin/bash

# ==============================================================================
# INSTALAÇÃO INTERATIVA: SUSE Private Registry
# ==============================================================================
# Pré-requisitos: cluster K3s ativo (rancher-install.sh já executado),
# kubectl e helm disponíveis, subscrição ativa do SUSE Private Registry.
# Credenciais SCC obtidas em: https://scc.suse.com → Proxies
# ==============================================================================

set -eo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

LINUX_IP=$(hostname -I | awk '{print $1}')
MACHINE_HOSTNAME=$(hostname)
LOG_FILE="/var/log/private-registry-install-$(date +%Y%m%d-%H%M%S).log"
SCC_REGISTRY="registry.suse.com"
CHART_OCI="oci://registry.suse.com/private-registry/private-registry-helm"

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
║       INSTALAÇÃO INTERATIVA: SUSE Private Registry              ║
║       via SUSE Customer Center                                  ║
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

echo -e "${BOLD}── SUSE Customer Center (SCC) ─────────────────────────────────────${NC}"
echo -e "  ${DIM}Acesse https://scc.suse.com → selecione a organização → Proxies${NC}"
echo -e "  ${DIM}As credenciais de espelhamento estão no canto superior direito${NC}"
echo ""
prompt        SCC_USER  "Usuário SCC (Mirroring)"    ""
prompt_secret SCC_PASS  "Senha SCC  (Mirroring)"
echo ""

echo -e "${BOLD}── Configuração do Helm / Kubernetes ──────────────────────────────${NC}"
prompt RELEASE_NAME  "Nome do release Helm"           "suse-registry"
prompt PR_NAMESPACE  "Namespace"                       "private-registry"
echo ""

echo -e "${BOLD}── Configuração do Registry ────────────────────────────────────────${NC}"
echo -e "  ${DIM}Configure o DNS para apontar este hostname ao IP do Ingress do cluster${NC}"
prompt PR_HOSTNAME  "Hostname do Registry (ex: registry.empresa.com)"  "registry.$MACHINE_HOSTNAME"
echo ""

echo -e "${BOLD}── Storage Class (Persistent Volumes) ─────────────────────────────${NC}"
echo -e "  ${DIM}O SUSE Private Registry requer Persistent Volumes. Deixe em branco para usar o padrão do cluster.${NC}"
CURRENT_SC=$(kubectl get storageclass 2>/dev/null | grep '(default)' | awk '{print $1}' || true)
[ -n "$CURRENT_SC" ] && echo -e "  ${DIM}Storage Class padrão detectada: ${BOLD}$CURRENT_SC${NC}"
prompt PR_STORAGE_CLASS  "Storage Class (vazio = padrão do cluster)"  ""
echo ""

echo -e "${BOLD}── TLS ─────────────────────────────────────────────────────────────${NC}"
PR_TLS=false
TLS_CERT_PATH=""
TLS_KEY_PATH=""
if confirm "  Configurar TLS com certificado próprio?"; then
  PR_TLS=true
  prompt TLS_CERT_PATH "  Caminho do certificado (.pem ou .crt)" ""
  prompt TLS_KEY_PATH  "  Caminho da chave privada (.pem ou .key)" ""
  [ ! -f "$TLS_CERT_PATH" ] && error "Arquivo de certificado não encontrado: $TLS_CERT_PATH"
  [ ! -f "$TLS_KEY_PATH"  ] && error "Arquivo de chave privada não encontrado: $TLS_KEY_PATH"
  log "Certificados verificados."
else
  warn "TLS não configurado. O registry usará certificado auto-assinado (adequado para PoC)."
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# RESUMO E CONFIRMAÇÃO FINAL
# ══════════════════════════════════════════════════════════════════════════════
section "RESUMO" "O QUE SERÁ INSTALADO"

echo -e "  ${DIM}Máquina          :${NC} ${BOLD}$MACHINE_HOSTNAME ($LINUX_IP)${NC}"
echo -e "  ${DIM}Registry SCC     :${NC} ${BOLD}$SCC_REGISTRY${NC} ${DIM}(usuário: $SCC_USER)${NC}"
echo -e "  ${DIM}Helm release     :${NC} ${BOLD}$RELEASE_NAME${NC}"
echo -e "  ${DIM}Namespace        :${NC} ${BOLD}$PR_NAMESPACE${NC}"
echo -e "  ${DIM}Hostname         :${NC} ${BOLD}$PR_HOSTNAME${NC}"
echo -e "  ${DIM}Storage Class    :${NC} ${BOLD}${PR_STORAGE_CLASS:-<padrão do cluster>}${NC}"
echo -e "  ${DIM}TLS              :${NC} ${BOLD}$([ "$PR_TLS" = true ] && echo "certificado próprio" || echo "auto-assinado pelo registry")${NC}"
echo -e "  ${DIM}Chart OCI        :${NC} ${BOLD}$CHART_OCI${NC}"
echo -e "  ${DIM}Log              :${NC} ${BOLD}$LOG_FILE${NC}"
echo ""
confirm "  Confirmar e iniciar a instalação?" || { info "Instalação cancelada."; exit 0; }
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 1/4 — NAMESPACE
# ══════════════════════════════════════════════════════════════════════════════
section "1/4" "CRIAÇÃO DO NAMESPACE"

kubectl create namespace "$PR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
log "Namespace '$PR_NAMESPACE' pronto."

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 2/4 — AUTENTICAÇÃO E SECRETS SCC
# ══════════════════════════════════════════════════════════════════════════════
section "2/4" "AUTENTICAÇÃO E SECRETS DO SCC"

info "Autenticando Helm no SUSE Registry ($SCC_REGISTRY)..."
echo "$SCC_PASS" | helm registry login "$SCC_REGISTRY" \
  --username "$SCC_USER" --password-stdin
log "Helm: login em $SCC_REGISTRY realizado com sucesso!"

info "Criando secret de espelhamento SCC no namespace '$PR_NAMESPACE'..."
kubectl create secret docker-registry suse-registry \
  --namespace "$PR_NAMESPACE" \
  --docker-server="$SCC_REGISTRY" \
  --docker-username="$SCC_USER" \
  --docker-password="$SCC_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -
log "Secret 'suse-registry' criado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 3/4 — SECRET TLS (OPCIONAL)
# ══════════════════════════════════════════════════════════════════════════════
section "3/4" "CONFIGURAÇÃO DE TLS"

if [ "$PR_TLS" = true ]; then
  info "Criando secret TLS a partir dos arquivos fornecidos..."
  kubectl create secret tls suse-registry-tls \
    --namespace "$PR_NAMESPACE" \
    --cert="$TLS_CERT_PATH" \
    --key="$TLS_KEY_PATH" \
    --dry-run=client -o yaml | kubectl apply -f -
  log "Secret TLS 'suse-registry-tls' criado com sucesso!"
else
  info "TLS ignorado. O registry gerará um certificado auto-assinado automaticamente."
fi

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 4/4 — INSTALAÇÃO VIA HELM
# ══════════════════════════════════════════════════════════════════════════════
section "4/4" "INSTALAÇÃO DO SUSE PRIVATE REGISTRY"

info "Chart  : $CHART_OCI"
info "Release: $RELEASE_NAME"
info "Namespace: $PR_NAMESPACE"
info "Iniciando instalação (pode levar vários minutos)..."
echo ""

HELM_OPTS=(
  --namespace "$PR_NAMESPACE"
  --set harbor.externalURL="https://$PR_HOSTNAME"
  --set harbor.expose.ingress.hosts.core="$PR_HOSTNAME"
  --set "global.imagePullSecrets[0].name=suse-registry"
  --wait
  --timeout 15m
)

[ -n "$PR_STORAGE_CLASS" ] && \
  HELM_OPTS+=(--set harbor.persistence.persistentVolumeClaim.registry.storageClass="$PR_STORAGE_CLASS")

if [ "$PR_TLS" = true ]; then
  HELM_OPTS+=(
    --set harbor.expose.tls.certSource=secret
    --set harbor.expose.tls.secret.secretName=suse-registry-tls
  )
fi

helm upgrade --install "$RELEASE_NAME" "$CHART_OCI" "${HELM_OPTS[@]}"

log "SUSE Private Registry instalado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# CONCLUSÃO
# ══════════════════════════════════════════════════════════════════════════════
echo ""
info "Verificando pods do Private Registry..."
kubectl get pods -n "$PR_NAMESPACE"

ADMIN_SECRET="${RELEASE_NAME}-harbor-core"
ADMIN_PASS=$(kubectl get secret --namespace "$PR_NAMESPACE" "$ADMIN_SECRET" \
  -o jsonpath="{.data.HARBOR_ADMIN_PASSWORD}" 2>/dev/null | base64 -d 2>/dev/null || true)

echo ""
echo -e "${BOLD}${GREEN}"
cat << 'DONE'
╔══════════════════════════════════════════════════════════════════╗
║              INSTALAÇÃO CONCLUÍDA COM SUCESSO!                  ║
╚══════════════════════════════════════════════════════════════════╝
DONE
echo -e "${NC}"
echo -e "  ${BOLD}Registry URL   :${NC} ${CYAN}https://$PR_HOSTNAME${NC}"
echo -e "  ${BOLD}Usuário admin  :${NC} ${CYAN}admin${NC}"
if [ -n "$ADMIN_PASS" ]; then
  echo -e "  ${BOLD}Senha admin    :${NC} ${CYAN}$ADMIN_PASS${NC}"
else
  echo -e "  ${BOLD}Senha admin    :${NC} ${DIM}execute o comando abaixo para obtê-la:${NC}"
  echo -e "  ${DIM}kubectl get secret --namespace $PR_NAMESPACE $ADMIN_SECRET \\${NC}"
  echo -e "  ${DIM}  -o jsonpath=\"{.data.HARBOR_ADMIN_PASSWORD}\" | base64 -d; echo${NC}"
fi
echo ""
echo -e "  ${DIM}⚠  Aponte o DNS '$PR_HOSTNAME' para o IP do Ingress do cluster:${NC}"
echo -e "  ${DIM}   kubectl get ingress -n $PR_NAMESPACE${NC}"
echo -e "  ${BOLD}Log completo   :${NC} ${CYAN}$LOG_FILE${NC}"
echo ""
