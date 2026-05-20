#!/bin/bash

# ==============================================================================
# PATCH DE KERNEL: Too Many Open Files
# ==============================================================================
# Aplica parâmetros obrigatórios de kernel e limites de sistema para clusters
# K3s com múltiplos produtos SUSE instalados — em especial SUSE Security
# (NeuVector) e SUSE Observability juntos, que geram alta demanda de file
# descriptors, inotify watches e memória mapeada.
#
# Execute ANTES de instalar SUSE Security ou SUSE Observability.
# ==============================================================================

set -eo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

LINUX_IP=$(hostname -I | awk '{print $1}')
MACHINE_HOSTNAME=$(hostname)
LOG_FILE="/var/log/kernel-patch-$(date +%Y%m%d-%H%M%S).log"

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
║   PATCH DE KERNEL: Too Many Open Files                          ║
║   Pré-requisito para SUSE Security + SUSE Observability         ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"
echo -e "  ${DIM}Máquina :${NC} ${BOLD}$MACHINE_HOSTNAME${NC} ${DIM}($LINUX_IP)${NC}"
echo -e "  ${DIM}Log     :${NC} ${BOLD}$LOG_FILE${NC}"
echo ""
echo -e "  ${DIM}Quando SUSE Security (NeuVector) e SUSE Observability são instalados${NC}"
echo -e "  ${DIM}no mesmo cluster, os pods entram em crash com erros${NC}"
echo -e "  ${BOLD}  'too many open files'${NC} ${DIM}e${NC} ${BOLD}'inotify limit reached'${NC}${DIM}.${NC}"
echo -e "  ${DIM}Este script corrige o problema de forma persistente no host.${NC}"
echo ""

# ── Verificação de root ───────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && error "Este script deve ser executado como root (sudo)."

# ══════════════════════════════════════════════════════════════════════════════
# STATUS ATUAL
# ══════════════════════════════════════════════════════════════════════════════
section "STATUS" "VALORES ATUAIS DO KERNEL"

echo -e "  ${BOLD}Parâmetro                                  Atual       Necessário${NC}"
echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${NC}"
printf "  ${CYAN}%-42s${NC} %-12s ${GREEN}%s${NC}\n" \
  "fs.inotify.max_user_instances" \
  "$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 'N/A')" \
  "8192"
printf "  ${CYAN}%-42s${NC} %-12s ${GREEN}%s${NC}\n" \
  "fs.inotify.max_user_watches" \
  "$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 'N/A')" \
  "1048576"
printf "  ${CYAN}%-42s${NC} %-12s ${GREEN}%s${NC}\n" \
  "fs.file-max" \
  "$(sysctl -n fs.file-max 2>/dev/null || echo 'N/A')" \
  "2097152"
printf "  ${CYAN}%-42s${NC} %-12s ${GREEN}%s${NC}\n" \
  "vm.max_map_count" \
  "$(sysctl -n vm.max_map_count 2>/dev/null || echo 'N/A')" \
  "524288"
echo ""

confirm "  Aplicar as configurações acima?" || { info "Operação cancelada."; exit 0; }
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 1/3 — PARÂMETROS DE KERNEL
# ══════════════════════════════════════════════════════════════════════════════
section "1/3" "PARÂMETROS DE KERNEL (sysctl)"

SYSCTL_FILE="/etc/sysctl.d/99-suse-k8s-limits.conf"
info "Gravando $SYSCTL_FILE..."

cat > "$SYSCTL_FILE" << 'EOF'
# SUSE Security + SUSE Observability — Parâmetros de kernel obrigatórios
# Aplicar ANTES de instalar os produtos acima no mesmo cluster K3s.

# Inotify: NeuVector e Observability juntos consomem muitos watchers
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches   = 1048576

# Descritores de arquivo globais — NeuVector + Kafka + VictoriaMetrics
fs.file-max = 2097152

# Memória mapeada — obrigatório para Victoria Metrics, Kafka e NeuVector
vm.max_map_count = 524288
EOF

