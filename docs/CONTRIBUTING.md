# Guia de Contribuição — PoC-Scripts

Este documento descreve a estrutura do projeto, decisões de design e como propor alterações. Serve também como referência para agentes de IA (Claude ou similares) que atuem neste repositório em sessões futuras.

---

## Estrutura do repositório

```
PoC-Scripts/
├── README.md                       # Documentação principal e guia de uso
├── docs/
│   ├── CONTRIBUTING.md             # Este arquivo — guia de contribuição e contexto de IA
│   └── MEMORY.md                   # Contexto de projeto para sessões de Claude
├── scripts/
│   ├── rancher-install.sh          # Script de instalação K3s + Rancher Prime
│   ├── observability-install.sh    # Script de instalação SUSE Observability
│   └── private-registry-install.sh # Script de instalação SUSE Private Registry
```

---

## Convenções do projeto

### Scripts bash

- Todos os scripts usam `#!/bin/bash` com `set -eo pipefail`
- Saída colorida com funções `log()`, `info()`, `warn()`, `error()`, `section()`
- Senhas e segredos são sempre lidos com `read -rs` (sem eco no terminal)
- Toda saída é duplicada para um log em `/var/log/` via `exec > >(tee -a "$LOG_FILE") 2>&1`
- Variáveis de versão com prefixo `v` (ex: `v1.16.2`) têm o prefixo removido antes de passar ao Helm com `${VAR#v}`
- Prompts interativos usam valores padrão exibidos entre colchetes: `[valor]`

### Documentação

- `README.md` é o ponto de entrada — deve sempre refletir o comportamento atual dos scripts
- Atualizar a tabela de compatibilidade sempre que a matriz Rancher/K3s/Cert-Manager mudar
- Manter o `docs/MEMORY.md` atualizado com decisões e mudanças relevantes

---

## Como propor alterações

1. Faça fork ou clone do repositório
2. Crie um branch descritivo: `feat/novo-script-rke2` ou `fix/compatibilidade-rancher-2.11`
3. Teste o script manualmente em uma VM limpa antes de abrir PR
4. Atualize o `README.md` e o `docs/MEMORY.md` se a mudança for relevante
5. Abra o Pull Request com descrição clara do que mudou e por quê

---

## Variáveis e defaults atuais

### rancher-install.sh

| Variável | Default atual | Notas |
|----------|--------------|-------|
| `K3S_VERSION` | `v1.33.7+k3s3` | Atualizar conforme suporte do Rancher |
| `RANCHER_VERSION` | `2.14.1` | Verificar https://github.com/rancher/rancher/releases |
| `CERTMGR_VERSION` | `v1.17.2` | Verificar https://github.com/cert-manager/cert-manager/releases |
| `AC_REGISTRY` | `dp.apps.rancher.io` | Registry fixo do Application Collection — não alterar |
| `RANCHER_HOSTNAME` | `rancher.virtnet` | Ambiente de PoC — ajustar para DNS real em produção |
| `RANCHER_REPLICAS` | `1` | PoC usa 1; produção recomenda 3 |

### private-registry-install.sh

| Variável | Default atual | Notas |
|----------|--------------|-------|
| `SCC_REGISTRY` | `registry.suse.com` | Registry SCC — não alterar |
| `CHART_OCI` | `oci://registry.suse.com/private-registry/private-registry-helm` | Chart OCI — não alterar |
| `RELEASE_NAME` | `suse-registry` | Nome do Helm release |
| `PR_NAMESPACE` | `private-registry` | Namespace Kubernetes |
| `PR_HOSTNAME` | `registry.<hostname>` | FQDN de acesso ao registry |

### observability-install.sh

| Variável | Default atual | Notas |
|----------|--------------|-------|
| `OBS_VERSION` | `2.2.0` | Versão do Helm chart do SUSE Observability |
| `OBS_NS` | `suse-observability` | Namespace Kubernetes |
| `OBS_BASE_URL` | `https://observability.virtnet` | URL de acesso à UI |
| `SIZING_PROFILE` | `trial` | Ver tabela de sizing no README |
| `AC_REGISTRY` | `dp.apps.rancher.io` | Registry fixo — não alterar |

---

## Parâmetros de kernel (observability-install.sh)

O script aplica automaticamente os seguintes ajustes no host — necessários para o SUSE Observability funcionar sem erros `too many open files`:

| Parâmetro | Valor | Razão |
|-----------|-------|-------|
| `fs.inotify.max_user_instances` | 8192 | Watchers de filesystem por usuário |
| `fs.inotify.max_user_watches` | 524288 | Total de arquivos monitorados |
| `fs.file-max` | 1048576 | Descritores de arquivo globais |
| `vm.max_map_count` | 262144 | Requerido por Victoria Metrics e Kafka |
| `LimitNOFILE` (K3s service) | infinity | Herança para todos os pods |

Arquivos criados:
- `/etc/sysctl.d/99-suse-observability.conf`
- `/etc/security/limits.d/99-suse-observability.conf`
- `/etc/systemd/system/k3s.service.d/nofile-override.conf`

---

## Roadmap / próximas melhorias

- [ ] Script de desinstalação / limpeza completa (`uninstall.sh`)
- [ ] Suporte a instalação multi-node (agentes K3s adicionais)
- [ ] Script para RKE2 + Rancher Prime
- [ ] Integração com Longhorn para storage persistente
- [ ] Validação de pré-requisitos de hardware (RAM, disco, CPU) antes de instalar
- [ ] Script de instalação do SUSE Observability Agent (coleta de métricas nos nós)
- [ ] Configuração de replicação entre instâncias do SUSE Private Registry
