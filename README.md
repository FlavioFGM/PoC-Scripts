# PoC-Scripts

Scripts de automação para ambientes de Prova de Conceito (PoC) com tecnologias SUSE.

---

## Conteúdo

| Script | Descrição |
|--------|-----------|
| [`scripts/rancher-install.sh`](scripts/rancher-install.sh) | Instalação interativa de K3s + Rancher Prime via Application Collection |

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
| Versão do K3s | `v1.31.5+k3s1` | Formato: `vX.Y.Z+k3sN` |
| Versão do Rancher | `2.10.3` | Formato: `X.Y.Z` |
| Versão do Cert-Manager | `v1.16.2` | Formato: `vX.Y.Z` |
| Hostname do Rancher | `rancher.virtnet` | FQDN que será usado para acessar a UI |
| Número de réplicas | `1` | Para PoC, usar `1` |
| Senha de bootstrap | `********` | Senha inicial de acesso ao Rancher |

#### Fase 2 — Verificação de compatibilidade

Antes de instalar, o script valida automaticamente a combinação de versões:

```
── Rancher vs K3s:
  ✔  Rancher 2.10.3 + K3s 1.31 → compatível (suporte: v1.29 a v1.31)

── Rancher vs Cert-Manager:
  ✔  Rancher 2.10.3 + Cert-Manager 1.16 → compatível (recomendado: v1.16.x)
```

Se detectar incompatibilidades, exibe avisos e pergunta se deseja continuar.

**Matriz de compatibilidade conhecida:**

| Rancher | K3s suportado | Cert-Manager recomendado |
|---------|---------------|--------------------------|
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

## Autor

**Flávio Gussi** — [flgussi@suse.com](mailto:flgussi@suse.com)

---

## Contribuindo

Consulte [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) para entender a estrutura do projeto e como propor alterações.
