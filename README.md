# PoC-Scripts

Scripts de automação para ambientes de Prova de Conceito (PoC) com tecnologias SUSE.

---

## Conteúdo

| Script | Descrição |
|--------|-----------|
| [`scripts/kernel-patch.sh`](scripts/kernel-patch.sh) | Patch de kernel obrigatório para clusters com SUSE Security + SUSE Observability |
| [`scripts/rancher-install.sh`](scripts/rancher-install.sh) | Instalação interativa de K3s + Rancher Prime via Application Collection |
| [`scripts/longhorn-install.sh`](scripts/longhorn-install.sh) | Instalação interativa do SUSE Storage (Longhorn) via Application Collection |
| [`scripts/observability-install.sh`](scripts/observability-install.sh) | Instalação interativa do SUSE Observability via Application Collection |
| [`scripts/private-registry-install.sh`](scripts/private-registry-install.sh) | Instalação interativa do SUSE Private Registry via SUSE Customer Center |

> **Ordem recomendada:** `kernel-patch.sh` → `rancher-install.sh` → demais scripts na ordem desejada.

---

## rancher-install.sh

Script interativo que instala e configura um cluster K3s single-node com Rancher Prime, utilizando o **SUSE Application Collection** como registry de imagens e charts.

### Pré-requisitos

