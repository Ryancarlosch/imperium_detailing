# Arquitetura do Projeto Imperium Manager

Ultima atualizacao: **2026-09-11**

## Baseline atual

- Aplicativo Flutter.
- Branch oficial: `desenvolvimento`.
- Banco local SQLite: `imperium_detailing.db`.
- Schema local atual: **v33**.
- Estrategia: offline-first.
- Supabase participa de autenticacao, licenca e sincronizacoes selecionadas.
- CI oficial: formatacao, `flutter analyze`, `flutter test` e `git diff --check`.

## Camadas

### `lib/config/`
Regras e configuracoes estaveis. A regra empresarial das 220 h/mes vive aqui.

### `lib/domain/`
Regras puras e compartilhadas de negocio.

Contrato consolidado:
- `ordem_servico_valor.dart`: fonte unica do valor comercial final da OS em Dart e SQLite.

### `lib/models/`
Entidades e serializacao Dart/SQLite.

### `lib/database/`
`app_database.dart` concentra abertura, schema e migrations historicas ate v33.

Diretriz:
- nao reescrever migrations antigas;
- preservar bancos instalados;
- extrair migrations futuras gradualmente quando a complexidade justificar.

### `lib/repositories/`
Persistencia e consultas de OS, Financeiro, DRE, custos, precificacao,
Dashboard, CRM, Fiscal, Estoque, Funcionarios, Ponto e Saude.

### `lib/services/`
Supabase, licenca, acesso de funcionario, sincronizacao, backup, PDF,
WhatsApp, notificacoes, placa e integracoes fiscais.

### `lib/screens/`
Interface Flutter.

## Contrato monetario da OS

Fonte: `lib/domain/ordem_servico_valor.dart`.

Regra oficial:

1. `base = max(valor_total - desconto, 0)`
2. `valor_negociado = max(base - desconto_negociacao + acrescimo_negociacao + juros_parcelamento, 0)`

Consumidores consolidados:
- model `OrdemServico`;
- finalizacao da OS;
- `PagamentoRepository`;
- `CustosRepository`;
- Dashboard por competencia;
- ticket medio;
- ranking de servicos;
- ranking de clientes;
- contas a receber;
- resumo financeiro de cliente;
- resumo financeiro de veiculo;
- DRE por competencia.

O DRE continua exibindo Receita Bruta e Deducoes separadamente. As deducoes
efetivas sao calculadas de forma que `receita_bruta - deducoes` permaneça
equivalente ao valor liquido oficial da OS.

## Financeiro

Fluxo de consistencia:

`OS -> pagamento -> movimento -> conta -> Dashboard -> DRE/relatorios`

Separar sempre:
- competencia = venda finalizada;
- caixa = recebimento/pagamento efetivo;
- saldo = saldo inicial + movimentos realizados.

## Precificacao

Regra protegida:
- empresa = 220 h/mes;
- nao multiplicar 220 pela quantidade de funcionarios.

## Sincronizacao

A operacao continua offline-first. Financeiro nao deve ser migrado
incidentalmente para nuvem antes da etapa oficial.

## Areas protegidas

Nao alterar incidentalmente:
- Supabase Auth;
- licenca;
- RLS/RPC;
- `empresa_id`;
- sincronizacao de funcionario;
- Ponto cloud/offline;
- OS Cloud;
- deep links.

## Divida arquitetural conhecida

- arquivos centrais grandes;
- migrations historicas concentradas;
- parte do SQL ainda e extensa, embora o contrato monetario esteja centralizado;
- algumas leituras operacionais disparam sync;
- retry/conflito/realtime cloud ainda precisam evoluir.

## Validacao obrigatoria

1. formatacao;
2. `flutter analyze`;
3. `flutter test`;
4. `git diff --check`;
5. APK quando o fluxo exigir dispositivo real.