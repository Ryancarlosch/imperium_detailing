# CHECKPOINT IMPERIUM — Promoção Cloud Controlada V1

Data: 2026-09-18
Branch: desenvolvimento
HEAD validado localmente pelo usuário: 8d759e411b55f85cfc575de43a68af77f4a3df9b

## Escopo concluído

- Promoção Cloud controlada por módulo.
- Ordem de promoção travada e reversível:
  1. Operacional — Clientes, Veículos e Agenda
  2. Ordens de Serviço
  3. Arquivos OS
  4. CRM e Orçamentos
  5. Estoque
  6. Financeiro
  7. Precificação
  8. Configurações
  9. Ponto
- Gate V2 obrigatório antes da promoção.
- Rollback somente do último módulo promovido.
- SQLite permanece como cache/offline no mobile.
- Cloud passa a representar o estado compartilhado de promoção por empresa.
- Nenhuma promoção silenciosa: ação explícita na tela de auditoria.
- Operacional V2 reconcilia conflitos antes do upload e novamente depois do download.
- Nova tabela Cloud:
  - `public.imperium_migracao_modulos`
- RLS habilitado.
- `anon` sem SELECT.
- `authenticated` sem DELETE.
- INSERT/UPDATE restritos a administrador da empresa.
- Migration aplicada:
  - `20260918130702_migracao_final_promocao_modulos_v1`
- Advisor de segurança sem novo alerta relacionado ao lote.

## Validação

Executado e aprovado localmente pelo usuário:
- `VALIDAR_APP.ps1`
- `flutter analyze`
- `flutter test`
- `git diff --check`

## Estado

Promoção Cloud Controlada V1 concluída e protegida.

Próximo bloco:
- fechamento pré-iOS;
- segurança e estabilidade;
- homologação Android + Web;
- Release Candidate congelado antes da adaptação iOS.

**CHECKPOINT IMPERIUM**
