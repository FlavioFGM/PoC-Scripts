#!/bin/bash

# ==============================================================================
# INSTALAÇÃO INTERATIVA: K3s + Rancher Prime
# ==============================================================================

set -eo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

LINUX_IP=$(hostname -I | awk '{print $1}')
MACHINE_HOSTNAME=$(hostname)
LOG_FILE="/var/log/rancher-install-$(date +%Y%m%d-%H%M%S).log"
AC_REGISTRY="dp.apps.rancher.io"

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
║        INSTALAÇÃO INTERATIVA: K3s + Rancher Prime               ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "  ${DIM}Máquina :${NC} ${BOLD}$MACHINE_HOSTNAME${NC} ${DIM}($LINUX_IP)${NC}"
echo -e "  ${DIM}Log     :${NC} ${BOLD}$LOG_FILE${NC}"
echo ""

# ── Verificação de root ───────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && error "Este script deve ser executado como root (sudo)."

# ══════════════════════════════════════════════════════════════════════════════
# COLETA DE VARIÁVEIS
# ══════════════════════════════════════════════════════════════════════════════
section "CONFIG" "CONFIGURAÇÃO DA INSTALAÇÃO"

echo -e "${BOLD}── Application Collection (SUSE) ──────────────────────────────────${NC}"
prompt        AC_USER              "Usuário"                           "flgussi@suse.com"
prompt_secret AC_PASS              "Senha"
echo ""

echo -e "${BOLD}── Versões dos Componentes ────────────────────────────────────────${NC}"
echo -e "  ${DIM}Referência: https://www.suse.com/suse-rancher/support-matrix/${NC}"
echo ""
prompt K3S_VERSION      "Versão do K3s       (ex: v1.31.5+k3s1)" "v1.31.5+k3s1"
prompt RANCHER_VERSION  "Versão do Rancher   (ex: 2.10.3)"        "2.10.3"
prompt CERTMGR_VERSION  "Versão Cert-Manager (ex: v1.16.2)"       "v1.16.2"
echo ""

echo -e "${BOLD}── Configuração do Rancher ────────────────────────────────────────${NC}"
prompt        RANCHER_HOSTNAME "Hostname do Rancher"   "rancher.virtnet"
prompt        RANCHER_REPLICAS "Número de réplicas"    "1"
prompt_secret RANCHER_BOOTSTRAP_PASS "Senha de bootstrap"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# VERIFICAÇÃO DE COMPATIBILIDADE
# ══════════════════════════════════════════════════════════════════════════════
section "COMPAT" "VERIFICAÇÃO DE COMPATIBILIDADE DE VERSÕES"

# Extrai minor do K3s: "v1.31.5+k3s1" → "31"
K3S_MINOR=$(echo "$K3S_VERSION" | grep -oP 'v1\.\K[0-9]+' | head -1)

# Extrai major e minor do Rancher: "2.10.3" → "2", "10"
RANCHER_MAJOR=$(echo "$RANCHER_VERSION" | cut -d. -f1)
RANCHER_MINOR=$(echo "$RANCHER_VERSION" | cut -d. -f2)

# Extrai minor do Cert-Manager: "v1.16.2" → "16"
CERTMGR_MINOR=$(echo "$CERTMGR_VERSION" | grep -oP 'v?1\.\K[0-9]+' | head -1)

info "Analisando: Rancher $RANCHER_VERSION | K3s 1.$K3S_MINOR | Cert-Manager 1.$CERTMGR_MINOR"
echo ""

COMPAT_WARN=false

# ── Rancher vs K3s ──────────────────────────────────────────────────────────
echo -e "  ${BOLD}Rancher vs K3s:${NC}"
if [ "$RANCHER_MAJOR" = "2" ]; then
  case "$RANCHER_MINOR" in
    10) SUPPORTED_K3S="29 30 31"; NOTE="v1.29 a v1.31" ;;
    9)  SUPPORTED_K3S="28 29 30"; NOTE="v1.28 a v1.30" ;;
    8)  SUPPORTED_K3S="27 28 29"; NOTE="v1.27 a v1.29" ;;
    7)  SUPPORTED_K3S="24 25 26"; NOTE="v1.24 a v1.26" ;;
    *)  SUPPORTED_K3S=""; NOTE="(versão fora da matriz conhecida)" ;;
  esac

  if [ -z "$SUPPORTED_K3S" ]; then
    warn "Rancher 2.$RANCHER_MINOR não está na matriz de compatibilidade conhecida."
    COMPAT_WARN=true
  elif echo "$SUPPORTED_K3S" | grep -qw "$K3S_MINOR"; then
    log "Rancher $RANCHER_VERSION + K3s 1.$K3S_MINOR → compatível (suporte: $NOTE)"
  else
    warn "Rancher $RANCHER_VERSION suporta K3s $NOTE"
    warn "K3s 1.$K3S_MINOR está FORA do suporte oficial para Rancher $RANCHER_VERSION"
    COMPAT_WARN=true
  fi
