# MEMORY.md — Contexto do Projeto para Claude

> Este arquivo é destinado a sessões futuras de Claude (ou outros agentes de IA) que trabalhem neste repositório. Contém decisões de design, histórico relevante e instruções de comportamento esperado.

---

## Identidade do projeto

- **Repositório:** https://github.com/FlavioFGM/PoC-Scripts
- **Dono:** Flávio Gussi — `flgussi@suse.com` / `Flavio_FGM@hotmail.com`
- **Cargo:** Engenheiro SUSE — usa o repositório para scripts de PoC com clientes
- **Idioma do projeto:** Português (BR) — comentários, docs e mensagens de log em PT-BR
- **Ambiente alvo:** openSUSE Leap 15.x / SLES — usar `zypper` para instalar pacotes no host

---

## Contexto técnico

### Stack atual

| Componente | Versão padrão | Origem |
|------------|--------------|--------|
| K3s | v1.33.7+k3s3 | https://get.k3s.io |
| Rancher Prime | 2.14.1 | Helm repo: `rancher-prime` |
| Cert-Manager | v1.17.2 | OCI: `dp.apps.rancher.io/charts/cert-manager` |
| SUSE Observability | 2.2.0 | OCI: `dp.apps.rancher.io/charts/suse-observability` |
| SUSE Private Registry | latest | OCI: `registry.suse.com/private-registry/private-registry-helm` |
| Helm | latest | https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 |
| Registry AC | dp.apps.rancher.io | SUSE Application Collection — fixo |
| Registry SCC | registry.suse.com | SUSE Customer Center — Private Registry |

### Matriz de compatibilidade (última atualização: 2026-05-20)

| Rancher | K3s suportado | Cert-Manager recomendado |
|---------|---------------|--------------------------|
| 2.14.x  | v1.33 – v1.35 | v1.17.x+ (mín: 1.15)     |
| 2.13.x  | v1.32 – v1.34 | v1.17.x+ (mín: 1.15)     |
| 2.12.x  | v1.31 – v1.33 | v1.17.x+ (mín: 1.15)     |
| 2.11.x  | v1.30 – v1.32 | v1.17.x+ (mín: 1.14)     |
| 2.10.x  | v1.29 – v1.31 | v1.16.x (mín: 1.14)      |
| 2.9.x   | v1.28 – v1.30 | v1.14 – v1.15 (mín: 1.13)|
| 2.8.x   | v1.27 – v1.29 | v1.13 – v1.14 (mín: 1.11)|
| 2.7.x   | v1.24 – v1.26 | v1.11+ (mín: 1.11)       |

Referência: https://www.suse.com/suse-rancher/support-matrix/

---

## Decisões de design tomadas

### 1. Script único e interativo
O script `rancher-install.sh` **não usa arquivo de configuração externo** — todas as variáveis são coletadas via prompts. Motivo: PoCs acontecem em ambientes novos; um único arquivo autocontido reduz erros de configuração.

### 2. Senhas nunca ficam em arquivos
Senhas são lidas com `read -rs` (sem eco) e usadas apenas em variáveis de ambiente na memória do processo. **Não armazenar senhas em arquivos, não logar valores de senhas.**

### 3. Log automático completo
`exec > >(tee -a "$LOG_FILE") 2>&1` no início do script garante que toda saída (stdout + stderr) vai para `/var/log/rancher-install-YYYYMMDD-HHMMSS.log`. Manter esse comportamento em todos os scripts.

### 4. Versão do Cert-Manager para Helm
O Helm OCI não aceita prefixo `v` em versões. A variável `CERTMGR_VERSION` é coletada com `v` (ex: `v1.16.2`) mas o `v` é removido antes do `helm upgrade --install` com `${CERTMGR_VERSION#v}`. **Aplicar esse padrão a outros scripts com charts OCI.**

### 5. DNS local no início
O script adiciona entradas ao `/etc/hosts` antes de instalar qualquer componente. Isso garante que o hostname do Rancher resolve localmente mesmo sem DNS externo configurado — essencial em labs e PoCs isoladas.

### 6. Verificação de compatibilidade com confirmação
O bloco de compatibilidade emite avisos mas **não bloqueia** a instalação — apenas pede confirmação. O usuário pode ter razões para usar versões fora da matriz (testing, edge cases).

### 7. cluster-init no K3s
O K3s é instalado com `--cluster-init` para habilitar HA futuro sem reinstalação. Mesmo em PoC single-node, isso não tem overhead significativo.

### 8. observability-install.sh — values.yaml temporário
O script gera um `/tmp/suse-observability-values-*.yaml` com credenciais e license key. Esse arquivo é deletado automaticamente via `trap cleanup EXIT`. Não persistir esse arquivo nem versioná-lo.

### 9. observability-install.sh — kernel tuning obrigatório
O SUSE Observability requer ajustes de kernel no host antes de instalar, ou os pods entram em crash/OOMKilled com erros `too many open files`. Os parâmetros são aplicados em runtime (`sysctl --system`) e persistidos em `/etc/sysctl.d/99-suse-observability.conf`. O serviço K3s recebe um override `LimitNOFILE=infinity` para herdar aos pods. O script pede confirmação antes de reiniciar K3s, pois isso impacta workloads existentes.

### 10. observability-install.sh — sizing profiles
O campo `sizing.profile` no values.yaml define o perfil de recursos. Para PoC, sempre usar `trial`. Nunca usar perfis HA em ambientes sem múltiplos nós — os pods ficarão em Pending por falta de recursos.

---

## Como Claude deve trabalhar neste repositório

1. **Sempre atualizar este MEMORY.md** ao fazer mudanças de design ou adicionar novos scripts
2. **Sempre atualizar o README.md** se mudar comportamento visível ao usuário
3. **Manter padrão de logging** — usar as funções `log()`, `info()`, `warn()`, `error()`, `section()` definidas no script
4. **Não adicionar dependências externas** sem justificativa — o objetivo é um script autocontido
5. **Testar sintaxe** com `bash -n script.sh` antes de commitar
6. **Commits em português** — mensagens de commit no mesmo idioma do projeto
7. **Atualizar a tabela de versões** em MEMORY.md e CONTRIBUTING.md sempre que os defaults mudarem
8. **Não armazenar credenciais** em nenhum arquivo do repositório

---

## Histórico de mudanças relevantes

| Data | Mudança | Motivo |
|------|---------|--------|
| 2026-05-19 | Criação inicial do repositório e script `rancher-install.sh` | Migração de script estático para script interativo com verificação de compatibilidade |
| 2026-05-19 | Adição de DNS local (etapa 1/8 do rancher-install) | Garantir resolução do hostname do Rancher em labs sem DNS externo |
| 2026-05-19 | Verificação de compatibilidade Rancher × K3s × Cert-Manager | Prevenir instalações com versões incompatíveis |
| 2026-05-19 | Criação do `observability-install.sh` | Automação da instalação do SUSE Observability via Application Collection com ajuste de kernel para too many open files |
