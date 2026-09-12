# Pendencias tecnicas

Ultima atualizacao: **2026-09-11**

## Sprint 1A - consolidacao arquitetural

### Parte A - contrato monetario Dart
Status: ✅

- `lib/domain/ordem_servico_valor.dart`;
- model;
- pagamentos;
- custos;
- finalizacao da OS;
- sem migration;
- schema v33 preservado.

### Parte B - contrato monetario SQL
Status: ✅ implementado, aguardando validacao local deste patch

- status financeiro de pagamentos;
- Dashboard por competencia;
- ticket medio;
- ranking cliente/servico;
- contas a receber;
- resumos cliente/veiculo;
- DRE competencia;
- teste de equivalencia Dart x SQLite.

## Proxima etapa

Sprint 1B - teste contratual ponta a ponta: ✅ validado

`OS -> pagamento -> movimento -> conta -> Dashboard -> DRE/relatorios`

Objetivo:
- provar por teste de integracao que uma mesma venda gera os mesmos valores
  em todos os pontos criticos;
- incluir desconto, pagamento parcial, parcelamento, taxa de maquininha,
  estorno e saldo de conta.

## Homologacoes de campo ainda necessarias

- Financeiro completo no APK;
- Ponto em dois aparelhos;
- Clientes/Veiculos/Agenda multiaparelho;
- OS Cloud V2.1;
- consulta de placa real;
- Fiscal posteriormente.

## Divida acompanhada

- arquivos centrais grandes;
- migrations historicas concentradas;
- sync acoplado a algumas leituras;
- motor generico de retry/conflito/realtime incompleto.

## Regras

- nao apagar dados para corrigir migration;
- nao esconder warnings;
- nao migrar Financeiro para nuvem incidentalmente;
- proteger Auth/Licenca/RLS/Ponto/sync de funcionario;
- atualizar roadmap a cada etapa relevante.
## Multiplataforma — futuro oficial

Status: ⬜ planejado após consolidação cloud/multi-dispositivo.

Objetivo:
- mesmo login Supabase Auth no Android, Web e iOS;
- mesma empresa e mesmas permissões;
- mesma base remota compartilhada;
- UI responsiva no Web;
- integrações nativas isoladas no iOS/Android;
- testes de paridade e multiempresa entre plataformas.

Pré-requisitos:
- concluir homologações atuais;
- estabilizar sync cloud por módulo;
- conflitos/versionamento/retry/idempotência;
- Storage para arquivos compartilhados;
- contratos remotos sem dependência de IDs SQLite locais.


## Estoque Cloud V1

Status: 🟡 desenvolvido para upload-only; homologação posterior em lote.

- Supabase: itens, lotes e movimentações.
- RLS por `empresa_id` e permissão `estoque`.
- Movimentações remotas append-only.
- App: upload integrado ao sync operacional.
- Sem download de estoque nesta V1.
- SQLite permanece v33.


## Estoque Cloud V2.1 — conflitos

Status: ⬜ próximo refinamento.

- atualizar itens/lotes já mapeados sem last-write-wins silencioso;
- detectar alteração local + alteração remota concorrente;
- registrar conflito para resolução controlada;
- propagar soft delete remotamente para aparelhos secundários;
- validar em dois dispositivos após o lote de desenvolvimento.
