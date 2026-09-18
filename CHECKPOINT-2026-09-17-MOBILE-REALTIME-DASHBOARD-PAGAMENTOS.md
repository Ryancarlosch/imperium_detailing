# CHECKPOINT IMPERIUM — Realtime Dashboard + Pagamentos Mobile

Data: 2026-09-17
Branch: desenvolvimento

## Escopo concluído

- `DashboardPage` escuta o evento pós-sync e relê silenciosamente:
  - resumo operacional;
  - faturamento;
  - indicadores financeiros;
  - saldos exibidos no dashboard.
- `PagamentosPage` escuta o evento pós-sync e relê silenciosamente:
  - contas a receber;
  - resumo geral de pagamentos.
- O detalhe da OS dentro de Pagamentos também relê:
  - resumo financeiro da OS;
  - pagamentos;
  - ajustes financeiros.
- Realtime continua sendo apenas gatilho; o SQLite permanece a fonte local/offline.
- Proteções contra recarga concorrente e contra atualização durante ação local de pagamento.
- Assinaturas Realtime canceladas no `dispose`.
- Teste fonte: `test/mobile_realtime_dashboard_pagamentos_source_test.dart`.

## Commits principais

- `6304941` — atualiza Dashboard após sync Realtime.
- `b1a18e2` — atualiza Pagamentos e detalhe da OS após sync Realtime.
- `1308296` — protege lote com teste fonte.

## Validações

Executadas e aprovadas localmente pelo usuário:

- `flutter analyze`
- `flutter test`
- `git diff --check`

## Estado

Implementação concluída e protegida por testes automáticos.
Homologação física Web ↔ Android / dois aparelhos permanece para rodada de campo futura.

**CHECKPOINT IMPERIUM**