sysctl --system --pattern "fs.inotify|fs.file-max|vm.max_map_count" > /dev/null
log "Parâmetros de kernel aplicados (runtime + persistência)"
echo ""
echo -e "  ${DIM}Valores ativos:${NC}"
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches \
       fs.file-max vm.max_map_count 2>/dev/null | sed 's/^/    /'

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 2/3 — LIMITES DE USUÁRIO
# ══════════════════════════════════════════════════════════════════════════════
section "2/3" "LIMITES DE USUÁRIO (ulimits)"

LIMITS_FILE="/etc/security/limits.d/99-suse-k8s-limits.conf"
info "Gravando $LIMITS_FILE..."

cat > "$LIMITS_FILE" << 'EOF'
# SUSE Security + SUSE Observability — Limites de descritores por usuário
*    soft nofile 131072
*    hard nofile 131072
root soft nofile 131072
root hard nofile 131072
*    soft nproc  65536
*    hard nproc  65536
EOF

log "Limites de usuário persistidos em $LIMITS_FILE"

# ══════════════════════════════════════════════════════════════════════════════
# ETAPA 3/3 — OVERRIDE DO SERVIÇO K3s
# ══════════════════════════════════════════════════════════════════════════════
section "3/3" "OVERRIDE DO SERVIÇO K3s (LimitNOFILE=infinity)"

K3S_OVERRIDE_DIR="/etc/systemd/system/k3s.service.d"
K3S_OVERRIDE_FILE="$K3S_OVERRIDE_DIR/nofile-override.conf"

if systemctl list-units --type=service 2>/dev/null | grep -q "k3s.service"; then
  info "Criando override systemd: $K3S_OVERRIDE_FILE"
  mkdir -p "$K3S_OVERRIDE_DIR"
  cat > "$K3S_OVERRIDE_FILE" << 'EOF'
[Service]
LimitNOFILE=infinity
EOF
  systemctl daemon-reload
  log "Override criado — K3s herdará LimitNOFILE=infinity para todos os pods"
  echo ""
  warn "O K3s precisa ser reiniciado para aplicar o override."
  warn "Workloads existentes serão temporariamente interrompidos."
  echo ""
  if confirm "  Reiniciar K3s agora?"; then
    systemctl restart k3s
    info "Aguardando K3s reinicializar (25s)..."
    sleep 25
    kubectl wait --for=condition=Ready nodes --all --timeout=120s 2>/dev/null \
      && log "K3s reiniciado com LimitNOFILE=infinity ✓" \
      || warn "Aguarde os nós ficarem Ready antes de instalar os produtos."
  else
    warn "K3s não reiniciado. Execute manualmente antes de instalar os produtos:"
    warn "  systemctl daemon-reload && systemctl restart k3s"
  fi
else
  info "Serviço K3s não detectado — override ignorado."
  info "Aplique LimitNOFILE=infinity ao runtime de container do seu ambiente."
fi

# ══════════════════════════════════════════════════════════════════════════════
# CONCLUSÃO
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'DONE'
╔══════════════════════════════════════════════════════════════════╗
║              PATCH DE KERNEL APLICADO COM SUCESSO!              ║
╚══════════════════════════════════════════════════════════════════╝
DONE
echo -e "${NC}"
echo -e "  ${BOLD}Arquivos criados / atualizados:${NC}"
echo -e "    ${CYAN}$SYSCTL_FILE${NC}"
echo -e "    ${CYAN}$LIMITS_FILE${NC}"
[ -f "$K3S_OVERRIDE_FILE" ] && echo -e "    ${CYAN}$K3S_OVERRIDE_FILE${NC}"
echo ""
echo -e "  ${BOLD}Verificar parâmetros ativos:${NC}"
echo -e "    ${DIM}sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches \\${NC}"
echo -e "    ${DIM}       fs.file-max vm.max_map_count${NC}"
echo ""
echo -e "  ${BOLD}Próximos passos:${NC}"
echo -e "    ${DIM}Execute este script antes de instalar:${NC}"
echo -e "    ${DIM}  • SUSE Security (NeuVector)${NC}"
echo -e "    ${DIM}  • SUSE Observability${NC}"
echo ""
echo -e "  ${BOLD}Log completo:${NC} ${CYAN}$LOG_FILE${NC}"
echo ""
