# CHECKPOINT IMPERIUM — Realtime CRM + Orçamentos Mobile

Data: 2026-09-17
Branch: desenvolvimento

## Escopo concluído

- Supabase Realtime habilitado para:
  - `public.imperium_orcamentos`
  - `public.imperium_orcamento_itens`
  - `public.imperium_crm_leads`
  - `public.imperium_crm_interacoes`
  - `public.imperium_crm_campanhas`
  - `public.imperium_crm_cupons`
- Migration de produção: `20260918022017_mobile_realtime_crm_orcamentos_v1`.
- `OperacionalRealtimeService` passou a observar CRM e Orçamentos por `empresa_id`.
- Atualização silenciosa pós-sync em:
  - CRM principal;
  - detalhe do lead;
  - campanhas e cupons;
  - Central de Relacionamento;
  - lista de orçamentos;
  - detalhe do orçamento.
- Realtime permanece apenas como gatilho; o SQLite continua sendo a fonte local/offline.
- Guards contra recargas concorrentes e ações locais sensíveis.
- Assinaturas Realtime canceladas no `dispose`.
- Teste fonte: `test/mobile_realtime_crm_orcamentos_source_test.dart`.

## Commits principais

- `cb17f7a` — versiona migration Realtime CRM/Orçamentos.
- `461fe1a` — observa tabelas CRM/Orçamentos no Realtime.
- `47955ef` — atualiza CRM, lead, campanhas e cupons.
- `defddbd` — atualiza Central de Relacionamento.
- `9e5a7b9` — atualiza lista de Orçamentos.
- `46a8a03` — atualiza detalhe do Orçamento.
- `22f1410` — protege lote com teste fonte.

## Validações

Executadas e aprovadas localmente pelo usuário:

- `flutter analyze`
- `flutter test`
- `git diff --check`

## Segurança / Supabase

- As seis tabelas possuem RLS habilitada.
- Advisor de segurança executado após DDL.
- Nenhum novo alerta ligado às tabelas deste lote.
- Permanecem apenas avisos antigos já conhecidos do projeto.

## Estado

Implementação concluída e protegida por testes automáticos.
Homologação física Web ↔ Android / dois aparelhos permanece para rodada de campo futura.

**CHECKPOINT IMPERIUM**