else
  warn "Versão do Rancher ($RANCHER_VERSION) não reconhecida pela matriz."
  COMPAT_WARN=true
fi

# ── Rancher vs Cert-Manager ──────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Rancher vs Cert-Manager:${NC}"
if [ -z "$CERTMGR_MINOR" ]; then
  warn "Não foi possível interpretar a versão do Cert-Manager: $CERTMGR_VERSION"
  COMPAT_WARN=true
elif [ "$CERTMGR_MINOR" -lt 11 ]; then
  warn "Cert-Manager < v1.11.0 não é suportado pelo Rancher. Mínimo: v1.11.0"
  COMPAT_WARN=true
else
  case "$RANCHER_MINOR" in
    10) REC_CM="v1.16.x"; MIN_CM=14 ;;
    9)  REC_CM="v1.14.x ou v1.15.x"; MIN_CM=13 ;;
    8)  REC_CM="v1.13.x ou v1.14.x"; MIN_CM=11 ;;
    *)  REC_CM="v1.11+"; MIN_CM=11 ;;
  esac

  if [ "$CERTMGR_MINOR" -lt "$MIN_CM" ]; then
    warn "Para Rancher $RANCHER_VERSION, recomenda-se Cert-Manager $REC_CM"
    warn "Cert-Manager 1.$CERTMGR_MINOR pode apresentar incompatibilidades"
    COMPAT_WARN=true
  else
    log "Rancher $RANCHER_VERSION + Cert-Manager 1.$CERTMGR_MINOR → compatível (recomendado: $REC_CM)"
  fi
fi

# ── Alerta final ─────────────────────────────────────────────────────────────
echo ""
if [ "$COMPAT_WARN" = true ]; then
  echo -e "  ${YELLOW}${BOLD}⚠  Foram detectados avisos de compatibilidade acima.${NC}"
  echo -e "  ${DIM}Referência oficial: https://www.suse.com/suse-rancher/support-matrix/${NC}"
  echo ""
  confirm "  Deseja continuar mesmo assim?" || { info "Instalação cancelada."; exit 0; }
else
  log "Todas as versões são compatíveis entre si."
fi

# ══════════════════════════════════════════════════════════════════════════════
# RESUMO E CONFIRMAÇÃO FINAL
# ══════════════════════════════════════════════════════════════════════════════
section "RESUMO" "O QUE SERÁ INSTALADO"

echo -e "  ${DIM}Máquina              :${NC} ${BOLD}$MACHINE_HOSTNAME ($LINUX_IP)${NC}"
echo -e "  ${DIM}DNS local            :${NC} ${BOLD}$MACHINE_HOSTNAME + $RANCHER_HOSTNAME → $LINUX_IP${NC}"
echo -e "  ${DIM}Application Coll.    :${NC} ${BOLD}$AC_USER @ $AC_REGISTRY${NC}"
echo -e "  ${DIM}K3s                  :${NC} ${BOLD}$K3S_VERSION${NC}"
echo -e "  ${DIM}Rancher Prime        :${NC} ${BOLD}$RANCHER_VERSION${NC} (hostname: $RANCHER_HOSTNAME, réplicas: $RANCHER_REPLICAS)"
echo -e "  ${DIM}Cert-Manager         :${NC} ${BOLD}$CERTMGR_VERSION${NC}"
echo -e "  ${DIM}Log                  :${NC} ${BOLD}$LOG_FILE${NC}"
echo ""
confirm "  Confirmar e iniciar a instalação?" || { info "Instalação cancelada."; exit 0; }
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 1 — DNS LOCAL
# ══════════════════════════════════════════════════════════════════════════════
section "1/8" "CONFIGURAÇÃO DE DNS LOCAL (/etc/hosts)"

add_hosts_entry() {
  local ip=$1 host=$2
  if grep -qE "^\s*[0-9].*\b${host}\b" /etc/hosts; then
    info "Entrada já existe em /etc/hosts: $host"
  else
    echo "$ip $host" >> /etc/hosts
    log "Adicionado ao /etc/hosts: $ip  $host"
  fi
}

add_hosts_entry "$LINUX_IP" "$MACHINE_HOSTNAME"
add_hosts_entry "$LINUX_IP" "$RANCHER_HOSTNAME"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 2 — HELM
# ══════════════════════════════════════════════════════════════════════════════
section "2/8" "INSTALAÇÃO DO HELM"

[ -L /usr/local/bin/helm ] && { info "Removendo link simbólico de helm..."; rm -f /usr/local/bin/helm; }

