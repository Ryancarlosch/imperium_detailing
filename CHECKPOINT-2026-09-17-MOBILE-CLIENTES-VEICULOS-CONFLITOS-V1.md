# CHECKPOINT IMPERIUM — Mobile Clientes/Veículos: detector de conflitos V1

Data: 2026-09-17
Branch: `desenvolvimento`

## Objetivo
Criar a base segura para detectar conflitos de sincronização em Clientes e Veículos quando o mesmo registro for alterado localmente e na nuvem em paralelo, sem ainda bloquear sincronização nem substituir dados automaticamente.

## Implementação
- Serviço novo: `lib/services/operacional_conflito_service.dart`.
- Detecta conflitos para `cliente` e `veiculo` usando:
  - `local_hash` da base conhecida;
  - hash local atual;
  - `remoto_atualizado_em` da base conhecida;
  - `atualizado_em` remoto atual;
  - `excluido_em` remoto.
- Motivos protegidos nesta etapa:
  - `registro_remoto_ausente`;
  - `alteracao_concorrente`;
  - `exclusao_remota_e_alteracao_local`.
- Estrutura local de diagnóstico: `imperium_sync_operacional_conflitos`.
- Métodos de diagnóstico/listagem preparados sem acionar resolução automática.

## Commits do lote
- `82957a6` — `feat(mobile): adiciona detector de conflitos operacional`
- `afcb660` — `test(mobile): protege detector de conflitos operacional`
- `4421ec2` — `style(mobile): corrige initializing formal no conflito operacional`

## Validação local informada
- `flutter test test/operacional_conflito_source_test.dart` — passou.
- `flutter analyze` — passou após a correção de estilo.
- `flutter test` — executado sem bloqueio antes da checagem final.
- `git diff --check` — sem saída.

## Preservado nesta etapa
- O detector ainda não está ligado ao fluxo de sincronização para bloquear uploads/downloads.
- Nenhum dado de Cliente/Veículo é substituído automaticamente por este novo serviço.
- Não há resolução automática entre versão local e versão da nuvem.

## Próxima etapa
Integrar o detector ao fluxo operacional com bloqueio seguro quando houver conflito pendente e depois expor resolução controlada pela Central Cloud.

**CHECKPOINT IMPERIUM**
