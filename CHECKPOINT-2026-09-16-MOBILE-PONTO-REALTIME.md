# CHECKPOINT IMPERIUM — Mobile / Ponto Realtime

Data local: 2026-09-16 (America/Sao_Paulo)
Branch: desenvolvimento

## Escopo concluído

- Retomada segura do Realtime do Meu Ponto ao voltar do segundo plano.
- Reassinatura do canal Realtime após `AppLifecycleState.resumed`.
- Recarregamento do estado do ponto ao retomar o app.
- Realtime ampliado para alterações de `ponto_jornada` e `ponto_config`, além de `ponto_registros`.
- Migração versionada para publicar `ponto_jornada` e `ponto_config` em `supabase_realtime`.
- RLS existente preservada; nenhuma regra de batida, cálculo de horas, estoque, financeiro ou OS foi alterada neste lote.

## Commits principais

- `c8ae318` — retomada do Realtime do Ponto no ciclo de vida do app.
- `dc6e0a9` — teste da retomada do Realtime.
- `aff4d0f` — checkpoint intermediário do lote mobile.
- `8c87978` — migração Realtime de jornada/configuração.
- `cda1e5a` — serviço mobile passa a ouvir jornada/configuração.
- `c64fb3f` — teste de Realtime de jornada/configuração.
- `a74afc2` — Dart format automático.

## Validações realizadas

Validação local informada pelo usuário:

- `flutter test test/ponto_realtime_service_test.dart` — PASSOU.
- `flutter analyze` — PASSOU.

Validação no Supabase real:

- `ponto_registros` publicado no Realtime.
- `ponto_jornada` publicado no Realtime.
- `ponto_config` publicado no Realtime.
- Políticas RLS de leitura de jornada/configuração permanecem limitadas aos usuários autenticados com acesso à mesma empresa.

## Observações

- O alerta Vercel de build-rate-limit é externo ao lote mobile e não foi tratado como erro deste código.
- Advisors do Supabase apontaram avisos preexistentes em outras estruturas/funções do projeto; este lote não criou novas permissões de acesso.
- Homologação prática em dois aparelhos continua sendo recomendada para validar atualização em tempo real no uso real.

## Status

✅ Ponto Realtime Mobile — retomada + jornada/configuração implementados e validados localmente.
