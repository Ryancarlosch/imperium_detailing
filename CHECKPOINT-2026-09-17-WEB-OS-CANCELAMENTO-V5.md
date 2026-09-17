# CHECKPOINT IMPERIUM — Cancelamento transacional Web V5

Data: 2026-09-17
Branch: `desenvolvimento`

## Escopo concluído

Foi implementado o cancelamento transacional de Ordens de Serviço no Web para OS em status `Aberta` ou `Em andamento`.

O fluxo V5 inclui:
- RPC Postgres `imperium_os_cancelar_web_v5`;
- `SECURITY INVOKER`;
- isolamento por `empresa_id` com RLS;
- CAS por `atualizado_em` para impedir cancelamento sobre versão desatualizada;
- idempotência/auditoria do cancelamento Web;
- motivo obrigatório;
- cancelamento de cobranças pendentes da OS;
- liberação de reservas de estoque vinculadas à OS;
- atualização do agendamento vinculado quando aplicável;
- transação atômica: em caso de falha, nenhuma etapa parcial é confirmada;
- bloqueio explícito de OS `Finalizada`, que deve seguir fluxo próprio de estorno/correção para preservar FIFO e financeiro;
- serviço Flutter Web `WebOsCancelamentoV5Service`;
- botão de cancelamento integrado à lista de edição Web de OS.

## Banco / Supabase

Migration aplicada em produção e versionada no repositório:

`20260917121925_os_cloud_v5_cancelamento_web_transacional`

Validações realizadas após a migration:
- RLS ativo na tabela de auditoria;
- RPC com `SECURITY INVOKER`;
- execução permitida para `authenticated`;
- execução não permitida para `anon`;
- advisor de segurança sem novo alerta específico causado pela V5.

## Validação local confirmada pelo usuário

PASS:

```text
flutter test test/web_os_cancelamento_v5_source_test.dart test/web_os_cancelamento_v5_ui_source_test.dart
```

PASS:

```text
flutter analyze
```

PASS / sem saída:

```text
git diff --check
```

PASS:

```text
flutter test
```

## Estado do lote

✅ Implementação concluída
✅ Migration aplicada
✅ Testes específicos aprovados
✅ Analyzer aprovado
✅ Diff check limpo
✅ Suíte completa aprovada

## Observação de segurança funcional

OS finalizada não é convertida diretamente para `Cancelada` por este fluxo. Um eventual cancelamento pós-finalização exige um fluxo próprio de estorno que recomponha estoque/FIFO, financeiro e demais efeitos já realizados de forma auditável e transacional.

**CHECKPOINT IMPERIUM concluído.**
