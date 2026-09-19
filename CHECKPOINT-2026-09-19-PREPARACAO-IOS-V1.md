# CHECKPOINT IMPERIUM — Preparação iOS V1

Data: 2026-09-19

## Estado validado

Base técnica validada localmente pelo usuário com `VALIDAR_RC.ps1`.

Resultado informado:
`RELEASE CANDIDATE ANDROID/WEB APROVADO.`

Base de código da etapa:
`0c15e5508991137470f21e3c3cacd044626892f6`

## Entregas consolidadas

- Gate de Release Candidate para Android e Web.
- Deep links nativos centralizados em `ImperiumAppLinks`.
- Callback de confirmação/recuperação de login centralizado.
- Callback de retorno do checkout centralizado.
- Preparação segura do Google Drive para iOS.
- Scripts para bootstrap e validação iOS no macOS.
- Documento `IOS-PREPARACAO-E-HOMOLOGACAO.md`.
- Testes de fonte atualizados para o contrato centralizado.

## Estado iOS

O repositório ainda não possui a pasta `ios/` versionada.

A próxima etapa deve ser executada em um Mac com Flutter e Xcode:
`bash scripts/preparar_ios_macos.sh SEU_BUNDLE_IDENTIFIER [GOOGLE_IOS_CLIENT_ID]`

Depois:
`bash scripts/validar_ios_macos.sh`

O script de preparação não deve ser executado no Windows.

## Próximas etapas

1. Definir o Bundle Identifier final.
2. Gerar a estrutura iOS em um Mac.
3. Configurar assinatura/Team no Xcode.
4. Validar build iOS sem assinatura.
5. Testar em iPhone físico.
6. Preparar Archive/TestFlight.
7. Homologar fluxos funcionais já existentes, sem adicionar novo escopo.