| Requisito | Detalhe |
|-----------|---------|
| Sistema operacional | openSUSE Leap 15.x / SLES 15.x |
| Acesso root | `sudo` ou sessão como root |
| Conectividade | Acesso à internet (download K3s, Helm, charts OCI) |
| Credenciais | Conta ativa no [SUSE Application Collection](https://apps.rancher.io) |
| Portas liberadas | `6443` (API K3s), `80`, `443` (Rancher UI) |

### Como usar

```bash
# 1. Clonar o repositório
git clone https://github.com/FlavioFGM/PoC-Scripts.git
cd PoC-Scripts

# 2. Dar permissão de execução
chmod +x scripts/rancher-install.sh

# 3. Executar como root
sudo bash scripts/rancher-install.sh
```

### Passo a passo da execução

O script é totalmente interativo e guia você por todas as etapas. Ao executar, você verá:

#### Fase 1 — Coleta de variáveis

O script solicita as seguintes informações antes de iniciar qualquer instalação:

| Variável | Exemplo | Descrição |
|----------|---------|-----------|
| Usuário Application Collection | `usuario@suse.com` | Login do portal apps.rancher.io |
| Senha Application Collection | `********` | Digitada sem eco no terminal |
| Versão do K3s | `v1.33.7+k3s3` | Formato: `vX.Y.Z+k3sN` |
| Versão do Rancher | `2.14.1` | Formato: `X.Y.Z` |
| Versão do Cert-Manager | `v1.17.2` | Formato: `vX.Y.Z` |
| Hostname do Rancher | `rancher.virtnet` | FQDN que será usado para acessar a UI |
| Número de réplicas | `1` | Para PoC, usar `1` |
| Senha de bootstrap | `********` | Senha inicial de acesso ao Rancher |

#### Fase 2 — Verificação de compatibilidade

Antes de instalar, o script valida automaticamente a combinação de versões:

```
── Rancher vs K3s:
  ✔  Rancher 2.14.1 + K3s 1.33 → compatível (suporte: v1.33 a v1.35)

── Rancher vs Cert-Manager:
  ✔  Rancher 2.14.1 + Cert-Manager 1.17 → compatível (recomendado: v1.17.x+)
```

Se detectar incompatibilidades, exibe avisos e pergunta se deseja continuar.

**Matriz de compatibilidade conhecida:**

| Rancher | K3s suportado | Cert-Manager recomendado |
|---------|---------------|--------------------------|
| 2.14.x  | v1.33 – v1.35 | v1.17.x+                 |
| 2.13.x  | v1.32 – v1.34 | v1.17.x+                 |
| 2.12.x  | v1.31 – v1.33 | v1.17.x+                 |
| 2.11.x  | v1.30 – v1.32 | v1.17.x+                 |
| 2.10.x  | v1.29 – v1.31 | v1.16.x                  |
| 2.9.x   | v1.28 – v1.30 | v1.14.x – v1.15.x        |
| 2.8.x   | v1.27 – v1.29 | v1.13.x – v1.14.x        |
| 2.7.x   | v1.24 – v1.26 | v1.11+                   |

> Referência oficial: https://www.suse.com/suse-rancher/support-matrix/

#### Fase 3 — Resumo e confirmação

Exibe um resumo completo do que será instalado e pede confirmação final antes de iniciar.

#### Fase 4 — Instalação (8 etapas)

```
[1/8] DNS LOCAL         → Adiciona hostname da máquina e do Rancher ao /etc/hosts
[2/8] HELM              → Instala o Helm (versão mais recente)
[3/8] K3s               → Instala K3s na versão especificada (modo cluster-init)
[4/8] KUBECONFIG        → Configura kubectl com o IP real da máquina
[5/8] NAMESPACES/SECRETS→ Cria namespaces e secrets do Application Collection
[6/8] REGISTRY LOGIN    → Autentica Helm no registry OCI do Application Collection
[7/8] CERT-MANAGER      → Instala Cert-Manager via Application Collection
[8/8] RANCHER PRIME     → Instala Rancher Prime via Helm
```

#### Fase 5 — Conclusão

```
╔══════════════════════════════════════════════════════════════════╗
║              INSTALAÇÃO CONCLUÍDA COM SUCESSO!                  ║
╚══════════════════════════════════════════════════════════════════╝

  Rancher UI   : https://rancher.virtnet
  Log completo : /var/log/rancher-install-YYYYMMDD-HHMMSS.log
```

### Logs

Toda a saída é salva automaticamente em:

```
/var/log/rancher-install-YYYYMMDD-HHMMSS.log
```

### Troubleshooting

**K3s não inicia após instalação:**
```bash
systemctl status k3s
journalctl -u k3s -f
```

**Pods do Rancher em CrashLoopBackOff:**
```bash
kubectl -n cattle-system get pods
kubectl -n cattle-system logs -l app=rancher --tail=50
```

**Cert-Manager não sobe:**
```bash
kubectl -n cert-manager get pods
kubectl -n cert-manager describe pod <nome-do-pod>
```

**Secret do Application Collection inválida:**
```bash
# Recriar o secret manualmente
kubectl create secret docker-registry application-collection \
  --docker-server=dp.apps.rancher.io \
  --docker-username=SEU_USUARIO \
  --docker-password=SUA_SENHA \
  --namespace=cattle-system \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## observability-install.sh

Script interativo que instala o **SUSE Observability** em um cluster K3s existente, utilizando o **SUSE Application Collection** como registry OCI.

> **Pré-requisito:** cluster K3s com Helm configurado (execute `rancher-install.sh` primeiro).

### Pré-requisitos adicionais

| Requisito | Detalhe |
|-----------|---------|
| License Key | Licença válida do SUSE Observability |
| RAM | Mínimo 8 GB (trial); 16 GB+ para perfis nonha; 32 GB+ para HA |
| Disco | Mínimo 50 GB de storage persistente disponível |
| Portas | `8080` (UI via port-forward), `443` (ingress) |

### Como usar

```bash
chmod +x scripts/observability-install.sh
sudo bash scripts/observability-install.sh
```

### Passo a passo da execução

#### Fase 1 — Coleta de variáveis

| Variável | Exemplo | Descrição |
|----------|---------|-----------|
| Usuário AC | `usuario@suse.com` | Login do Application Collection |
| Senha AC | `********` | Sem eco no terminal |
| Versão do chart | `2.2.0` | Versão do Helm chart |
| Namespace | `suse-observability` | Namespace Kubernetes de destino |
| Base URL | `https://observability.virtnet` | URL de acesso à UI |
| License Key | `********` | Licença SUSE Observability |
| Senha admin | `********` | Senha do usuário `admin` |
| Receiver API Key | *(opcional)* | Gerada automaticamente se vazia |
| Sizing profile | `trial` | Ver tabela abaixo |
| StorageClass | *(opcional)* | Padrão do cluster se vazia |

#### Perfis de sizing disponíveis

| Perfil | Agentes | Uso |
|--------|---------|-----|
| `trial` | — | PoC / avaliação (recursos mínimos) |
| `10-nonha` | até 10 | Teste não-HA |
| `20-nonha` | até 20 | Teste não-HA |
| `50-nonha` | até 50 | Homologação não-HA |
| `100-nonha` | até 100 | Homologação não-HA |
| `150-ha` | até 150 | Produção HA |
| `250-ha` | até 250 | Produção HA |
| `500-ha` | até 500 | Produção HA |
| `4000-ha` | até 4000 | Produção HA enterprise |

#### Fase 2 — Instalação (7 etapas)

```
[1/7] KERNEL         → Ajusta fs.inotify, fs.file-max, vm.max_map_count
                       Configura ulimits e override do serviço K3s (LimitNOFILE=infinity)
                       Previne erros "too many open files"
[2/7] DNS LOCAL      → Adiciona hostname da Observability ao /etc/hosts
[3/7] NAMESPACE      → Cria namespace e secret do Application Collection
[4/7] REGISTRY LOGIN → Autentica Helm no registry OCI
[5/7] VALUES.YAML    → Gera arquivo de configuração temporário (removido ao final)
[6/7] HELM INSTALL   → Instala via oci://dp.apps.rancher.io/charts/suse-observability
[7/7] STATUS         → Exibe pods, URL de acesso e comando de port-forward
```

### Acesso após instalação

**Via hostname (se DNS/ingress configurado):**
```
https://observability.virtnet
```

**Via port-forward (sem ingress):**
```bash
kubectl port-forward service/suse-observability-suse-observability-router \
  8080:8080 --namespace suse-observability
# Acesse: http://localhost:8080
```

Credenciais: usuário `admin` + senha definida durante a instalação.

### Troubleshooting

**Erro "too many open files" em pods:**
```bash
# Verificar parâmetros aplicados
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches vm.max_map_count

# Se K3s não foi reiniciado, aplicar manualmente:
systemctl daemon-reload && systemctl restart k3s
```

**Pods em Pending (sem recursos ou storage):**
```bash
kubectl describe pods -n suse-observability | grep -A5 "Events:"
kubectl get pvc -n suse-observability
```

**Pods em CrashLoopBackOff:**
```bash
kubectl -n suse-observability logs <pod-name> --previous --tail=50
```

**Verificar license e configuração:**
```bash
kubectl get secret -n suse-observability
helm get values suse-observability -n suse-observability
```

---

## kernel-patch.sh

Script standalone que aplica configurações de kernel obrigatórias no host para evitar erros `too many open files` em clusters com **SUSE Security (NeuVector)** e/ou **SUSE Observability** instalados.

> Execute **antes** de instalar SUSE Security ou SUSE Observability. Não requer cluster Kubernetes ativo.

### Por que é necessário

NeuVector e SUSE Observability juntos criam alta demanda de inotify watchers, file descriptors e memória mapeada (Kafka, VictoriaMetrics, controladores NeuVector). Sem os ajustes abaixo, pods entram em `CrashLoopBackOff` com erros `too many open files` e `inotify limit reached`.

### Parâmetros aplicados

| Parâmetro | Valor | Motivo |
|-----------|-------|--------|
| `fs.inotify.max_user_instances` | 8192 | Watchers por usuário (NeuVector + Observability) |
| `fs.inotify.max_user_watches` | 1048576 | Total de arquivos monitorados |
| `fs.file-max` | 2097152 | Descritores globais do sistema |
| `vm.max_map_count` | 524288 | Victoria Metrics, Kafka e NeuVector |
| `LimitNOFILE` (K3s service) | infinity | Herança do limite para todos os pods |

### Como usar

```bash
chmod +x scripts/kernel-patch.sh
sudo bash scripts/kernel-patch.sh
```

### Arquivos criados

```
/etc/sysctl.d/99-suse-k8s-limits.conf
/etc/security/limits.d/99-suse-k8s-limits.conf
/etc/systemd/system/k3s.service.d/nofile-override.conf
```

---

## longhorn-install.sh

Script interativo que instala o **SUSE Storage (Longhorn)** em um cluster K3s existente, utilizando o **SUSE Application Collection** como registry de imagens e charts.

> **Pré-requisito:** cluster K3s com Helm configurado (execute `rancher-install.sh` primeiro).

### Pré-requisitos adicionais

| Requisito | Detalhe |
|-----------|---------|
| Subscrição | SUSE Storage ativa no Application Collection |
| Credenciais AC | Portal apps.rancher.io → User Profile → Tokens |
| open-iscsi | O script instala automaticamente via zypper se não encontrado |
| Storage | Disco local disponível no caminho configurado (padrão: `/var/lib/longhorn`) |

### Como usar

```bash
chmod +x scripts/longhorn-install.sh
sudo bash scripts/longhorn-install.sh
```

### Passo a passo da execução

#### Fase 1 — Coleta de variáveis

| Variável | Exemplo | Descrição |
|----------|---------|-----------|
| Usuário AC | `usuario@suse.com` | Login do Application Collection |
| Senha AC | `********` | Sem eco no terminal |
| Versão do chart | `1.8.1` | Versão do Helm chart Longhorn |
| Namespace | `longhorn-system` | Namespace de instalação |
| Release | `longhorn` | Nome do Helm release |
| Réplicas padrão | `1` | PoC usa 1; produção recomenda 3 |
| Caminho de dados | `/var/lib/longhorn` | Diretório de storage no host |
| StorageClass padrão | s/N | Define Longhorn como StorageClass padrão |

#### Fase 2 — Instalação (4 etapas)

```
[1/4] NAMESPACE    → Cria longhorn-system (idempotente)
[2/4] SECRET       → Cria imagePullSecret 'application-collection' em longhorn-system
[3/4] HELM LOGIN   → Autentica Helm no registry OCI do Application Collection
[4/4] HELM INSTALL → Instala via oci://dp.apps.rancher.io/charts/longhorn
```

### Troubleshooting

**Pods em Pending (sem storage disponível):**
```bash
kubectl get nodes.longhorn.io -n longhorn-system
kubectl describe nodes.longhorn.io -n longhorn-system
```

**Interface web (port-forward):**
```bash
kubectl port-forward service/longhorn-frontend 8080:80 -n longhorn-system
# Acesse: http://localhost:8080
```

**Verificar StorageClass:**
```bash
kubectl get storageclass
kubectl get pv,pvc -A
```

---

## private-registry-install.sh

Script interativo que instala o **SUSE Private Registry** em um cluster K3s existente, utilizando o **SUSE Customer Center (SCC)** como registry de origem.

> **Pré-requisito:** cluster K3s com Helm configurado (execute `rancher-install.sh` primeiro). Requer subscrição ativa do SUSE Private Registry.

### Pré-requisitos adicionais

| Requisito | Detalhe |
|-----------|---------|
| Subscrição | SUSE Private Registry ativa no SCC |
| Credenciais SCC | Obtidas em scc.suse.com → selecione organização → Proxies |
| Storage | Persistent Volumes disponíveis no cluster |
| DNS | Hostname do registry deve resolver para o IP do Ingress |

### Como usar

```bash
chmod +x scripts/private-registry-install.sh
sudo bash scripts/private-registry-install.sh
```

### Passo a passo da execução

#### Fase 1 — Coleta de variáveis

| Variável | Exemplo | Descrição |
|----------|---------|-----------|
| Usuário SCC (Mirroring) | `usuario@suse.com` | Credencial de espelhamento do SCC |
| Senha SCC (Mirroring) | `********` | Sem eco no terminal |
| Nome do release Helm | `suse-registry` | Nome do release Kubernetes |
| Namespace | `private-registry` | Namespace de instalação |
| Hostname do Registry | `registry.empresa.com` | FQDN de acesso ao registry |
| Storage Class | *(opcional)* | Padrão do cluster se vazio |
| TLS próprio | *(opcional)* | Caminho para cert e chave |

#### Fase 2 — Instalação (4 etapas)

```
[1/4] NAMESPACE    → Cria namespace (idempotente)
[2/4] AUTENTICAÇÃO → Login Helm no SCC + criação de imagePullSecret
[3/4] TLS          → Cria secret TLS com certificado próprio (opcional)
[4/4] HELM INSTALL → Instala via oci://registry.suse.com/private-registry/private-registry-helm
```

#### Fase 3 — Conclusão

```
╔══════════════════════════════════════════════════════════════════╗
║              INSTALAÇÃO CONCLUÍDA COM SUCESSO!                  ║
╚══════════════════════════════════════════════════════════════════╝

  Registry URL   : https://registry.empresa.com
  Usuário admin  : admin
  Senha admin    : <extraída do secret Kubernetes>
```

### Troubleshooting

**Pods em Pending (sem storage):**
```bash
kubectl get pvc -n private-registry
kubectl describe pvc -n private-registry
```

**Erro de autenticação no pull de imagens:**
```bash
kubectl get secret suse-registry -n private-registry -o yaml
```

**Verificar Ingress e IP:**
```bash
kubectl get ingress -n private-registry
```

**Obter senha admin manualmente:**
```bash
kubectl get secret --namespace private-registry suse-registry-harbor-core \
  -o jsonpath="{.data.HARBOR_ADMIN_PASSWORD}" | base64 -d; echo
```

---

## Autor

**Flávio Gussi** — [flgussi@suse.com](mailto:flgussi@suse.com)

---

## Contribuindo

Consulte [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) para entender a estrutura do projeto e como propor alterações.