if command -v helm &> /dev/null; then
  log "Helm já instalado: $(helm version --short)"
else
  info "Baixando e instalando Helm (versão mais recente)..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log "Helm instalado: $(helm version --short)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 3 — K3s
# ══════════════════════════════════════════════════════════════════════════════
section "3/8" "INSTALAÇÃO DO K3s ($K3S_VERSION)"

info "Versão : $K3S_VERSION"
info "Modo   : server com --cluster-init (HA-ready)"
info "Iniciando download e instalação..."

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - server \
  --cluster-init \
  --write-kubeconfig-mode 644

log "K3s instalado com sucesso!"
info "Aguardando K3s inicializar (15s)..."
sleep 15

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 4 — KUBECONFIG
# ══════════════════════════════════════════════════════════════════════════════
section "4/8" "CONFIGURAÇÃO DO KUBECONFIG"

mkdir -p "$HOME/.kube"
cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sed -i "s/127.0.0.1/$LINUX_IP/g" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

info "Verificando nós do cluster..."
kubectl get nodes
log "Kubeconfig configurado. API endpoint: https://$LINUX_IP:6443"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 5 — NAMESPACES E SECRETS
# ══════════════════════════════════════════════════════════════════════════════
section "5/8" "NAMESPACES E SECRETS DE IMAGEM"

for ns in cattle-system cert-manager opencost; do
  info "Configurando namespace: $ns"
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret docker-registry application-collection \
    --docker-server="$AC_REGISTRY" \
    --docker-username="$AC_USER" \
    --docker-password="$AC_PASS" \
    --namespace="$ns" \
    --dry-run=client -o yaml | kubectl apply -f -

  log "Namespace $ns: pronto ✓"
done

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 6 — HELM REGISTRY LOGIN
# ══════════════════════════════════════════════════════════════════════════════
section "6/8" "LOGIN NO REGISTRO OCI ($AC_REGISTRY)"

info "Autenticando Helm no Application Collection Registry..."
echo "$AC_PASS" | helm registry login "$AC_REGISTRY" -u "$AC_USER" --password-stdin
log "Login realizado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 7 — CERT-MANAGER
# ══════════════════════════════════════════════════════════════════════════════
section "7/8" "INSTALAÇÃO DO CERT-MANAGER ($CERTMGR_VERSION)"

# Helm OCI não aceita prefixo "v"
CERTMGR_VERSION_HELM="${CERTMGR_VERSION#v}"

info "Chart  : oci://$AC_REGISTRY/charts/cert-manager"
info "Versão : $CERTMGR_VERSION_HELM"

helm upgrade --install cert-manager "oci://$AC_REGISTRY/charts/cert-manager" \
  --version "$CERTMGR_VERSION_HELM" \
  -n cert-manager \
  --set "global.imagePullSecrets[0].name=application-collection" \
  --set crds.enabled=true \
  --wait \
  --timeout 10m

log "Cert-Manager $CERTMGR_VERSION instalado com sucesso!"
echo ""
kubectl get pods -n cert-manager

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 8 — RANCHER PRIME
# ══════════════════════════════════════════════════════════════════════════════
section "8/8" "INSTALAÇÃO DO RANCHER PRIME ($RANCHER_VERSION)"

info "Adicionando repositório rancher-prime..."
helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
helm repo update

info "Hostname  : $RANCHER_HOSTNAME"
info "Versão    : $RANCHER_VERSION"
info "Réplicas  : $RANCHER_REPLICAS"
info "Iniciando instalação (pode levar alguns minutos)..."

helm upgrade --install rancher rancher-prime/rancher \
  --namespace cattle-system \
  --version "$RANCHER_VERSION" \
  --set hostname="$RANCHER_HOSTNAME" \
  --set replicas="$RANCHER_REPLICAS" \
  --set bootstrapPassword="$RANCHER_BOOTSTRAP_PASS" \
  --set "global.imagePullSecrets[0].name=application-collection" \
  --wait \
  --timeout 15m

log "Rancher Prime $RANCHER_VERSION instalado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# CONCLUSÃO
# ══════════════════════════════════════════════════════════════════════════════
echo ""
info "Verificando rollout do Rancher..."
kubectl -n cattle-system rollout status deploy/rancher

echo ""
echo -e "${BOLD}${GREEN}"
cat << 'DONE'
╔══════════════════════════════════════════════════════════════════╗
║              INSTALAÇÃO CONCLUÍDA COM SUCESSO!                  ║
╚══════════════════════════════════════════════════════════════════╝
DONE
echo -e "${NC}"
echo -e "  ${BOLD}Rancher UI   :${NC} ${CYAN}https://$RANCHER_HOSTNAME${NC}"
echo -e "  ${BOLD}Log completo :${NC} ${CYAN}$LOG_FILE${NC}"
echo ""
