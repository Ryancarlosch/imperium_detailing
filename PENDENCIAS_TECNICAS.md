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


## Estoque Cloud V2.2 — resolução de conflito

Status: ⬜ próximo passo.

- listar conflitos no diagnóstico/admin;
- escolher versão local ou versão da nuvem;
- preservar auditoria da decisão;
- homologar concorrência em dois aparelhos.


## Estoque Cloud após V2.2

Próximos blocos:
- reserva/consumo compartilhado por Ordem de Serviço;
- saldo consistente sob concorrência;
- alertas de estoque entre aparelhos;
- interface de conflitos pode ser acoplada ao diagnóstico/admin;
- homologação real em dois dispositivos no lote final.


## Estoque Cloud V3 — homologação posterior

- testar duas OS concorrendo pelo mesmo item em dois aparelhos;
- validar reserva, liberação e consumo;
- validar finalização offline seguida de reconexão;
- conferir bloqueio de item/lote/movimentação quando reserva falhar;
- conferir alerta de estoque baixo nos dois aparelhos;
- decidir depois se a UI exibirá badge/notificação push além do alerta sincronizado.


## Financeiro Cloud V2 — próximo pacote

- download controlado de contas/plano/pagamentos/movimentos;
- reconstrução de mapas após interrupção;
- conflitos de conta/plano/pagamento/movimento;
- impedir dupla contabilização ao baixar pagamento + movimento;
- atualizar resumo da OS sem recriar movimento financeiro;
- transferências, fornecedores, taxas de cartão e conciliações cloud;
- homologação multiaparelho de competência x caixa.


## Financeiro Cloud V3 — próximos blocos

- conciliações bancárias Cloud;
- custos fixos/metas/colaboradores de custo conforme prioridade;
- comprovantes financeiros via Storage;
- resolução de exclusão financeira com regra de auditoria;
- UI/diagnóstico de conflitos financeiros;
- recalcular/espelhar resumo de contas a receber da OS sem recriar movimentos;
- homologação multiaparelho: Pix, dinheiro, cartão, parcelado, taxa, estorno e transferência.


## Próximo foco — Precificação Cloud V1

Financeiro Cloud possui agora a base necessária para alimentar Precificação:
- plano de contas;
- contas e movimentos;
- custos fixos;
- metas;
- regras/taxas de cartão;
- fornecedores;
- conciliações.

Próximo pacote grande:
- custos mensais compartilhados;
- mão de obra/custo-hora;
- regra oficial de 220h da empresa;
- margem/meta;
- preço sugerido;
- cenários de precificação;
- integração com catálogo de serviços.


## Precificação Cloud V2 — próximo passo

- conflito concorrente de catálogo/config/preferências;
- CAS por `atualizado_em`;
- resolução local/nuvem;
- sincronização de exclusões;
- cenários personalizados de margem/meta;
- histórico de simulações;
- integração de preço sugerido com catálogo mediante confirmação do usuário;
- homologação em dois aparelhos.


## Precificação após V2

Próximo pacote recomendado:
- UI gerencial para listar conflitos e escolher Local/Nuvem;
- UI de cenários e comparação de preços;
- botão controlado para aplicar preço sugerido ao catálogo;
- alertas de margem abaixo do mínimo;
- indicador de serviço com prejuízo / margem crítica;
- homologação real em dois aparelhos no lote final.

## Depois da Precificação V3

Próximo bloco:
- Configurações e Usuários Cloud;
- preferências compartilhadas;
- permissões finais por módulo;
- segunda empresa ponta a ponta;
- depois Storage/arquivos de OS e motor unificado de sincronização.

Homologação pendente da Precificação:
- dois aparelhos alterando a mesma margem;
- dois aparelhos alterando o mesmo serviço;
- escolha Local e escolha Nuvem;
- cenário criado em um aparelho aparecendo no outro;
- aplicação de preço sugerido refletindo no catálogo e sincronização.

## Próximos blocos depois de Configurações Cloud V1

1. CRM + Orçamentos Cloud, para completar os módulos operacionais ainda locais.
2. Arquivos da OS via Storage:
   - fotos;
   - assinatura;
   - checklist/anexos.
3. Isolamento local multiempresa:
   - tenant por registro ou banco SQLite por empresa;
   - troca segura de empresa;
   - limpeza/seleção de cache por tenant.
4. Motor unificado de sincronização:
   - fila;
   - retry;
   - diagnóstico;
   - observabilidade.
5. Web e iOS.


## CRM + Orçamentos Cloud V2

