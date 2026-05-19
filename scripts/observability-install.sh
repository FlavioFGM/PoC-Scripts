#!/bin/bash

# ==============================================================================
# INSTALAÇÃO INTERATIVA: SUSE Observability
# via SUSE Application Collection (OCI Registry)
# ==============================================================================

set -eo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

LINUX_IP=$(hostname -I | awk '{print $1}')
MACHINE_HOSTNAME=$(hostname)
AC_REGISTRY="dp.apps.rancher.io"
LOG_FILE="/var/log/observability-install-$(date +%Y%m%d-%H%M%S).log"
VALUES_FILE="/tmp/suse-observability-values-$(date +%Y%m%d%H%M%S).yaml"

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

cleanup() {
  if [ -f "$VALUES_FILE" ]; then
    rm -f "$VALUES_FILE"
    info "Arquivo temporário de values removido com segurança."
  fi
}
trap cleanup EXIT

select_sizing() {
  echo -e "${BOLD}  Perfil de sizing:${NC}"
  echo ""
  echo -e "  ${DIM}── Não-HA (PoC / teste) ─────────────────────────────────────${NC}"
  echo -e "    ${BOLD}1)${NC} trial     — Avaliação rápida, recursos mínimos ${YELLOW}(recomendado para PoC)${NC}"
  echo -e "    ${BOLD}2)${NC} 10-nonha  — Até 10 agentes monitorados"
  echo -e "    ${BOLD}3)${NC} 20-nonha  — Até 20 agentes"
  echo -e "    ${BOLD}4)${NC} 50-nonha  — Até 50 agentes"
  echo -e "    ${BOLD}5)${NC} 100-nonha — Até 100 agentes"
  echo ""
  echo -e "  ${DIM}── HA (produção) ─────────────────────────────────────────────${NC}"
  echo -e "    ${BOLD}6)${NC} 150-ha    — Até 150 agentes (Alta Disponibilidade)"
  echo -e "    ${BOLD}7)${NC} 250-ha    — Até 250 agentes (HA)"
  echo -e "    ${BOLD}8)${NC} 500-ha    — Até 500 agentes (HA)"
  echo -e "    ${BOLD}9)${NC} 4000-ha   — Até 4000 agentes (HA)"
  echo ""
  echo -en "${BOLD}  Escolha [1-9]${NC} ${DIM}[1]${NC}: "
  read -r __choice
  case "${__choice:-1}" in
    1) SIZING_PROFILE="trial"     ;;
    2) SIZING_PROFILE="10-nonha"  ;;
    3) SIZING_PROFILE="20-nonha"  ;;
    4) SIZING_PROFILE="50-nonha"  ;;
    5) SIZING_PROFILE="100-nonha" ;;
    6) SIZING_PROFILE="150-ha"    ;;
    7) SIZING_PROFILE="250-ha"    ;;
    8) SIZING_PROFILE="500-ha"    ;;
    9) SIZING_PROFILE="4000-ha"   ;;
    *) SIZING_PROFILE="trial"; warn "Opção inválida, usando 'trial'." ;;
  esac
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║       INSTALAÇÃO INTERATIVA: SUSE Observability                 ║
║       via SUSE Application Collection                           ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "  ${DIM}Máquina :${NC} ${BOLD}$MACHINE_HOSTNAME${NC} ${DIM}($LINUX_IP)${NC}"
echo -e "  ${DIM}Log     :${NC} ${BOLD}$LOG_FILE${NC}"
echo ""

# ── Verificações iniciais ─────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && error "Este script deve ser executado como root (sudo)."
command -v kubectl &>/dev/null || error "kubectl não encontrado. Execute o rancher-install.sh antes deste script."
command -v helm    &>/dev/null || error "helm não encontrado. Execute o rancher-install.sh antes deste script."

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
kubectl cluster-info &>/dev/null || error "Não foi possível conectar ao cluster Kubernetes. Verifique o KUBECONFIG."

# ══════════════════════════════════════════════════════════════════════════════
# COLETA DE VARIÁVEIS
# ══════════════════════════════════════════════════════════════════════════════
section "CONFIG" "CONFIGURAÇÃO DA INSTALAÇÃO"

