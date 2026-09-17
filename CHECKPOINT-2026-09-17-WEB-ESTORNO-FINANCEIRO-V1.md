# CHECKPOINT IMPERIUM — Estorno Financeiro Web V1

Data: 2026-09-17
Branch: `desenvolvimento`
Base validada: `3ea3c0ed262dd33ed2a83ce288dc8bea41fe694d`

## Escopo concluído

- Migration Supabase `20260917124628_financeiro_estorno_web_v1` aplicada e versionada.
- RPC `imperium_financeiro_estornar_pagamento_web_v1` com `SECURITY INVOKER`, execução para `authenticated` e sem execução para `anon`.
- Dois modos explícitos:
  - `correcao`: cancela recebimento/taxa lançados por engano sem criar saída real;
  - `devolucao`: preserva entrada histórica e cria saída real de devolução ao cliente.
- CAS pelo `atualizado_em` do pagamento.
- Idempotência por chave estável.
- Pagamento passa a `Estornado`.
- Ajuste automático de taxa/repasse vinculado ao pagamento é cancelado.
- Parcela é reaberta quando aplicável.
- Resumo financeiro da OS é recalculado na mesma transação.
- Guard no banco impede ajuste de `Taxa de maquininha` ativo quando o pagamento já está estornado, evitando reativação indevida pelo sync móvel.
- Serviço Web `WebFinanceiroEstornoService` integrado.
- Card `WebFinanceiroPagamentosCard` integrado ao Fluxo de Caixa Web.
- Ação de estorno disponível somente para pagamentos com status `Pago`.

## Validação local confirmada pelo usuário

- `flutter analyze`: PASS.
- `flutter test`: PASS (suíte completa).
- `git diff --check`: PASS / sem saída.

## Segurança verificada no Supabase

- RPC nova usa `SECURITY INVOKER`.
- `authenticated` possui EXECUTE.
- `anon` não possui EXECUTE.
- Trigger `trg_imperium_os_ajuste_taxa_estorno_guard` ativo.
- Advisor não apontou alerta novo específico deste lote; permanecem avisos antigos do projeto já conhecidos.

## Pendências fora deste lote

- Homologação manual real do estorno com dados de teste no Web + sincronização no Android.
- Homologação multiempresa/multi-dispositivo ampla continua como gate de produção.

## Resultado

Implementação e validação automatizada do Estorno Financeiro Web V1 concluídas.
