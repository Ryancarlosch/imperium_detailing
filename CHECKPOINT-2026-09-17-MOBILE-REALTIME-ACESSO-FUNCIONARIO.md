# CHECKPOINT IMPERIUM — Permissões/Acesso do Funcionário em Realtime Seguro

Data: 2026-09-17
Branch: desenvolvimento

## Escopo concluído

- Realtime seguro para mudanças de acesso do funcionário.
- Migration de produção:
  - `20260918023902_funcionario_acesso_realtime_seguro_v1`
- Nova tabela de sinal:
  - `public.imperium_funcionario_realtime_sinais`
- A tabela de sinal não expõe:
  - permissões;
  - e-mail;
  - login;
  - PIN;
  - conteúdo das tabelas privadas de acesso.
- RLS da tabela de sinal permite SELECT somente quando:
  - `auth_user_id = auth.uid()`
- `imperium_funcionario_acessos` e
  `imperium_funcionario_dispositivos` continuam sem SELECT direto para
  `authenticated`.
- Trigger gera sinal apenas quando mudam dados relevantes de autorização:
  - permissões;
  - ativo;
  - auth_user_id;
  - permitir_novo_dispositivo;
  - e-mail;
  - login.
- Atualização comum de `ultimo_acesso_em` não gera sinal e evita loop.
- Revogação total sinaliza também o usuário anterior usando
  `OLD.auth_user_id`, permitindo que o celular revogado receba o evento final.
- Novo serviço mobile:
  - `lib/services/funcionario_acesso_realtime_service.dart`
- `UsuarioInicioPage`:
  - assina o sinal do próprio `auth.uid()`;
  - chama a RPC oficial ao receber evento;
  - atualiza permissões locais e menu da sessão;
  - encerra o acesso quando funcionário/dispositivo for revogado;
  - preserva timer de 90 segundos, resume e refresh manual como fallback;
  - enfileira nova sincronização caso outro evento chegue durante sync.
- Teste fonte:
  - `test/funcionario_acesso_realtime_source_test.dart`

## Commits principais

- `cfba4db` — versiona migration segura de Realtime do acesso.
- `1d12f02` — serviço Realtime dedicado ao acesso do funcionário.
- `f7de50a` — aplica permissões/revogação na sessão ativa.
- `e6bc1ee` — protege arquitetura e segurança com teste fonte.

## Validações

Executadas e aprovadas localmente pelo usuário:

- `flutter analyze`
- `flutter test`
- `git diff --check`

## Segurança / Supabase

- Tabela de sinal com RLS e policy específica por `auth.uid()`.
- Trigger e publicação Realtime confirmados em produção.
- Advisor de segurança executado após a DDL.
- Nenhum novo alerta ligado ao lote.
- Avisos antigos de `imperium_funcionario_acessos` e
  `imperium_funcionario_dispositivos` permanecem como dívida conhecida; este
  lote não abriu acesso direto a essas tabelas.

## Estado

Implementação concluída e protegida por testes automáticos.
Homologação física administrador ↔ celular do funcionário permanece para a
rodada de campo futura.

**CHECKPOINT IMPERIUM**