echo -e "${BOLD}── Application Collection (SUSE) ──────────────────────────────────${NC}"
prompt        AC_USER  "Usuário"  "flgussi@suse.com"
prompt_secret AC_PASS  "Senha"
echo ""

echo -e "${BOLD}── SUSE Observability ─────────────────────────────────────────────${NC}"
prompt        OBS_VERSION   "Versão do chart"             "2.2.0"
prompt        OBS_NS        "Namespace"                   "suse-observability"
prompt        OBS_BASE_URL  "Base URL (https://...)"      "https://observability.virtnet"
prompt_secret OBS_LICENSE   "License Key"
prompt_secret OBS_ADMIN_PASS "Senha do admin"
echo ""

echo -e "  ${DIM}Receiver API Key — deixe vazio para gerar automaticamente${NC}"
prompt OBS_RECEIVER_KEY "Receiver API Key" ""
echo ""

echo -e "${BOLD}── Sizing ─────────────────────────────────────────────────────────${NC}"
select_sizing
echo -e "  ${DIM}Perfil selecionado: ${BOLD}$SIZING_PROFILE${NC}"
echo ""

echo -e "${BOLD}── Storage (opcional) ─────────────────────────────────────────────${NC}"
echo -e "  ${DIM}Deixe vazio para usar a StorageClass padrão do cluster${NC}"
prompt OBS_STORAGE_CLASS "StorageClass" ""
echo ""

# Extrai hostname da URL para usar no /etc/hosts
OBS_HOSTNAME=$(echo "$OBS_BASE_URL" | sed -E 's|https?://||' | cut -d/ -f1)

# ══════════════════════════════════════════════════════════════════════════════
# RESUMO E CONFIRMAÇÃO
# ══════════════════════════════════════════════════════════════════════════════
section "RESUMO" "O QUE SERÁ INSTALADO"

echo -e "  ${DIM}Application Collection   :${NC} ${BOLD}$AC_USER @ $AC_REGISTRY${NC}"
echo -e "  ${DIM}Namespace                :${NC} ${BOLD}$OBS_NS${NC}"
echo -e "  ${DIM}Versão do chart          :${NC} ${BOLD}$OBS_VERSION${NC}"
echo -e "  ${DIM}Base URL                 :${NC} ${BOLD}$OBS_BASE_URL${NC}"
echo -e "  ${DIM}Sizing profile           :${NC} ${BOLD}$SIZING_PROFILE${NC}"
echo -e "  ${DIM}StorageClass             :${NC} ${BOLD}${OBS_STORAGE_CLASS:-[padrão do cluster]}${NC}"
echo -e "  ${DIM}Receiver API Key         :${NC} ${BOLD}${OBS_RECEIVER_KEY:-[gerada automaticamente]}${NC}"
echo -e "  ${DIM}DNS local (/etc/hosts)   :${NC} ${BOLD}$OBS_HOSTNAME → $LINUX_IP${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Um values.yaml temporário será criado em $VALUES_FILE${NC}"
echo -e "  ${DIM}(removido automaticamente ao final — contém dados sensíveis)${NC}"
echo ""
confirm "  Confirmar e iniciar a instalação?" || { info "Instalação cancelada."; exit 0; }
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 1/7 — KERNEL: TOO MANY OPEN FILES
# ══════════════════════════════════════════════════════════════════════════════
section "1/7" "AJUSTE DE KERNEL — OPEN FILES / INOTIFY / MMAP"

info "O SUSE Observability usa Kafka, Victoria Metrics e múltiplos watchers."
info "Sem esses ajustes, erros 'too many open files' e crashes ocorrem."
echo ""

# ── sysctl permanente ────────────────────────────────────────────────────────
SYSCTL_FILE="/etc/sysctl.d/99-suse-observability.conf"
info "Gravando $SYSCTL_FILE..."
cat > "$SYSCTL_FILE" << 'EOF'
# SUSE Observability — Parâmetros de kernel obrigatórios

# Inotify: watchers para file-system events (usado por vários pods)
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches   = 524288

# Descritores de arquivo globais do sistema
fs.file-max = 1048576

# Memória mapeada — obrigatório para Victoria Metrics / Kafka
vm.max_map_count = 262144
EOF

