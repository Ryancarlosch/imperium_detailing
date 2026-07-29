import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

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

    final caminho = join(
      pastaBanco,
      'imperium_detailing.db',
    );

    return openDatabase(
      caminho,
      version: 10,
      onConfigure: (database) async {
        await database.execute(
          'PRAGMA foreign_keys = ON',
        );
      },
      onCreate: (database, version) async {
        await _criarTabelas(database);
      },
      onUpgrade: (
          database,
          versaoAntiga,
          versaoNova,
          ) async {
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
          await _criarTabelaMovimentosFinanceiros(
            database,
          );
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
      },
    );
  }

  Future<void> _criarTabelas(
      Database database,
      ) async {
    await _criarTabelaClientes(database);
    await _criarTabelaVeiculos(database);
    await _criarTabelaAgendamentos(database);
    await _criarTabelaFotos(database);
    await _criarTabelaMovimentosFinanceiros(
      database,
    );
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
    await _criarTabelaMovimentacoesEstoque(database);
    await _criarTabelaConfiguracoesEstoque(database);
    await _inserirConfiguracaoEstoquePadrao(database);
  }

  Future<void> _criarTabelaClientes(
      Database database,
      ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS clientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        telefone TEXT,
        email TEXT,
        endereco TEXT,
        observacoes TEXT
      )
    ''');
  }

  Future<void> _criarTabelaVeiculos(
      Database database,
      ) async {
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

  Future<void> _criarTabelaAgendamentos(
      Database database,
      ) async {
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

  Future<void> _criarTabelaFotos(
      Database database,
      ) async {
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

  Future<void> _criarTabelaMovimentosFinanceiros(
      Database database,
      ) async {
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

  Future<void> _criarTabelaOrcamentos(
      Database database,
      ) async {
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

  Future<void> _criarTabelaItensOrcamento(
      Database database,
      ) async {
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

  Future<void> _criarTabelaOrdensServico(
      Database database,
      ) async {
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

  Future<void> _criarTabelaItensOrdemServico(
      Database database,
      ) async {
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

  Future<void> _criarTabelaChecklistOrdemServico(
      Database database,
      ) async {
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

    await database.execute('''
      CREATE INDEX IF NOT EXISTS
      idx_ordem_servico_checklist_os_id
      ON ordem_servico_checklist (ordem_servico_id)
    ''');
  }

  Future<void> _atualizarChecklistParaVersao8(
      Database database,
      ) async {
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
  }

  Future<void> _criarTabelaFotosOrdemServico(
      Database database,
      ) async {
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

  Future<void> _criarTabelaProdutosOrdemServico(
      Database database,
      ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS ordem_servico_produtos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ordem_servico_id INTEGER NOT NULL,
        produto_id INTEGER,
        produto_nome TEXT NOT NULL,
        quantidade REAL NOT NULL DEFAULT 0,
        unidade TEXT NOT NULL DEFAULT '',
        custo_unitario REAL NOT NULL DEFAULT 0,
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


  Future<void> _criarTabelaItensEstoque(
      Database database,
      ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS itens_estoque (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        categoria TEXT NOT NULL DEFAULT '',
        quantidade REAL NOT NULL DEFAULT 0,
        quantidade_minima REAL NOT NULL DEFAULT 0,
        unidade TEXT NOT NULL DEFAULT 'un',
        custo_unitario REAL NOT NULL DEFAULT 0,
        fornecedor TEXT NOT NULL DEFAULT '',
        observacoes TEXT NOT NULL DEFAULT '',
        atualizado_em TEXT NOT NULL
      )
    ''');

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
  }

  Future<void> _criarTabelaMovimentacoesEstoque(
      Database database,
      ) async {
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
        origem TEXT NOT NULL DEFAULT 'Manual',
        ordem_servico_id INTEGER,
        data TEXT NOT NULL,
        FOREIGN KEY (item_estoque_id)
          REFERENCES itens_estoque (id)
          ON DELETE CASCADE,
        FOREIGN KEY (ordem_servico_id)
          REFERENCES ordens_servico (id)
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
  }

  Future<void> _criarTabelaConfiguracoesEstoque(
      Database database,
      ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS configuracoes_estoque (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        controlar_produtos_os INTEGER NOT NULL DEFAULT 0,
        baixar_automaticamente INTEGER NOT NULL DEFAULT 0,
        exigir_quantidade INTEGER NOT NULL DEFAULT 0,
        alertar_estoque_baixo INTEGER NOT NULL DEFAULT 1,
        atualizado_em TEXT NOT NULL
      )
    ''');
  }

  Future<void> _inserirConfiguracaoEstoquePadrao(
      Database database,
      ) async {
    await database.insert(
      'configuracoes_estoque',
      {
        'id': 1,
        'controlar_produtos_os': 0,
        'baixar_automaticamente': 0,
        'exigir_quantidade': 0,
        'alertar_estoque_baixo': 1,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _criarTabelaConfiguracoes(
      Database database,
      ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS configuracoes (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        nome_fantasia TEXT NOT NULL DEFAULT 'Imperium Detailing',
        razao_social TEXT NOT NULL DEFAULT '',
        cnpj TEXT NOT NULL DEFAULT '',
        inscricao_estadual TEXT NOT NULL DEFAULT '',
        telefone TEXT NOT NULL DEFAULT '',
        whatsapp TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        site TEXT NOT NULL DEFAULT '',
        instagram TEXT NOT NULL DEFAULT '',
        endereco TEXT NOT NULL DEFAULT '',
        numero TEXT NOT NULL DEFAULT '',
        complemento TEXT NOT NULL DEFAULT '',
        bairro TEXT NOT NULL DEFAULT '',
        cidade TEXT NOT NULL DEFAULT '',
        estado TEXT NOT NULL DEFAULT '',
        cep TEXT NOT NULL DEFAULT '',
        caminho_logo TEXT,
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
        atualizado_em TEXT NOT NULL
      )
    ''');
  }

  Future<void> _inserirConfiguracaoPadrao(
      Database database,
      ) async {
    await database.insert(
      'configuracoes',
      {
        'id': 1,
        'nome_fantasia': 'Imperium Detailing',
        'nome_aplicativo': 'Imperium Detailing',
        'cor_principal': 0xFFD6A84B,
        'cor_secundaria': 0xFF1A1A1A,
        'tema': 'escuro',
        'validade_orcamento_dias': 15,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _migrarOrcamentosAntigos(
      Database database,
      ) async {
    final tabelaExiste = await _tabelaExiste(
      database,
      'orcamentos',
    );

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

  Future<bool> _tabelaExiste(
      Database database,
      String tabela,
      ) async {
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
    final tabelaExiste = await _tabelaExiste(
      database,
      tabela,
    );

    if (!tabelaExiste) {
      return;
    }

    final colunas = await database.rawQuery(
      'PRAGMA table_info($tabela)',
    );

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
