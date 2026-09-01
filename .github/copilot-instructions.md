# Imperium Manager — instruções do repositório para GitHub Copilot

## Fonte de verdade
- Trabalhe na branch `desenvolvimento`.
- Leia `ROADMAP-IMPERIUM-MESTRE.md` e `PENDENCIAS_TECNICAS.md` antes de alterar módulos relevantes.
- Fontes ativas: `lib/`, `test/`, `supabase/` e `scripts/`.
- Ignore backups, patches históricos, `*.BLOQUEADO` e logs, salvo pedido explícito.
- Procure implementações existentes antes de criar services, repositories, telas ou tabelas novas.

## Regras de negócio protegidas
- A empresa usa aproximadamente **220 h/mês**. Não multiplicar 220 pela quantidade de funcionários.
- Faturamento por competência é diferente de caixa/saldo.
- OS finalizada gera faturamento comercial; saldo só muda quando dinheiro é recebido/pago.
- Transferências não são receita/despesa operacional da DRE.
- Conciliação não deve virar receita/despesa da DRE.
- Retry/sincronização nunca pode duplicar movimentos financeiros.
- Responsável da OS indica quem executou; salário/valor-hora são internos.
- Multiempresa é obrigatória: preservar `empresa_id`, RLS, Auth e isolamento.
- Nunca expor `service_role`, token privado ou secret de Edge Function no Flutter/APK.

## Estado cloud protegido
- Ponto já possui implementação híbrida/offline; não reescrever sem tarefa específica.
- Clientes, veículos e agenda já possuem sincronização operacional.
- OS Cloud está em **Upload-Only V1**. Não implementar download de OS sem tarefa explícita e homologação do upload.
- Financeiro continua local por enquanto.
- Fotos/assinaturas ficam locais até a etapa oficial de Storage.
- `consultar-placa` exige JWT e `FALCON_DATAHUB_TOKEN` somente no Supabase.

## Áreas sensíveis
Não alterar incidentalmente:
- `lib/services/licenca_service.dart`
- `lib/services/funcionario_acesso_service.dart`
- `lib/services/supabase_bootstrap.dart`
- `lib/services/ponto_nuvem_service.dart`
- `lib/services/ponto_offline_sync_service.dart`
- `lib/services/operacional_sync_service.dart`
- RLS, RPCs, `empresa_id`, `auth_user_id`, `dispositivo_id`, deep links e primeiro acesso.

## Forma de trabalhar
- Alterações pequenas e focadas no escopo.
- Preservar bancos SQLite já instalados; nunca apagar dados para corrigir migração.
- Em sincronização, tratar idempotência, offline/retry, conflitos e isolamento.
- Em financeiro, rastrear `OS → pagamento → movimento → conta → dashboard → relatórios`.
- Não aplicar refactors em massa fora do escopo.
- Atualizar roadmap quando o status real mudar.

## Critério obrigatório
Antes de concluir:
1. `dart format --output=none --set-exit-if-changed lib test`
2. `flutter analyze`
3. `flutter test`
4. `git diff --check`

Relatar arquivos alterados, validações e pendências de homologação.