sysctl --system --pattern "fs.inotify|fs.file-max|vm.max_map_count" > /dev/null
log "Parâmetros de kernel aplicados (runtime + persistência)"

# ── ulimits permanentes ───────────────────────────────────────────────────────
LIMITS_FILE="/etc/security/limits.d/99-suse-observability.conf"
info "Gravando $LIMITS_FILE..."
cat > "$LIMITS_FILE" << 'EOF'
# SUSE Observability — Limites de descritores de arquivo por usuário
*    soft nofile 65536
*    hard nofile 65536
root soft nofile 65536
root hard nofile 65536
*    soft nproc  65536
*    hard nproc  65536
EOF
log "Limites de usuário persistidos em $LIMITS_FILE"

# ── Override do serviço K3s ───────────────────────────────────────────────────
K3S_OVERRIDE_DIR="/etc/systemd/system/k3s.service.d"
K3S_OVERRIDE_FILE="$K3S_OVERRIDE_DIR/nofile-override.conf"

if systemctl list-units --type=service 2>/dev/null | grep -q "k3s.service"; then
  warn "O serviço K3s será reiniciado para aplicar LimitNOFILE=infinity."
  warn "Workloads existentes serão temporariamente interrompidos."
  echo ""
  if confirm "  Reiniciar K3s agora para aplicar os limites?"; then
    mkdir -p "$K3S_OVERRIDE_DIR"
    cat > "$K3S_OVERRIDE_FILE" << 'EOF'
[Service]
LimitNOFILE=infinity
EOF
    systemctl daemon-reload
    systemctl restart k3s
    info "Aguardando K3s reinicializar (25s)..."
    sleep 25
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
    log "K3s reiniciado com LimitNOFILE=infinity ✓"
  else
    warn "K3s não reiniciado. Aplique manualmente depois:"
    warn "  systemctl daemon-reload && systemctl restart k3s"
  fi
else
  info "Serviço K3s não detectado — override de LimitNOFILE ignorado."
fi

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 2/7 — DNS LOCAL
# ══════════════════════════════════════════════════════════════════════════════
section "2/7" "CONFIGURAÇÃO DE DNS LOCAL (/etc/hosts)"

add_hosts_entry() {
  local ip=$1 host=$2
  if grep -qE "^\s*[0-9].*\b${host}\b" /etc/hosts; then
    info "Entrada já existe em /etc/hosts: $host"
  else
    echo "$ip $host" >> /etc/hosts
    log "Adicionado ao /etc/hosts: $ip  $host"
  fi
}

add_hosts_entry "$LINUX_IP" "$OBS_HOSTNAME"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 3/7 — NAMESPACE E SECRET DE IMAGEM
# ══════════════════════════════════════════════════════════════════════════════
section "3/7" "NAMESPACE E SECRET DE IMAGEM"

info "Criando namespace: $OBS_NS"
kubectl create namespace "$OBS_NS" --dry-run=client -o yaml | kubectl apply -f -

info "Criando secret 'application-collection' em $OBS_NS..."
kubectl create secret docker-registry application-collection \
  --docker-server="$AC_REGISTRY" \
  --docker-username="$AC_USER" \
  --docker-password="$AC_PASS" \
  --namespace="$OBS_NS" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Namespace $OBS_NS configurado ✓"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 4/7 — HELM REGISTRY LOGIN
# ══════════════════════════════════════════════════════════════════════════════
section "4/7" "LOGIN NO REGISTRO OCI ($AC_REGISTRY)"

info "Autenticando Helm no Application Collection Registry..."
echo "$AC_PASS" | helm registry login "$AC_REGISTRY" -u "$AC_USER" --password-stdin
log "Login realizado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 5/7 — GERAÇÃO DO VALUES.YAML
# ══════════════════════════════════════════════════════════════════════════════
section "5/7" "GERAÇÃO DO ARQUIVO DE CONFIGURAÇÃO"

info "Gerando values.yaml em $VALUES_FILE..."

