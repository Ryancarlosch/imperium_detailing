# CHECKPOINT IMPERIUM — Conflitos operacionais na Central Cloud

Data: 2026-09-17
Branch: `desenvolvimento`
Base validada: `081f4460077222913e2c081b3e8f104f9033850f`

## Objetivo deste lote

Tornar visíveis e resolvíveis na Central Cloud os conflitos de sincronização do núcleo operacional (Clientes, Veículos e Agenda), reutilizando a implementação já existente em `OperacionalCloudV2Service` e evitando detectores duplicados.

## Entregas

- `OperacionalConflitoService` passou a atuar como fachada compatível sobre `OperacionalCloudV2Service`, mantendo uma única fonte de verdade para conflitos operacionais.
- Confirmado que `SyncMotorService` já bloqueia o módulo `operacional` quando `OperacionalCloudV2Service.prepararUpload()` encontra conflito pendente.
- Novo widget `OperacionalConflitosCard` para a Central Cloud.
- O card exibe diagnóstico e conflitos pendentes de Clientes, Veículos e Agenda.
- A resolução permite escolher entre `Este aparelho` e `Nuvem`, chamando respectivamente `resolverUsandoLocal` e `resolverUsandoNuvem` do serviço V2.
- Após resolução, o fluxo dispara nova sincronização segura.
- `ConfiguracoesCloudCentralPage` recebeu somente a importação e a inclusão do novo card, preservando os demais blocos.
- Testes fonte protegem a unificação do detector e a integração do card na Central Cloud.

## Commits principais

- `1178f10` — unifica serviço de conflitos operacionais com o V2 existente.
- `b08de9e` — protege por teste a unificação e o bloqueio real do motor.
- `74c8ba7` — adiciona card de conflitos operacionais.
- `43f8e2f` — adiciona teste fonte do card.
- `f329332` — exibe card na Central Cloud.
- `081f446` — protege por teste a integração na Central Cloud.

## Validação local informada

- `flutter test test/operacional_conflito_source_test.dart` — PASS.
- `flutter test test/operacional_conflitos_card_source_test.dart` — PASS.
- `flutter analyze` — PASS / sem issues.
- `git diff --check` — PASS / sem saída.

## Observação de fechamento

A suíte completa `flutter test` não foi executada novamente especificamente após o lote visual da Central Cloud. Antes de um fechamento amplo/release, manter a validação integral como requisito.

## Próximo passo recomendado

Executar a suíte completa e, em seguida, homologar em cenário real com duas versões concorrentes de Cliente/Veículo/Agendamento para validar o fluxo completo: detecção -> bloqueio -> exibição na Central Cloud -> escolha Local/Nuvem -> nova sincronização sem sobrescrita silenciosa.
