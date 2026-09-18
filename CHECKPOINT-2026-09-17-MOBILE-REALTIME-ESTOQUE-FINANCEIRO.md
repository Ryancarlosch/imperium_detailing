# CHECKPOINT IMPERIUM — Realtime Estoque + Financeiro Mobile

Data: 2026-09-17
Branch: desenvolvimento

## Escopo concluído

- Supabase Realtime habilitado para:
  - `public.imperium_estoque_itens`
  - `public.imperium_estoque_lotes`
  - `public.imperium_estoque_movimentacoes`
  - `public.imperium_financeiro_contas`
  - `public.imperium_financeiro_movimentos`
- Migration de produção: `20260918020141_mobile_realtime_estoque_financeiro_v1`.
- `OperacionalRealtimeService` passou a observar Estoque e Financeiro por `empresa_id`.
- `EstoquePage` relê silenciosamente itens, movimentações e configuração local após o sync.
- `FinanceiroPage` relê silenciosamente KPIs e saldos das contas após o sync.
- Realtime continua sendo apenas gatilho; SQLite permanece fonte local e o motor existente continua responsável por sync, retry/backoff, conflitos e offline-first.
- Proteção contra recargas concorrentes.
- Assinaturas canceladas no `dispose`.
- Teste fonte: `test/mobile_realtime_estoque_financeiro_source_test.dart`.

## Commits principais

- `905dd41` — versiona migration Realtime de Estoque e Financeiro.
- `f10a958` — observa tabelas de Estoque e Financeiro no Realtime.
- `ca4ccc9` — atualiza Estoque após sync Realtime.
- `88a50fd` — atualiza Financeiro após sync Realtime.
- `a256492` — protege lote com teste fonte.

## Validações

Executadas e aprovadas localmente pelo usuário:

- `flutter analyze`
- `flutter test`
- `git diff --check`

## Segurança / Supabase

- Tabelas envolvidas com RLS habilitada.
- Advisor de segurança executado após DDL.
- Nenhum novo alerta ligado às tabelas deste lote.
- Permanecem apenas avisos antigos já conhecidos do projeto.

## Estado

Implementação concluída e protegida por testes automáticos.
Homologação física Web ↔ Android / dois aparelhos permanece para rodada de campo futura.

**CHECKPOINT IMPERIUM**
