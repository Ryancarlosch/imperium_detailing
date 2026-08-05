import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const int schemaVersion = 20;

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _abrirBanco();
    return _database!;
  }

  Future<Database> _abrirBanco() async {
    final pastaBanco = await getDatabasesPath();

    final caminho = join(pastaBanco, 'imperium_detailing.db');

    return openDatabase(
      caminho,
      version: schemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await _criarTabelas(database);
      },
      onUpgrade: (database, versaoAntiga, versaoNova) async {
        if (versaoAntiga < 2) {
          await _criarTabelaVeiculos(database);
        }

        if (versaoAntiga < 3) {
          await _criarTabelaAgendamentos(database);
        }

        if (versaoAntiga < 4) {
          await _criarTabelaFotos(database);
        }

        if (versaoAntiga < 5) {
          await _criarTabelaMovimentosFinanceiros(database);
        }

        if (versaoAntiga < 6) {
          await _criarTabelaOrcamentos(database);
          await _criarTabelaItensOrcamento(database);
          await _migrarOrcamentosAntigos(database);
        }

        if (versaoAntiga < 7) {
          await _criarTabelaOrdensServico(database);
          await _criarTabelaItensOrdemServico(database);
          await _criarTabelaChecklistOrdemServico(database);
          await _criarTabelaFotosOrdemServico(database);
          await _criarTabelaProdutosOrdemServico(database);
        }

        if (versaoAntiga < 8) {
          await _atualizarChecklistParaVersao8(database);
        }

        if (versaoAntiga < 9) {
          await _criarTabelaConfiguracoes(database);
          await _inserirConfiguracaoPadrao(database);
        }

        if (versaoAntiga < 10) {
          await _criarTabelaItensEstoque(database);
          await _criarTabelaMovimentacoesEstoque(database);
          await _criarTabelaConfiguracoesEstoque(database);
          await _inserirConfiguracaoEstoquePadrao(database);
        }

        if (versaoAntiga < 11) {
          await _atualizarConfiguracoesEstoqueParaVersao11(database);
        }

        if (versaoAntiga < 12) {
          await _criarTabelaServicosCatalogo(database);
          await _criarTabelaServicoProdutos(database);
          await _criarTabelaServicosRelacionados(database);
        }

        if (versaoAntiga < 13) {
          await _atualizarConfiguracoesParaVersao13(database);
        }

        if (versaoAntiga < 14) {
          await _atualizarConfiguracoesParaVersao14(database);
        }

        if (versaoAntiga < 15) {
          await _atualizarItensEstoqueParaVersao15(database);
        }

        if (versaoAntiga < 16) {
          await _atualizarProdutosOrdemServicoParaVersao16(database);
        }

        if (versaoAntiga < 17) {
          await _atualizarParaVersao17(database);
        }

        if (versaoAntiga < 18) {
          await _atualizarParaVersao18(database);
        }

        if (versaoAntiga < 19) {
          await _atualizarParaVersao19(database);
        }

        if (versaoAntiga < 20) {
          await _atualizarParaVersao20(database);
        }
      },
    );
  }

  Future<void> _criarTabelas(Database database) async {
    await _criarTabelaClientes(database);
    await _criarTabelaVeiculos(database);
    await _criarTabelaAgendamentos(database);
    await _criarTabelaFotos(database);
    await _criarTabelaMovimentosFinanceiros(database);
    await _criarTabelaOrcamentos(database);
    await _criarTabelaItensOrcamento(database);
    await _criarTabelaOrdensServico(database);
    await _criarTabelaItensOrdemServico(database);
    await _criarTabelaChecklistOrdemServico(database);
    await _criarTabelaFotosOrdemServico(database);
    await _criarTabelaProdutosOrdemServico(database);
    await _criarTabelaConfiguracoes(database);
    await _inserirConfiguracaoPadrao(database);
    await _criarTabelaItensEstoque(database);
    await _criarTabelaEstoqueLotes(database);
    await _criarTabelaMovimentacoesEstoque(database);
    await _criarTabelaConfiguracoesEstoque(database);
    await _inserirConfiguracaoEstoquePadrao(database);
    await _criarTabelaServicosCatalogo(database);
    await _criarTabelaServicoProdutos(database);
    await _criarTabelaServicosRelacionados(database);
    await _criarTabelaCategoriasServico(database);
    await _criarTabelaOrdemServicoProdutoLotes(database);
  }

  Future<void> _criarTabelaClientes(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS clientes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          telefone TEXT,
          email TEXT,
          endereco TEXT,
          observacoes TEXT,
          ativo INTEGER NOT NULL DEFAULT 1,
          arquivado_em TEXT
        )
      ''');

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'clientes',
      coluna: 'ativo',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'clientes',
      coluna: 'arquivado_em',
      definicao: 'TEXT',
    );

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_clientes_ativo_nome
        ON clientes (ativo, nome COLLATE NOCASE)
      ''');
  }

  Future<void> _criarTabelaVeiculos(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS veiculos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cliente_id INTEGER NOT NULL,
          marca TEXT NOT NULL,
          modelo TEXT NOT NULL,
          placa TEXT,
          cor TEXT,
          ano TEXT,
          observacoes TEXT,
          FOREIGN KEY (cliente_id)
            REFERENCES clientes (id)
            ON DELETE CASCADE
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_veiculos_cliente_id
        ON veiculos (cliente_id)
      ''');
  }

  Future<void> _criarTabelaAgendamentos(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS agendamentos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cliente_id INTEGER NOT NULL,
          veiculo_id INTEGER NOT NULL,
          servico TEXT NOT NULL,
          data TEXT NOT NULL,
          hora TEXT NOT NULL,
          valor REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'Agendado',
          observacoes TEXT,
          FOREIGN KEY (cliente_id)
            REFERENCES clientes (id)
            ON DELETE CASCADE,
          FOREIGN KEY (veiculo_id)
            REFERENCES veiculos (id)
            ON DELETE CASCADE
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_agendamentos_cliente_id
        ON agendamentos (cliente_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_agendamentos_veiculo_id
        ON agendamentos (veiculo_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_agendamentos_data
        ON agendamentos (data)
      ''');
  }

  Future<void> _criarTabelaFotos(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS fotos_servico (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cliente_id INTEGER NOT NULL,
          veiculo_id INTEGER NOT NULL,
          caminho_antes TEXT NOT NULL,
          caminho_depois TEXT NOT NULL,
          descricao TEXT,
          data TEXT NOT NULL,
          FOREIGN KEY (cliente_id)
            REFERENCES clientes (id)
            ON DELETE CASCADE,
          FOREIGN KEY (veiculo_id)
            REFERENCES veiculos (id)
            ON DELETE CASCADE
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_fotos_cliente_id
        ON fotos_servico (cliente_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_fotos_veiculo_id
        ON fotos_servico (veiculo_id)
      ''');
  }

  Future<void> _criarTabelaMovimentosFinanceiros(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS movimentos_financeiros (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tipo TEXT NOT NULL,
          descricao TEXT NOT NULL,
          valor REAL NOT NULL DEFAULT 0,
          forma_pagamento TEXT,
          data TEXT NOT NULL,
          cliente_id INTEGER,
          agendamento_id INTEGER,
          FOREIGN KEY (cliente_id)
            REFERENCES clientes (id)
            ON DELETE SET NULL,
          FOREIGN KEY (agendamento_id)
            REFERENCES agendamentos (id)
            ON DELETE SET NULL
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_cliente_id
        ON movimentos_financeiros (cliente_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_agendamento_id
        ON movimentos_financeiros (agendamento_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_data
        ON movimentos_financeiros (data)
      ''');
  }

  Future<void> _criarTabelaOrcamentos(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS orcamentos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cliente_id INTEGER NOT NULL,
          veiculo_id INTEGER,
          servico TEXT NOT NULL DEFAULT '',
          descricao TEXT NOT NULL DEFAULT '',
          valor REAL NOT NULL DEFAULT 0,
          data_emissao TEXT NOT NULL,
          validade TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'Pendente',
          observacoes TEXT NOT NULL DEFAULT '',
          desconto REAL NOT NULL DEFAULT 0,
          FOREIGN KEY (cliente_id)
            REFERENCES clientes (id)
            ON DELETE CASCADE,
          FOREIGN KEY (veiculo_id)
            REFERENCES veiculos (id)
            ON DELETE SET NULL
        )
      ''');

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'orcamentos',
      coluna: 'desconto',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_orcamentos_cliente_id
        ON orcamentos (cliente_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_orcamentos_veiculo_id
        ON orcamentos (veiculo_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_orcamentos_status
        ON orcamentos (status)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_orcamentos_data_emissao
        ON orcamentos (data_emissao)
      ''');
  }

  Future<void> _criarTabelaItensOrcamento(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS orcamento_itens (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          orcamento_id INTEGER NOT NULL,
          servico TEXT NOT NULL,
          descricao TEXT NOT NULL DEFAULT '',
          quantidade REAL NOT NULL DEFAULT 1,
          valor_unitario REAL NOT NULL DEFAULT 0,
          ordem INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (orcamento_id)
            REFERENCES orcamentos (id)
            ON DELETE CASCADE
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_orcamento_itens_orcamento_id
        ON orcamento_itens (orcamento_id)
      ''');
  }

  Future<void> _criarTabelaOrdensServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordens_servico (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          orcamento_id INTEGER,
          agendamento_id INTEGER,
          cliente_id INTEGER NOT NULL,
          veiculo_id INTEGER,
          numero TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'Aberta',
          data_abertura TEXT NOT NULL,
          data_inicio TEXT,
          data_finalizacao TEXT,
          hora_entrada TEXT,
          hora_saida TEXT,
          funcionario_responsavel TEXT NOT NULL DEFAULT '',
          observacoes TEXT NOT NULL DEFAULT '',
          valor_total REAL NOT NULL DEFAULT 0,
          desconto REAL NOT NULL DEFAULT 0,
          forma_pagamento TEXT,
          quilometragem_entrada TEXT NOT NULL DEFAULT '',
          combustivel_entrada TEXT NOT NULL DEFAULT '',
          assinatura_cliente TEXT,
          lancado_financeiro INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (orcamento_id)
            REFERENCES orcamentos (id)
            ON DELETE SET NULL,
          FOREIGN KEY (agendamento_id)
            REFERENCES agendamentos (id)
            ON DELETE SET NULL,
          FOREIGN KEY (cliente_id)
            REFERENCES clientes (id)
            ON DELETE CASCADE,
          FOREIGN KEY (veiculo_id)
            REFERENCES veiculos (id)
            ON DELETE SET NULL
        )
      ''');

    await database.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS
        idx_ordens_servico_numero
        ON ordens_servico (numero)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_orcamento_id
        ON ordens_servico (orcamento_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_cliente_id
        ON ordens_servico (cliente_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_veiculo_id
        ON ordens_servico (veiculo_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_status
        ON ordens_servico (status)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_data_abertura
        ON ordens_servico (data_abertura)
      ''');
  }

  Future<void> _criarTabelaItensOrdemServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_itens (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          orcamento_item_id INTEGER,
          servico TEXT NOT NULL,
          descricao TEXT NOT NULL DEFAULT '',
          quantidade REAL NOT NULL DEFAULT 1,
          valor_unitario REAL NOT NULL DEFAULT 0,
          concluido INTEGER NOT NULL DEFAULT 0,
          ordem INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE,
          FOREIGN KEY (orcamento_item_id)
            REFERENCES orcamento_itens (id)
            ON DELETE SET NULL
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordem_servico_itens_os_id
        ON ordem_servico_itens (ordem_servico_id)
      ''');
  }

  Future<void> _criarTabelaChecklistOrdemServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_checklist (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          categoria TEXT NOT NULL DEFAULT 'Geral',
          item TEXT NOT NULL,
          marcado INTEGER NOT NULL DEFAULT 0,
          status INTEGER NOT NULL DEFAULT 0,
          observacao TEXT NOT NULL DEFAULT '',
          foto_avaria TEXT,
          avaria_localizacao TEXT NOT NULL DEFAULT '',
          avaria_data_registro TEXT,
          ordem INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE
        )
      ''');

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'status',
      definicao: 'INTEGER NOT NULL DEFAULT 0',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'foto_avaria',
      definicao: 'TEXT',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'avaria_localizacao',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'avaria_data_registro',
      definicao: 'TEXT',
    );

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordem_servico_checklist_os_id
        ON ordem_servico_checklist (ordem_servico_id)
      ''');
  }

  Future<void> _atualizarChecklistParaVersao8(Database database) async {
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'status',
      definicao: 'INTEGER NOT NULL DEFAULT 0',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'foto_avaria',
      definicao: 'TEXT',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'avaria_localizacao',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'avaria_data_registro',
      definicao: 'TEXT',
    );
  }

  Future<void> _criarTabelaFotosOrdemServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_fotos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          etapa TEXT NOT NULL DEFAULT 'Antes',
          caminho TEXT NOT NULL,
          descricao TEXT NOT NULL DEFAULT '',
          data TEXT NOT NULL,
          ordem INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordem_servico_fotos_os_id
        ON ordem_servico_fotos (ordem_servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordem_servico_fotos_etapa
        ON ordem_servico_fotos (etapa)
      ''');
  }

  Future<void> _criarTabelaProdutosOrdemServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_produtos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          produto_id INTEGER,
          produto_nome TEXT NOT NULL,
          quantidade REAL NOT NULL DEFAULT 0,
          unidade TEXT NOT NULL DEFAULT '',
          custo_unitario REAL NOT NULL DEFAULT 0,
          custo_unitario_no_momento REAL NOT NULL DEFAULT 0,
          custo_total_no_momento REAL NOT NULL DEFAULT 0,
          composicao_lotes_json TEXT NOT NULL DEFAULT '',
          baixado_estoque INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordem_servico_produtos_os_id
        ON ordem_servico_produtos (ordem_servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordem_servico_produtos_produto_id
        ON ordem_servico_produtos (produto_id)
      ''');
  }

  Future<void> _criarTabelaItensEstoque(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS itens_estoque (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          categoria TEXT NOT NULL DEFAULT '',
          quantidade REAL NOT NULL DEFAULT 0,
          quantidade_minima REAL NOT NULL DEFAULT 0,
          unidade TEXT NOT NULL DEFAULT 'un',
          valor_total_pago REAL NOT NULL DEFAULT 0,
          quantidade_total REAL NOT NULL DEFAULT 0,
          custo_unitario REAL NOT NULL DEFAULT 0,
          custo_unitario_calculado REAL NOT NULL DEFAULT 0,
          fornecedor TEXT NOT NULL DEFAULT '',
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          atualizado_em TEXT NOT NULL
        )
      ''');

    // Em bancos legados, a tabela pode existir sem esta coluna.
    // Garantimos a coluna antes de criar o índice para evitar falha de migração.
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'itens_estoque',
      coluna: 'ativo',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_itens_estoque_nome
        ON itens_estoque (nome)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_itens_estoque_categoria
        ON itens_estoque (categoria)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_itens_estoque_ativo
        ON itens_estoque (ativo)
      ''');
  }

  Future<void> _criarTabelaMovimentacoesEstoque(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS movimentacoes_estoque (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_estoque_id INTEGER NOT NULL,
          tipo TEXT NOT NULL,
          quantidade REAL NOT NULL DEFAULT 0,
          quantidade_anterior REAL NOT NULL DEFAULT 0,
          quantidade_posterior REAL NOT NULL DEFAULT 0,
          custo_unitario REAL NOT NULL DEFAULT 0,
          observacoes TEXT NOT NULL DEFAULT '',
          motivo TEXT NOT NULL DEFAULT '',
          origem TEXT NOT NULL DEFAULT 'Manual',
          ordem_servico_id INTEGER,
          lote_id INTEGER,
          data TEXT NOT NULL,
          FOREIGN KEY (item_estoque_id)
            REFERENCES itens_estoque (id)
            ON DELETE CASCADE,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE SET NULL,
          FOREIGN KEY (lote_id)
            REFERENCES estoque_lotes (id)
            ON DELETE SET NULL
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentacoes_estoque_item_id
        ON movimentacoes_estoque (item_estoque_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentacoes_estoque_data
        ON movimentacoes_estoque (data)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentacoes_estoque_tipo
        ON movimentacoes_estoque (tipo)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentacoes_estoque_os_id
        ON movimentacoes_estoque (ordem_servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentacoes_estoque_lote_id
        ON movimentacoes_estoque (lote_id)
      ''');
  }

  Future<void> _criarTabelaConfiguracoesEstoque(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS configuracoes_estoque (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          controlar_estoque INTEGER NOT NULL DEFAULT 1,
          controlar_produtos_ordem_servico INTEGER NOT NULL DEFAULT 1,
          baixa_automatica INTEGER NOT NULL DEFAULT 1,
          exigir_quantidade INTEGER NOT NULL DEFAULT 1,
          alertar_estoque_baixo INTEGER NOT NULL DEFAULT 1,
          estoque_minimo_padrao REAL NOT NULL DEFAULT 2,
          controlar_produtos_os INTEGER NOT NULL DEFAULT 1,
          baixar_automaticamente INTEGER NOT NULL DEFAULT 1,
          atualizado_em TEXT NOT NULL
        )
      ''');
  }

  Future<void> _inserirConfiguracaoEstoquePadrao(Database database) async {
    await database.insert('configuracoes_estoque', {
      'id': 1,
      'controlar_estoque': 1,
      'controlar_produtos_ordem_servico': 1,
      'baixa_automatica': 1,
      'exigir_quantidade': 1,
      'alertar_estoque_baixo': 1,
      'estoque_minimo_padrao': 2,
      'controlar_produtos_os': 1,
      'baixar_automaticamente': 1,
      'atualizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _atualizarConfiguracoesEstoqueParaVersao11(
    Database database,
  ) async {
    await _criarTabelaConfiguracoesEstoque(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'controlar_estoque',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'controlar_produtos_ordem_servico',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'baixa_automatica',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'exigir_quantidade',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'alertar_estoque_baixo',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'estoque_minimo_padrao',
      definicao: 'REAL NOT NULL DEFAULT 2',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'controlar_produtos_os',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes_estoque',
      coluna: 'baixar_automaticamente',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _inserirConfiguracaoEstoquePadrao(database);

    await database.execute('''
        UPDATE configuracoes_estoque
        SET
          controlar_estoque = 1,
          controlar_produtos_ordem_servico =
            CASE
              WHEN controlar_produtos_os = 1 THEN 1
              ELSE controlar_produtos_ordem_servico
            END,
          baixa_automatica =
            CASE
              WHEN baixar_automaticamente = 1 THEN 1
              ELSE baixa_automatica
            END,
          controlar_produtos_os =
            CASE
              WHEN controlar_produtos_ordem_servico = 1 THEN 1
              ELSE controlar_produtos_os
            END,
          baixar_automaticamente =
            CASE
              WHEN baixa_automatica = 1 THEN 1
              ELSE baixar_automaticamente
            END,
          atualizado_em = '${DateTime.now().toIso8601String()}'
        WHERE id = 1
      ''');
  }

  Future<void> _criarTabelaServicosCatalogo(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS servicos_catalogo (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          categoria_id INTEGER,
          categoria TEXT NOT NULL DEFAULT '',
          descricao TEXT NOT NULL DEFAULT '',
          observacoes_padrao TEXT NOT NULL DEFAULT '',
          preco_minimo REAL NOT NULL DEFAULT 0,
          preco_padrao REAL NOT NULL DEFAULT 0,
          preco_maximo REAL NOT NULL DEFAULT 0,
          duracao_minutos INTEGER NOT NULL DEFAULT 0,
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servicos_catalogo_nome
        ON servicos_catalogo (nome)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servicos_catalogo_categoria
        ON servicos_catalogo (categoria)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servicos_catalogo_categoria_id
        ON servicos_catalogo (categoria_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servicos_catalogo_ativo
        ON servicos_catalogo (ativo)
      ''');
  }

  Future<void> _criarTabelaCategoriasServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS servico_categorias (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          UNIQUE(nome)
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servico_categorias_nome
        ON servico_categorias (nome)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servico_categorias_ativo
        ON servico_categorias (ativo)
      ''');
  }

  Future<void> _criarTabelaEstoqueLotes(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS estoque_lotes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_estoque_id INTEGER NOT NULL,
          data_compra TEXT NOT NULL,
          quantidade_original REAL NOT NULL DEFAULT 0,
          quantidade_normalizada REAL NOT NULL DEFAULT 0,
          quantidade_disponivel REAL NOT NULL DEFAULT 0,
          unidade_original TEXT NOT NULL DEFAULT '',
          unidade_base TEXT NOT NULL DEFAULT 'un',
          valor_total_pago REAL NOT NULL DEFAULT 0,
          custo_unitario REAL NOT NULL DEFAULT 0,
          fornecedor TEXT NOT NULL DEFAULT '',
          observacao TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          FOREIGN KEY (item_estoque_id)
            REFERENCES itens_estoque (id)
            ON DELETE CASCADE
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_estoque_lotes_item_id
        ON estoque_lotes (item_estoque_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_estoque_lotes_data_compra
        ON estoque_lotes (data_compra)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_estoque_lotes_ativo
        ON estoque_lotes (ativo)
      ''');
  }

  Future<void> _criarTabelaOrdemServicoProdutoLotes(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_produto_lotes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_produto_id INTEGER NOT NULL,
          lote_id INTEGER,
          quantidade REAL NOT NULL DEFAULT 0,
          custo_unitario REAL NOT NULL DEFAULT 0,
          custo_total REAL NOT NULL DEFAULT 0,
          criado_em TEXT NOT NULL,
          FOREIGN KEY (ordem_servico_produto_id)
            REFERENCES ordem_servico_produtos (id)
            ON DELETE CASCADE,
          FOREIGN KEY (lote_id)
            REFERENCES estoque_lotes (id)
            ON DELETE SET NULL
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_produto_lotes_produto_os_id
        ON ordem_servico_produto_lotes (ordem_servico_produto_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_produto_lotes_lote_id
        ON ordem_servico_produto_lotes (lote_id)
      ''');
  }

  Future<void> _criarTabelaServicoProdutos(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS servico_produtos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          servico_id INTEGER NOT NULL,
          item_estoque_id INTEGER NOT NULL,
          quantidade_padrao REAL NOT NULL DEFAULT 0,
          unidade TEXT NOT NULL DEFAULT '',
          obrigatorio INTEGER NOT NULL DEFAULT 0,
          marcado_por_padrao INTEGER NOT NULL DEFAULT 0,
          ordem INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (servico_id)
            REFERENCES servicos_catalogo (id)
            ON DELETE CASCADE,
          FOREIGN KEY (item_estoque_id)
            REFERENCES itens_estoque (id)
            ON DELETE CASCADE,
          UNIQUE (servico_id, item_estoque_id)
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servico_produtos_servico_id
        ON servico_produtos (servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servico_produtos_item_id
        ON servico_produtos (item_estoque_id)
      ''');
  }

  Future<void> _criarTabelaServicosRelacionados(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS servicos_relacionados (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          servico_id INTEGER NOT NULL,
          servico_relacionado_id INTEGER NOT NULL,
          ordem INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (servico_id)
            REFERENCES servicos_catalogo (id)
            ON DELETE CASCADE,
          FOREIGN KEY (servico_relacionado_id)
            REFERENCES servicos_catalogo (id)
            ON DELETE CASCADE,
          UNIQUE (servico_id, servico_relacionado_id),
          CHECK (servico_id <> servico_relacionado_id)
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_servicos_relacionados_servico_id
        ON servicos_relacionados (servico_id)
      ''');
  }

  Future<void> _criarTabelaConfiguracoes(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS configuracoes (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          nome_fantasia TEXT NOT NULL DEFAULT 'Sua empresa',
          razao_social TEXT NOT NULL DEFAULT '',
          cnpj TEXT NOT NULL DEFAULT '',
          inscricao_estadual TEXT NOT NULL DEFAULT '',
          telefone TEXT NOT NULL DEFAULT '',
          whatsapp TEXT NOT NULL DEFAULT '',
          email TEXT NOT NULL DEFAULT '',
          site TEXT NOT NULL DEFAULT '',
          instagram TEXT NOT NULL DEFAULT '',
          facebook TEXT NOT NULL DEFAULT '',
          endereco TEXT NOT NULL DEFAULT '',
          numero TEXT NOT NULL DEFAULT '',
          complemento TEXT NOT NULL DEFAULT '',
          bairro TEXT NOT NULL DEFAULT '',
          cidade TEXT NOT NULL DEFAULT '',
          estado TEXT NOT NULL DEFAULT '',
          cep TEXT NOT NULL DEFAULT '',
          caminho_logo TEXT,
          caminho_assinatura_empresa TEXT,
          nome_aplicativo TEXT NOT NULL DEFAULT 'Imperium Detailing',
          cor_principal INTEGER NOT NULL DEFAULT 4292257867,
          cor_secundaria INTEGER NOT NULL DEFAULT 4280295456,
          tema TEXT NOT NULL DEFAULT 'escuro',
          validade_orcamento_dias INTEGER NOT NULL DEFAULT 15,
          rodape_documentos TEXT NOT NULL DEFAULT '',
          termos_orcamento TEXT NOT NULL DEFAULT '',
          termos_ordem_servico TEXT NOT NULL DEFAULT '',
          observacao_padrao TEXT NOT NULL DEFAULT '',
          mensagem_agradecimento TEXT NOT NULL DEFAULT '',
          mensagem_orcamento TEXT NOT NULL DEFAULT '',
          mensagem_confirmacao TEXT NOT NULL DEFAULT '',
          mensagem_entrega TEXT NOT NULL DEFAULT '',
          mensagem_cobranca TEXT NOT NULL DEFAULT '',
          ultimo_backup_em TEXT,
          ultimo_backup_caminho TEXT,
          ultimo_backup_tamanho_bytes INTEGER NOT NULL DEFAULT 0,
          atualizado_em TEXT NOT NULL
        )
      ''');
  }

  Future<void> _inserirConfiguracaoPadrao(Database database) async {
    await database.insert('configuracoes', {
      'id': 1,
      'nome_fantasia': 'Sua empresa',
      'nome_aplicativo': 'Imperium Detailing',
      'cor_principal': 0xFFD6A84B,
      'cor_secundaria': 0xFF1A1A1A,
      'tema': 'escuro',
      'validade_orcamento_dias': 15,
      'atualizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _atualizarConfiguracoesParaVersao13(Database database) async {
    await _criarTabelaConfiguracoes(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes',
      coluna: 'facebook',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes',
      coluna: 'caminho_assinatura_empresa',
      definicao: 'TEXT',
    );
  }

  Future<void> _atualizarConfiguracoesParaVersao14(Database database) async {
    await _criarTabelaConfiguracoes(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes',
      coluna: 'ultimo_backup_em',
      definicao: 'TEXT',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes',
      coluna: 'ultimo_backup_caminho',
      definicao: 'TEXT',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'configuracoes',
      coluna: 'ultimo_backup_tamanho_bytes',
      definicao: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _atualizarItensEstoqueParaVersao15(Database database) async {
    await _criarTabelaItensEstoque(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'itens_estoque',
      coluna: 'valor_total_pago',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'itens_estoque',
      coluna: 'quantidade_total',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'itens_estoque',
      coluna: 'custo_unitario_calculado',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await database.execute('''
        UPDATE itens_estoque
        SET custo_unitario_calculado = CASE
          WHEN COALESCE(custo_unitario_calculado, 0) > 0 THEN custo_unitario_calculado
          ELSE COALESCE(custo_unitario, 0)
        END
        WHERE COALESCE(custo_unitario, 0) > 0
      ''');
  }

  Future<void> _atualizarProdutosOrdemServicoParaVersao16(
    Database database,
  ) async {
    await _criarTabelaProdutosOrdemServico(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_produtos',
      coluna: 'custo_unitario_no_momento',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_produtos',
      coluna: 'custo_total_no_momento',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await database.execute('''
        UPDATE ordem_servico_produtos
        SET
          custo_unitario_no_momento = CASE
            WHEN COALESCE(custo_unitario_no_momento, 0) > 0
              THEN custo_unitario_no_momento
            ELSE COALESCE(custo_unitario, 0)
          END,
          custo_total_no_momento = CASE
            WHEN COALESCE(custo_total_no_momento, 0) > 0
              THEN custo_total_no_momento
            ELSE COALESCE(quantidade, 0) * CASE
              WHEN COALESCE(custo_unitario_no_momento, 0) > 0
                THEN custo_unitario_no_momento
              ELSE COALESCE(custo_unitario, 0)
            END
          END
      ''');
  }

  Future<void> _atualizarParaVersao17(Database database) async {
    await _criarTabelaItensEstoque(database);
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'itens_estoque',
      coluna: 'ativo',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    await _criarTabelaCategoriasServico(database);
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'movimentacoes_estoque',
      coluna: 'lote_id',
      definicao: 'INTEGER',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'servicos_catalogo',
      coluna: 'categoria_id',
      definicao: 'INTEGER',
    );
    await _criarTabelaEstoqueLotes(database);
    await _criarTabelaOrdemServicoProdutoLotes(database);
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_produtos',
      coluna: 'composicao_lotes_json',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await database.execute('''
        INSERT OR IGNORE INTO servico_categorias (
          nome,
          ativo,
          criado_em,
          atualizado_em
        )
        SELECT DISTINCT
          TRIM(categoria) AS nome,
          1,
          '${DateTime.now().toIso8601String()}',
          '${DateTime.now().toIso8601String()}'
        FROM servicos_catalogo
        WHERE TRIM(COALESCE(categoria, '')) != ''
      ''');

    await database.execute('''
        UPDATE servicos_catalogo
        SET categoria_id = (
          SELECT c.id
          FROM servico_categorias c
          WHERE LOWER(TRIM(c.nome)) = LOWER(TRIM(servicos_catalogo.categoria))
          LIMIT 1
        )
        WHERE TRIM(COALESCE(categoria, '')) != ''
      ''');

    final itens = await database.rawQuery('''
      SELECT
        id,
        quantidade,
        unidade,
        valor_total_pago,
        quantidade_total,
        custo_unitario,
        custo_unitario_calculado,
        fornecedor,
        observacoes,
        atualizado_em
      FROM itens_estoque
      ''');

    for (final item in itens) {
      final itemId = (item['id'] as num?)?.toInt();

      if (itemId == null) {
        continue;
      }

      final jaTemLote = await database.rawQuery(
        'SELECT id FROM estoque_lotes WHERE item_estoque_id = ? LIMIT 1',
        [itemId],
      );

      if (jaTemLote.isNotEmpty) {
        continue;
      }

      final quantidade = (item['quantidade'] as num?)?.toDouble() ?? 0;

      if (quantidade <= 0) {
        continue;
      }

      final custoCalculado =
          (item['custo_unitario_calculado'] as num?)?.toDouble() ?? 0;
      final custoLegado = (item['custo_unitario'] as num?)?.toDouble() ?? 0;
      final custoUnitario = custoCalculado > 0 ? custoCalculado : custoLegado;

      if (custoUnitario <= 0) {
        continue;
      }

      final valorTotalPago =
          (item['valor_total_pago'] as num?)?.toDouble() ?? 0;
      final quantidadeTotal =
          (item['quantidade_total'] as num?)?.toDouble() ?? 0;

      final valorLote = valorTotalPago > 0
          ? valorTotalPago
          : (quantidade * custoUnitario);
      final quantidadeOriginal = quantidadeTotal > 0
          ? quantidadeTotal
          : quantidade;
      final unidadeBase = _normalizarUnidadeBase(
        item['unidade']?.toString() ?? 'un',
      );
      final timestamp =
          item['atualizado_em']?.toString().trim().isNotEmpty == true
          ? item['atualizado_em'].toString()
          : DateTime.now().toIso8601String();

      await database.insert('estoque_lotes', {
        'item_estoque_id': itemId,
        'data_compra': timestamp,
        'quantidade_original': quantidadeOriginal,
        'quantidade_disponivel': quantidade,
        'unidade_base': unidadeBase,
        'valor_total_pago': valorLote,
        'custo_unitario': custoUnitario,
        'fornecedor': item['fornecedor']?.toString() ?? '',
        'observacao': item['observacoes']?.toString() ?? 'Lote legado',
        'ativo': 1,
        'criado_em': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    }
  }

  Future<void> _atualizarParaVersao18(Database database) async {
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'quilometragem_entrada',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'combustivel_entrada',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'avaria_localizacao',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_checklist',
      coluna: 'avaria_data_registro',
      definicao: 'TEXT',
    );
  }

  Future<void> _atualizarParaVersao19(Database database) async {
    await _criarTabelaMovimentacoesEstoque(database);
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'movimentacoes_estoque',
      coluna: 'motivo',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _criarTabelaEstoqueLotes(database);
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'estoque_lotes',
      coluna: 'quantidade_normalizada',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'estoque_lotes',
      coluna: 'unidade_original',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await database.execute('''
        UPDATE estoque_lotes
        SET
          quantidade_normalizada = CASE
            WHEN COALESCE(quantidade_normalizada, 0) > 0
              THEN quantidade_normalizada
            ELSE COALESCE(quantidade_original, 0)
          END,
          unidade_original = CASE
            WHEN TRIM(COALESCE(unidade_original, '')) != ''
              THEN unidade_original
            WHEN LOWER(TRIM(COALESCE(unidade_base, ''))) IN ('ml', 'g', 'metro', 'unidade')
              THEN LOWER(TRIM(unidade_base))
            ELSE 'unidade'
          END
      ''');
  }

  Future<void> _atualizarParaVersao20(Database database) async {
    await _criarTabelaClientes(database);

    await database.execute('''
        UPDATE clientes
        SET ativo = 1
        WHERE ativo IS NULL
      ''');
  }

  String _normalizarUnidadeBase(String unidade) {
    switch (unidade.trim().toLowerCase()) {
      case 'l':
        return 'ml';
      case 'kg':
        return 'g';
      case 'metro':
      case 'm':
        return 'metro';
      case 'un':
      case 'unidade':
        return 'unidade';
      case 'ml':
        return 'ml';
      case 'g':
        return 'g';
      default:
        return 'unidade';
    }
  }

  Future<void> _migrarOrcamentosAntigos(Database database) async {
    final tabelaExiste = await _tabelaExiste(database, 'orcamentos');

    if (!tabelaExiste) {
      return;
    }

    await database.execute('''
        INSERT INTO orcamento_itens (
          orcamento_id,
          servico,
          descricao,
          quantidade,
          valor_unitario,
          ordem
        )
        SELECT
          o.id,
          CASE
            WHEN TRIM(COALESCE(o.servico, '')) = ''
              THEN 'Serviço'
            ELSE o.servico
          END,
          COALESCE(o.descricao, ''),
          1,
          COALESCE(o.valor, 0),
          0
        FROM orcamentos o
        WHERE NOT EXISTS (
          SELECT 1
          FROM orcamento_itens i
          WHERE i.orcamento_id = o.id
        )
      ''');
  }

  Future<bool> _tabelaExiste(Database database, String tabela) async {
    final resultado = await database.rawQuery(
      '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name = ?
        LIMIT 1
        ''',
      [tabela],
    );

    return resultado.isNotEmpty;
  }

  Future<void> _adicionarColunaSeNecessario({
    required Database database,
    required String tabela,
    required String coluna,
    required String definicao,
  }) async {
    final tabelaExiste = await _tabelaExiste(database, tabela);

    if (!tabelaExiste) {
      return;
    }

    final colunas = await database.rawQuery('PRAGMA table_info($tabela)');

    final colunaExiste = colunas.any(
      (item) => item['name']?.toString() == coluna,
    );

    if (colunaExiste) {
      return;
    }

    await database.execute(
      'ALTER TABLE $tabela '
      'ADD COLUMN $coluna $definicao',
    );
  }

  Future<void> fecharBanco() async {
    final database = _database;

    if (database == null) {
      return;
    }

    await database.close();
    _database = null;
  }
}