{
  echo "global:"
  [ -n "$OBS_STORAGE_CLASS" ] && echo "  storageClass: \"$OBS_STORAGE_CLASS\""
  echo "  suseObservability:"
  echo "    license: \"$OBS_LICENSE\""
  echo "    baseUrl: \"$OBS_BASE_URL\""
  echo "    sizing:"
  echo "      profile: \"$SIZING_PROFILE\""
  echo "    adminPassword: \"$OBS_ADMIN_PASS\""
  [ -n "$OBS_RECEIVER_KEY" ] && echo "    receiverApiKey: \"$OBS_RECEIVER_KEY\""
  echo "    pullSecret:"
  echo "      username: \"$AC_USER\""
  echo "      password: \"$AC_PASS\""
} > "$VALUES_FILE"

log "Values gerado. Estrutura (campos sensíveis ocultados):"
echo ""
echo -e "  ${DIM}global:"
echo -e "    suseObservability:"
echo -e "      license:       [configurada]"
echo -e "      baseUrl:       $OBS_BASE_URL"
echo -e "      sizing.profile: $SIZING_PROFILE"
echo -e "      adminPassword: [configurada]"
[ -n "$OBS_RECEIVER_KEY" ] && echo -e "      receiverApiKey: [configurada]"
[ -n "$OBS_STORAGE_CLASS" ] && echo -e "    storageClass:  $OBS_STORAGE_CLASS"
echo -e "    pullSecret:    [configurada]${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 6/7 — HELM INSTALL
# ══════════════════════════════════════════════════════════════════════════════
section "6/7" "INSTALAÇÃO VIA HELM — APPLICATION COLLECTION"

OBS_CHART="oci://$AC_REGISTRY/charts/suse-observability"
OBS_VERSION_HELM="${OBS_VERSION#v}"

info "Chart   : $OBS_CHART"
info "Versão  : $OBS_VERSION_HELM"
info "Release : suse-observability"
info "Esta etapa pode levar 10-20 minutos dependendo do perfil de sizing..."
echo ""

helm upgrade --install suse-observability "$OBS_CHART" \
  --version "$OBS_VERSION_HELM" \
  --namespace "$OBS_NS" \
  --values "$VALUES_FILE" \
  --timeout 20m \
  --wait

log "SUSE Observability $OBS_VERSION instalado com sucesso!"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 7/7 — STATUS E ACESSO
# ══════════════════════════════════════════════════════════════════════════════
section "7/7" "STATUS E INFORMAÇÕES DE ACESSO"

info "Verificando pods no namespace $OBS_NS..."
echo ""
kubectl get pods -n "$OBS_NS"
echo ""

echo -e "${BOLD}${GREEN}"
cat << 'DONE'
╔══════════════════════════════════════════════════════════════════╗
║       SUSE OBSERVABILITY INSTALADO COM SUCESSO!                 ║
╚══════════════════════════════════════════════════════════════════╝
DONE
echo -e "${NC}"

echo -e "  ${BOLD}Acesso via ingress / hostname:${NC}"
echo -e "    ${CYAN}$OBS_BASE_URL${NC}"
echo ""
echo -e "  ${BOLD}Acesso via port-forward${NC} ${DIM}(se não houver ingress configurado):${NC}"
echo -e "    ${DIM}kubectl port-forward service/suse-observability-suse-observability-router \\"
echo -e "      8080:8080 --namespace $OBS_NS${NC}"
echo -e "    Acesse: ${CYAN}http://localhost:8080${NC}"
echo ""
echo -e "  ${BOLD}Credenciais iniciais:${NC}"
echo -e "    Usuário : ${BOLD}admin${NC}"
echo -e "    Senha   : ${BOLD}[definida durante a instalação]${NC}"
echo ""
echo -e "  ${BOLD}Parâmetros de kernel aplicados${NC} ${DIM}(persistentes):${NC}"
echo -e "    ${DIM}fs.inotify.max_user_instances = 8192${NC}"
echo -e "    ${DIM}fs.inotify.max_user_watches   = 524288${NC}"
echo -e "    ${DIM}fs.file-max                   = 1048576${NC}"
echo -e "    ${DIM}vm.max_map_count              = 262144${NC}"
echo ""
echo -e "  ${BOLD}Log completo:${NC} ${CYAN}$LOG_FILE${NC}"
echo ""
