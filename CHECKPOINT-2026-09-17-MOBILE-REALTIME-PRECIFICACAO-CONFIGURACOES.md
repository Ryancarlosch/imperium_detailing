# CHECKPOINT IMPERIUM — Realtime Precificação + Configurações Mobile

Data: 2026-09-17
Branch: desenvolvimento

## Escopo concluído

- Supabase Realtime habilitado para:
  - `public.imperium_precificacao_colaboradores_custo`
  - `public.imperium_precificacao_config`
  - `public.imperium_precificacao_servico_produtos`
  - `public.imperium_precificacao_servicos`
  - `public.imperium_precificacao_servicos_catalogo`
  - `public.imperium_precificacao_simulacoes`
  - `public.imperium_precificacao_snapshots`
  - `public.imperium_configuracoes_empresa`
- Migration de produção: `20260918022904_mobile_realtime_precificacao_configuracoes_v1`.
- `OperacionalRealtimeService` passou a observar Precificação e Configurações por `empresa_id`.
- Atualização silenciosa pós-sync em:
  - Precificação de serviços;
  - Central Cloud de Precificação;
  - resumo de Custos;
  - Configurações da empresa.
- A Precificação não sobrescreve margens/média que estejam sendo editadas e ainda não tenham sido salvas.
- Configurações não sobrescrevem nenhum campo local alterado e ainda não salvo.
- Guards contra recarga durante salvamento, backup, assinatura da empresa e sincronização.
- Assinaturas Realtime canceladas no `dispose`.
- Teste fonte: `test/mobile_realtime_precificacao_configuracoes_source_test.dart`.

## Commits principais

- `29ffd9e` — versiona migration Realtime de Precificação e Configurações.
- `67d2767` — observa tabelas no serviço Realtime.
- `d335311` — atualiza Precificação sem perder edições locais.
- `810c659` — atualiza Central de Precificação.
- `ccda8d1` — atualiza resumo de Custos.
- `d3379d2` — atualiza Configurações sem sobrescrever campos não salvos.
- `b50ce95` — protege lote com teste fonte.

## Validações

Executadas e aprovadas localmente pelo usuário:

- `flutter analyze`
- `flutter test`
- `git diff --check`

## Segurança / Supabase

- As oito tabelas possuem RLS habilitada.
- Advisor de segurança executado após DDL.
- Nenhum novo alerta ligado às tabelas deste lote.
- Permanecem apenas avisos antigos já conhecidos do projeto.

## Estado

Implementação concluída e protegida por testes automáticos.
Homologação física Web ↔ Android / dois aparelhos permanece para rodada de campo futura.

**CHECKPOINT IMPERIUM**
