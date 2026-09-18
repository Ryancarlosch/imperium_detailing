# CHECKPOINT IMPERIUM — Release Candidate Android/Web pré-iOS

Data: 2026-09-18
Branch: desenvolvimento
HEAD validado localmente pelo usuário: 207a69a93960969de47405f5f603d821852c82a6

## Escopo concluído

- Android e Web congelados como base técnica antes da adaptação iOS.
- Gate de Release Candidate:
  - `VALIDAR_RC.ps1`
  - `flutter pub get`
  - validação de formatação Dart
  - `flutter analyze`
  - `flutter test`
  - `flutter build apk --release`
  - `flutter build web --target lib/main_web_bootstrap.dart --release`
  - `git diff --check`
- Deep links nativos centralizados em:
  - `lib/config/imperium_app_links.dart`
- Contratos preservados:
  - `imperiumdetailing://login-callback/`
  - `imperiumdetailing://payment-return/`
- Auditoria de segurança pré-RC:
  - nenhuma chave `service_role` encontrada no código versionado;
  - tabelas RLS sem policies verificadas como backend-only;
  - `anon` e `authenticated` sem CRUD direto nessas tabelas;
  - RPCs SECURITY DEFINER antigas revisadas sem revogação cega.
- Preparação iOS documentada:
  - `IOS-PREPARACAO-E-HOMOLOGACAO.md`
- Scripts Mac preparados:
  - `scripts/preparar_ios_macos.sh`
  - `scripts/validar_ios_macos.sh`
- O repositório ainda não possui a pasta `ios/`.
  Ela deve ser gerada pelo Flutter em um Mac antes da compilação iOS.

## Validação

Executado e aprovado localmente pelo usuário:
- `VALIDAR_RC.ps1`
- Flutter analyze
- Flutter test
- APK release
- Web release
- Git diff check

## Estado

Release Candidate Android/Web pré-iOS aprovado.

Próximo bloco:
- gerar e versionar plataforma iOS em Mac;
- configurar Info.plist;
- configurar Bundle Identifier e Signing;
- validar build iOS sem assinatura;
- testar em iPhone físico;
- preparar TestFlight.

**CHECKPOINT IMPERIUM**
