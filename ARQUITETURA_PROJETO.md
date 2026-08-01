# Arquitetura do Projeto Imperium Detailing

## 1. Visão geral da arquitetura

O projeto é um aplicativo Flutter para gestão de serviços automotivos. A estrutura principal está organizada em camadas claras:

- `lib/main.dart`: ponto de entrada do app.
- `lib/screens/`: telas e interface do usuário.
- `lib/repositories/`: abstração de acesso a dados e consultas SQLite.
- `lib/models/`: definições de entidades de domínio e conversão entre Dart e SQLite.
- `lib/database/app_database.dart`: implementação do banco SQLite e criação de tabelas.
- `lib/services/`: serviços de infraestrutura (notificações, PDF, WhatsApp).
- `lib/modules/`: pasta vazia no momento.

O app usa Flutter puro com widgets, `StatefulWidget` e `setState`, sem gerenciadores de estado externos como Provider/Bloc/GetX.

---

## 2. Models identificados

Todos os arquivos em `lib/models/`:

- `agendamento.dart`
- `cliente.dart`
- `configuracao.dart`
- `configuracao_estoque.dart`
- `foto_servico.dart`
- `item_estoque.dart`
- `item_orcamento.dart`
- `movimentacao_estoque.dart`
- `movimento_financeiro.dart`
- `orcamento.dart`
- `ordem_servico.dart`
- `ordem_servico_item.dart`
- `produto_ordem_servico.dart`
- `servico_catalogo.dart`
- `servico_produto.dart`
- `veiculo.dart`

Esses models representam as principais entidades do domínio: clientes, veículos, agendamentos, orçamentos, ordens de serviço, finanças, estoque, fotos, serviços e configurações.

---

## 3. Repositories identificados

Todos os arquivos em `lib/repositories/`:

- `agendamento_repository.dart`
- `cliente_repository.dart`
- `configuracao_repository.dart`
- `dashboard_repository.dart`
- `estoque_repository.dart`
- `financeiro_repository.dart`
- `foto_servico_repository.dart`
- `orcamento_repository.dart`
- `ordem_servico_checklist_repository.dart`
- `ordem_servico_foto_repository.dart`
- `ordem_servico_repository.dart`
- `produto_ordem_servico_repository.dart`
- `servico_repository.dart`
- `veiculo_repository.dart`

Padrões observados:

- cada repository usa `AppDatabase.instance.database`
- encapsula consultas SQL e mapeia resultados para models
- permite operações CRUD e consultas customizadas

---

## 4. Telas identificadas

Todos os arquivos em `lib/screens/`:

- `agenda_page.dart`
- `agendamento_detalhes_page.dart`
- `clientes_page.dart`
- `cliente_detalhes_page.dart`
- `configuracoes_page.dart`
- `dashboard_page.dart`
- `estoque_page.dart`
- `financeiro_page.dart`
- `fotos_page.dart`
- `foto_detalhes_page.dart`
- `foto_veiculo_detalhes_page.dart`
- `galeria_veiculo_page.dart`
- `item_estoque_detalhes_page.dart`
- `nova_foto_page.dart`
- `nova_movimentacao_estoque_page.dart`
- `nova_ordem_servico_page.dart`
- `novo_agendamento_page.dart`
- `novo_item_estoque_page.dart`
- `novo_movimento_page.dart`
- `novo_orcamento_page.dart`
- `novo_servico_page.dart`
- `novo_veiculo_page.dart`
- `orcamentos_page.dart`
- `orcamento_detalhes_page.dart`
- `ordem_servico_assinatura_page.dart`
- `ordem_servico_checklist_page.dart`
- `ordem_servico_fotos_page.dart`
- `ordem_servico_produtos_page.dart`
- `ordens_servico_page.dart`
- `servicos_page.dart`
- `veiculos_cliente_page.dart`
- `veiculos_page.dart`
- `veiculo_detalhes_page.dart`

`main.dart` inicia o app em `DashboardPage`.

---

## 5. Banco SQLite

Arquivo principal: `lib/database/app_database.dart`.

Características do banco:

- banco local `imperium_detailing.db`
- `PRAGMA foreign_keys = ON`
- schema versionado até `version: 12`
- `onCreate` gera todas as tabelas necessárias
- `onUpgrade` aplica migrações conforme versões anteriores

Tabelas e relações principais:

- `clientes`
- `veiculos`
- `agendamentos`
- `fotos_servico`
- `movimentos_financeiros`
- `orcamentos`
- `orcamento_itens`
- `ordens_servico`
- `ordem_servico_itens`
- `ordem_servico_checklist`
- `ordem_servico_fotos`
- `ordem_servico_produtos`
- `itens_estoque`
- `movimentacoes_estoque`
- `configuracoes_estoque`
- `servicos_catalogo`
- `servico_produtos`
- `servicos_relacionados`
- `configuracoes`

Relações importantes:

- `veiculos.cliente_id` → `clientes.id`
- `agendamentos.cliente_id`, `agendamentos.veiculo_id`
- `fotos_servico.cliente_id`, `fotos_servico.veiculo_id`
- `movimentos_financeiros.cliente_id`, `movimentos_financeiros.agendamento_id`
- `orcamentos.cliente_id`, `orcamentos.veiculo_id`
- `ordens_servico.cliente_id`, `ordens_servico.veiculo_id`, `ordens_servico.orcamento_id`, `ordens_servico.agendamento_id`
- `ordem_servico_itens.ordem_servico_id`
- `ordem_servico_checklist.ordem_servico_id`
- `ordem_servico_fotos.ordem_servico_id`
- `ordem_servico_produtos.ordem_servico_id`
- `movimentacoes_estoque.item_estoque_id`, `movimentacoes_estoque.ordem_servico_id`
- `servico_produtos.servico_id`, `servico_produtos.item_estoque_id`
- `servicos_relacionados.servico_id`, `servicos_relacionados.servico_relacionado_id`

Existem tabelas de configuração single-row: `configuracoes` e `configuracoes_estoque`.

---

## 6. Dependências no `pubspec.yaml`

Dependências de produção:

- `flutter`
- `flutter_localizations`
- `sqflite`
- `path`
- `image_picker`
- `path_provider`
- `photo_view`
- `signature`
- `pdf`
- `printing`
- `share_plus`
- `intl`
- `fl_chart`
- `url_launcher`
- `flutter_local_notifications`
- `timezone`
- `flutter_timezone`

Dependências de desenvolvimento:

- `flutter_test`
- `flutter_lints`

---

## 7. Comunicação entre módulos

Fluxo de dados e integração do app:

- `main.dart` inicializa `NotificationService` e abre `DashboardPage`.
- `screens/` consultam `repositories/` diretamente para dados.
- `repositories/` usam `AppDatabase` para executar SQL e retornar models.
- `models/` representam os dados e providenciam conversão para e de `Map<String, dynamic>`.
- `services/` cuidam da infraestrutura:
  - `NotificationService`: agenda notificações de agendamentos.
  - `OrdemServicoPdfService`: geração de PDFs de ordens/órçamentos.
  - `WhatsappService`: integração com WhatsApp.
- Navegação é feita por `Navigator.push` entre telas.
- O padrão é de comunicação imperativa: UI chama repositórios, espera resultados e atualiza estado local.
- Algumas telas usam consultas SQL diretas no `DashboardPage`, sem repository adicional.

---

## 8. Observações de arquitetura

- O projeto é organizado por camada, mas ainda não possui um padrão de injeção de dependência ou gerenciamento de estado global.
- A pasta `lib/modules/` existe, mas está vazia, indicando possível intenção de modularização futura.
- A navegação e o fluxo de dados são tratados localmente em cada tela.
- A lógica de persistência e o mapeamento de dados estão bem centralizados em `repositories/` e `app_database.dart`.
- O uso de SQLite, com tabelas e índices, é suficiente para o escopo de CRM/serviços e controle financeiro local.

---

## 9. Conclusão

O projeto é uma aplicação Flutter com arquitetura tradicional de camadas. A persistência é baseada em SQLite, com repositórios atuando como camada de dados e modelos representando entidades de negócio. A interface é construída com telas diretas e chamadas assíncronas a repositórios, sem camadas avançadas de estado.