- CAS por `atualizado_em`;
- detecção de alteração concorrente;
- resolução Local/Nuvem;
- propagação controlada de exclusão remota;
- diagnóstico visual de conflitos;
- relacionamento de orçamento com OS criada a partir dele;
- homologação em dois aparelhos.

Depois disso:
- Arquivos/Storage da OS;
- isolamento SQLite multiempresa;
- motor unificado de sincronização.

## CRM + Orçamentos - depois do V2

- homologar dois aparelhos editando o mesmo lead;
- homologar dois aparelhos editando o mesmo orçamento;
- testar conflito de exclusão;
- histórico visual de resoluções.

Próximo bloco: Arquivos/Storage Cloud da OS.

## Arquivos/Storage da OS - próximos passos

- V2 de conflito concorrente do checklist;
- resolução visual de conflito de assinatura;
- compactação/redimensionamento adicional antes do upload;
- indicador visual de arquivo pendente/erro nas telas da OS;
- suporte Web sem depender de caminho de arquivo local;
- anexos genéricos quando existir entidade local própria para anexos;
- homologação com dois aparelhos:
  - foto criada no A aparece no B;
  - foto de avaria aparece no B;
  - assinatura criada no A abre no B;
  - exclusão local vira soft delete remoto.


## Depois de Arquivos/Storage V2

- homologação real em dois Androids;
- testar checklist alterado simultaneamente;
- testar assinatura trocada simultaneamente;
- testar exclusão concorrente de checklist;
- UI de retry para arquivo local ausente;
- suporte Web para leitura/upload sem caminho `File`.

Próximo bloco estrutural:
- isolamento SQLite por empresa;
- impedir vazamento local ao alternar tenant;
- preparar troca segura de empresa;
- depois motor unificado de sincronização/hardening.

## Depois do isolamento SQLite multiempresa

Homologar:
- empresa A com dados atuais adota o banco legado sem perda;
- criar/usar empresa B abre banco vazio v33;
- cadastrar dados na B e voltar para A sem mistura;
- operar offline em A, trocar depois para B e retornar;
- backup de A não restaura em B;
- fotos/checklist/assinatura novos ficam no diretório do tenant.

Próximo bloco:
- motor unificado de sincronização;
- fila/retry/telemetria por módulo;
- painel de saúde do sync;
- depois Web.

## Depois do Motor Unificado V1

Homologar em rede real:
- desligar internet durante cada módulo;
- religar e confirmar retry/backoff;
- conflito de Arquivos não deve impedir Ponto;
- conflito Financeiro deve bloquear Precificação, mas não CRM;
- trocar empresa e confirmar fila separada por tenant;
- reiniciar aplicativo com módulos em erro;
- confirmar que fila/histórico sobrevivem ao restart.

Próximas evoluções:
- V2: conectividade/reachability explícita;
- compactação/limpeza do histórico de eventos;
- botão retry por módulo;
- telemetria de duração e volume;
- Web: adaptar persistência da fila para ambiente sem sqflite nativo.


## Depois da Web Foundation V1

Portabilidade Web por lotes:
1. Dashboard + navegação;
2. Clientes / Veículos / Agenda;
3. OS sem arquivos locais;
4. Estoque;
5. Financeiro / DRE / Precificação;
6. CRM / Orçamentos;
7. Arquivos/assinatura usando bytes + Storage;
8. Ponto e permissões.

Pendências técnicas:
- remover dependências diretas de `dart:io` das telas compartilhadas;
- criar widget de imagem multiplataforma;
- transformar PDF/compartilhamento para fluxo de bytes/download no browser;
- backup local tradicional permanece Android/iOS;
- testar IndexedDB no mesmo domínio/porta durante homologação.

## Após Web Comercial e Gestão V3

Prioridade seguinte:
1. OS Cloud V3 com reconciliação/CAS para OS e itens já mapeados;
2. liberar edição de OS existente no Web;
3. finalização Web transacional coordenando estoque + financeiro;
4. arquivos/checklist/assinatura Web por bytes + Storage;
5. PDF/download no navegador;
6. homologação cruzada Web ↔ Android em dois dispositivos;
7. iOS.

## Após OS Cloud V3

1. Finalização Web transacional e idempotente:
   OS + produtos/FIFO + reservas + pagamentos + financeiro + conta.
2. Cancelamento Web com compensações seguras.
3. Checklist, fotos e assinatura Web usando bytes/Storage.
4. PDFs e download no navegador.
5. Homologação cruzada Android ↔ Web em dois dispositivos.
6. Preparação iOS.
