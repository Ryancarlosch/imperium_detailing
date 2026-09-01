# Pendências técnicas

Última atualização: **2026-09-01**

## Baseline de qualidade
- `dart format --output=none --set-exit-if-changed lib test`: ✅
- `flutter analyze`: ✅ sem issues
- `flutter test`: ✅ suíte completa
- `git diff --check`: ✅
- GitHub Actions: 🟡 conferir após o push desta Sprint 0

## Sprint 0
- warning `_data` removido;
- `.imperium_backup_*` removidos da árvore rastreada, mantendo histórico Git;
- logs antigos de análise/teste fora do índice;
- contexto persistente do Copilot criado;
- fonte `consultar-placa` alinhada à V5 ativa, preservando marcador de contrato dos testes;
- roadmap atualizado para o baseline de 2026-09-01.

## Pendências reais
1. homologar consulta de placa no APK e logs do Falcon;
2. homologar OS Cloud Upload-Only V1 com OS real, retry/idempotência e isolamento;
3. homologar Financeiro local completo no APK;
4. fechar Ponto em dois aparelhos;
5. validar Clientes/Veículos/Agenda multiaparelho e conflitos;
6. seguir ordem oficial de migração cloud.

## Regras
- Não aumentar warnings.
- Não esconder warnings no `analysis_options.yaml`.
- Não migrar Financeiro para nuvem incidentalmente.
- Multiempresa, licença, Auth, RLS e sincronização de funcionário são áreas protegidas.