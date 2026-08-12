import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const int schemaVersion = 27;

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
      onOpen: (database) async {
        await _aplicarPlanoContasSimplificado(database);
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

        if (versaoAntiga < 21) {
          await _atualizarParaVersao21(database);
        }

        if (versaoAntiga < 22) {
          await _atualizarParaVersao22(database);
        }

        if (versaoAntiga < 23) {
          await _atualizarParaVersao23(database);
        }

        if (versaoAntiga < 24) {
          await _atualizarParaVersao24(database);
        }

        if (versaoAntiga < 25) {
          await _atualizarParaVersao25(database);
        }

        if (versaoAntiga < 26) {
          await _atualizarParaVersao26(database);
        }

        if (versaoAntiga < 27) {
          await _atualizarParaVersao27(database);
        }
      },
    );
  }

  Future<void> _criarTabelas(Database database) async {
    await _criarTabelaClientes(database);
    await _criarTabelaVeiculos(database);
    await _criarTabelaAgendamentos(database);
    await _criarTabelaFotos(database);
    await _criarTabelaOrcamentos(database);
    await _criarTabelaItensOrcamento(database);
    await _criarTabelaOrdensServico(database);
    await _criarTabelaRevisoesOrdemServico(database);
    await _criarTabelaAjustesFinanceirosOrdemServico(database);
    await _criarTabelaPlanoContasFinanceiro(database);
    await _inserirPlanoContasFinanceiroPadrao(database);
    await _criarTabelaContasFinanceiras(database);
    await _inserirContaFinanceiraPadrao(database);
    await _criarTabelaFornecedores(database);
    await _criarTabelaTransferenciasFinanceiras(database);
    await _criarTabelaCustosFixos(database);
    await _criarTabelaColaboradoresCusto(database);
    await _criarTabelaMaoObraOrdemServico(database);
    await _criarTabelaRegrasTaxaCartao(database);
    await _criarTabelaMetasFinanceiras(database);
    await _criarTabelaPagamentosOrdemServico(database);
    await _criarTabelaMovimentosFinanceiros(database);
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

  Future<void> _criarTabelaPlanoContasFinanceiro(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_plano_contas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          codigo TEXT NOT NULL UNIQUE,
          nome TEXT NOT NULL,
          tipo TEXT NOT NULL,
          natureza TEXT NOT NULL,
          grupo_dre TEXT NOT NULL DEFAULT 'Não DRE',
          parent_id INTEGER,
          ativo INTEGER NOT NULL DEFAULT 1,
          ordem INTEGER NOT NULL DEFAULT 0,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          FOREIGN KEY (parent_id)
            REFERENCES financeiro_plano_contas (id)
            ON DELETE RESTRICT,
          CHECK (tipo IN ('Entrada', 'Saída', 'Neutro'))
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_plano_contas_parent
        ON financeiro_plano_contas (parent_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_plano_contas_ativo_tipo
        ON financeiro_plano_contas (ativo, tipo, ordem, nome COLLATE NOCASE)
      ''');
  }

  Future<void> _inserirPlanoContasFinanceiroPadrao(Database database) async {
    final agora = DateTime.now().toIso8601String();

    final contas = <Map<String, Object?>>[
      {
        'codigo': '1',
        'nome': 'Receitas',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': null,
        'ordem': 100,
      },
      {
        'codigo': '1.01',
        'nome': 'Serviços',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1',
        'ordem': 110,
      },
      {
        'codigo': '1.01.01',
        'nome': 'Polimento',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1.01',
        'ordem': 111,
      },
      {
        'codigo': '1.01.02',
        'nome': 'Higienização',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1.01',
        'ordem': 112,
      },
      {
        'codigo': '1.01.03',
        'nome': 'Insulfilm',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1.01',
        'ordem': 113,
      },
      {
        'codigo': '1.01.04',
        'nome': 'Vitrificação',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1.01',
        'ordem': 114,
      },
      {
        'codigo': '1.01.05',
        'nome': 'Lavação',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1.01',
        'ordem': 115,
      },
      {
        'codigo': '1.01.06',
        'nome': 'Pintura',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1.01',
        'ordem': 116,
      },
      {
        'codigo': '1.01.07',
        'nome': 'Revenda',
        'tipo': 'Entrada',
        'natureza': 'Receita operacional',
        'grupo_dre': 'Receita Bruta',
        'parent_codigo': '1.01',
        'ordem': 117,
      },
      {
        'codigo': '1.02',
        'nome': 'Deduções da receita',
        'tipo': 'Saída',
        'natureza': 'Dedução de receita',
        'grupo_dre': 'Deduções',
        'parent_codigo': '1',
        'ordem': 120,
      },
      {
        'codigo': '1.02.01',
        'nome': 'Estornos e cancelamentos',
        'tipo': 'Saída',
        'natureza': 'Dedução de receita',
        'grupo_dre': 'Deduções',
        'parent_codigo': '1.02',
        'ordem': 121,
      },
      {
        'codigo': '1.02.02',
        'nome': 'Descontos comerciais',
        'tipo': 'Saída',
        'natureza': 'Dedução de receita',
        'grupo_dre': 'Deduções',
        'parent_codigo': '1.02',
        'ordem': 122,
      },
      {
        'codigo': '1.02.03',
        'nome': 'Impostos sobre faturamento',
        'tipo': 'Saída',
        'natureza': 'Dedução de receita',
        'grupo_dre': 'Deduções',
        'parent_codigo': '1.02',
        'ordem': 123,
      },
      {
        'codigo': '1.99',
        'nome': 'Outras receitas',
        'tipo': 'Entrada',
        'natureza': 'Outras receitas',
        'grupo_dre': 'Outras Receitas',
        'parent_codigo': '1',
        'ordem': 190,
      },
      {
        'codigo': '1.99.01',
        'nome': 'Outras receitas',
        'tipo': 'Entrada',
        'natureza': 'Outras receitas',
        'grupo_dre': 'Outras Receitas',
        'parent_codigo': '1.99',
        'ordem': 191,
      },
      {
        'codigo': '2',
        'nome': 'Despesas',
        'tipo': 'Saída',
        'natureza': 'Despesa operacional',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': null,
        'ordem': 200,
      },
      {
        'codigo': '2.01',
        'nome': 'Colaboradores',
        'tipo': 'Saída',
        'natureza': 'Mão de obra',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2',
        'ordem': 210,
      },
      {
        'codigo': '2.01.01',
        'nome': 'Folha de pagamento',
        'tipo': 'Saída',
        'natureza': 'Mão de obra',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.01',
        'ordem': 211,
      },
      {
        'codigo': '2.01.02',
        'nome': 'Gastos pessoais do proprietário',
        'tipo': 'Saída',
        'natureza': 'Mão de obra',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.01',
        'ordem': 212,
      },
      {
        'codigo': '2.01.03',
        'nome': 'Encargos e benefícios',
        'tipo': 'Saída',
        'natureza': 'Mão de obra',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.01',
        'ordem': 213,
      },
      {
        'codigo': '2.02',
        'nome': 'Custo de venda',
        'tipo': 'Saída',
        'natureza': 'Custo variável',
        'grupo_dre': 'Custos Variáveis',
        'parent_codigo': '2',
        'ordem': 220,
      },
      {
        'codigo': '2.02.01',
        'nome': 'Taxas de cartão',
        'tipo': 'Saída',
        'natureza': 'Custo variável',
        'grupo_dre': 'Custos Variáveis',
        'parent_codigo': '2.02',
        'ordem': 221,
      },
      {
        'codigo': '2.02.02',
        'nome': 'Comissões',
        'tipo': 'Saída',
        'natureza': 'Custo variável',
        'grupo_dre': 'Custos Variáveis',
        'parent_codigo': '2.02',
        'ordem': 222,
      },
      {
        'codigo': '2.03',
        'nome': 'Materiais',
        'tipo': 'Saída',
        'natureza': 'Custo variável',
        'grupo_dre': 'Custos Variáveis',
        'parent_codigo': '2',
        'ordem': 230,
      },
      {
        'codigo': '2.03.01',
        'nome': 'Produtos consumidos em serviços',
        'tipo': 'Saída',
        'natureza': 'Custo de produto consumido',
        'grupo_dre': 'Custos Variáveis',
        'parent_codigo': '2.03',
        'ordem': 231,
      },
      {
        'codigo': '2.03.02',
        'nome': 'Materiais de consumo',
        'tipo': 'Saída',
        'natureza': 'Custo variável',
        'grupo_dre': 'Custos Variáveis',
        'parent_codigo': '2.03',
        'ordem': 232,
      },
      {
        'codigo': '2.04',
        'nome': 'Empresa',
        'tipo': 'Saída',
        'natureza': 'Despesa fixa',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2',
        'ordem': 240,
      },
      {
        'codigo': '2.04.01',
        'nome': 'Aluguel',
        'tipo': 'Saída',
        'natureza': 'Despesa fixa',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 241,
      },
      {
        'codigo': '2.04.02',
        'nome': 'Energia elétrica',
        'tipo': 'Saída',
        'natureza': 'Despesa fixa',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 242,
      },
      {
        'codigo': '2.04.03',
        'nome': 'Água',
        'tipo': 'Saída',
        'natureza': 'Despesa fixa',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 243,
      },
      {
        'codigo': '2.04.04',
        'nome': 'Internet e telefone',
        'tipo': 'Saída',
        'natureza': 'Despesa fixa',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 244,
      },
      {
        'codigo': '2.04.05',
        'nome': 'Contador',
        'tipo': 'Saída',
        'natureza': 'Despesa fixa',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 245,
      },
      {
        'codigo': '2.04.06',
        'nome': 'Impostos',
        'tipo': 'Saída',
        'natureza': 'Despesa variável',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 246,
      },
      {
        'codigo': '2.04.07',
        'nome': 'Combustível',
        'tipo': 'Saída',
        'natureza': 'Despesa variável',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 247,
      },
      {
        'codigo': '2.04.08',
        'nome': 'Manutenção',
        'tipo': 'Saída',
        'natureza': 'Despesa variável',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 248,
      },
      {
        'codigo': '2.04.09',
        'nome': 'Marketing',
        'tipo': 'Saída',
        'natureza': 'Despesa variável',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 249,
      },
      {
        'codigo': '2.04.10',
        'nome': 'Software e assinaturas',
        'tipo': 'Saída',
        'natureza': 'Despesa fixa',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 250,
      },
      {
        'codigo': '2.04.11',
        'nome': 'Limpeza',
        'tipo': 'Saída',
        'natureza': 'Despesa variável',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 251,
      },
      {
        'codigo': '2.04.12',
        'nome': 'Taxas e tributos operacionais',
        'tipo': 'Saída',
        'natureza': 'Despesa variável',
        'grupo_dre': 'Despesas Operacionais',
        'parent_codigo': '2.04',
        'ordem': 252,
      },
      {
        'codigo': '2.05',
        'nome': 'Despesas financeiras',
        'tipo': 'Saída',
        'natureza': 'Despesa financeira',
        'grupo_dre': 'Resultado Financeiro',
        'parent_codigo': '2',
        'ordem': 260,
      },
      {
        'codigo': '2.05.01',
        'nome': 'Juros e tarifas bancárias',
        'tipo': 'Saída',
        'natureza': 'Despesa financeira',
        'grupo_dre': 'Resultado Financeiro',
        'parent_codigo': '2.05',
        'ordem': 261,
      },
      {
        'codigo': '2.99',
        'nome': 'Outras despesas',
        'tipo': 'Saída',
        'natureza': 'Outras despesas',
        'grupo_dre': 'Outras Despesas',
        'parent_codigo': '2',
        'ordem': 290,
      },
      {
        'codigo': '2.99.01',
        'nome': 'Outras despesas',
        'tipo': 'Saída',
        'natureza': 'Outras despesas',
        'grupo_dre': 'Outras Despesas',
        'parent_codigo': '2.99',
        'ordem': 291,
      },
      {
        'codigo': '9',
        'nome': 'Movimentos sem efeito na DRE',
        'tipo': 'Neutro',
        'natureza': 'Movimento patrimonial',
        'grupo_dre': 'Não DRE',
        'parent_codigo': null,
        'ordem': 900,
      },
      {
        'codigo': '9.01',
        'nome': 'Transferência entre contas',
        'tipo': 'Neutro',
        'natureza': 'Transferência',
        'grupo_dre': 'Não DRE',
        'parent_codigo': '9',
        'ordem': 910,
      },
      {
        'codigo': '9.02',
        'nome': 'Empréstimos',
        'tipo': 'Neutro',
        'natureza': 'Empréstimo',
        'grupo_dre': 'Não DRE',
        'parent_codigo': '9',
        'ordem': 920,
      },
      {
        'codigo': '9.03',
        'nome': 'Aportes',
        'tipo': 'Neutro',
        'natureza': 'Aporte',
        'grupo_dre': 'Não DRE',
        'parent_codigo': '9',
        'ordem': 930,
      },
      {
        'codigo': '9.04',
        'nome': 'Retiradas e gastos pessoais',
        'tipo': 'Neutro',
        'natureza': 'Retirada',
        'grupo_dre': 'Não DRE',
        'parent_codigo': '9',
        'ordem': 940,
      },
      {
        'codigo': '9.05',
        'nome': 'Correção de caixa',
        'tipo': 'Neutro',
        'natureza': 'Ajuste de caixa',
        'grupo_dre': 'Não DRE',
        'parent_codigo': '9',
        'ordem': 950,
      },
      {
        'codigo': '9.06',
        'nome': 'Compra para estoque',
        'tipo': 'Saída',
        'natureza': 'Aquisição de estoque',
        'grupo_dre': 'Não DRE',
        'parent_codigo': '9',
        'ordem': 960,
      },
    ];

    for (final conta in contas) {
      final parentCodigo = conta['parent_codigo']?.toString();
      int? parentId;

      if (parentCodigo != null && parentCodigo.isNotEmpty) {
        parentId = await _idPlanoContaPorCodigo(database, parentCodigo);
      }

      await database.insert('financeiro_plano_contas', {
        'codigo': conta['codigo'],
        'nome': conta['nome'],
        'tipo': conta['tipo'],
        'natureza': conta['natureza'],
        'grupo_dre': conta['grupo_dre'],
        'parent_id': parentId,
        'ativo': 1,
        'ordem': conta['ordem'],
        'criado_em': agora,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _aplicarPlanoContasSimplificado(Database database) async {
    if (!await _tabelaExiste(database, 'financeiro_plano_contas')) {
      return;
    }

    // Mantém os códigos internos já usados por pagamentos, taxas,
    // transferências e histórico. A simplificação é visual/operacional.
    await _inserirPlanoContasFinanceiroPadrao(database);

    final agora = DateTime.now().toIso8601String();
    // Regra gerencial do proprietário:
    // 2.01.02 representa somente valores efetivamente pagos/gastos pelo
    // proprietário e entra no DRE. O valor mensal cadastrado em Mão de Obra
    // continua sendo apenas referência para precificação e não gera lançamento.
    await database.update(
      'financeiro_plano_contas',
      {
        'nome': 'Gastos pessoais do proprietário',
        'tipo': 'Saída',
        'natureza': 'Mão de obra',
        'grupo_dre': 'Despesas Operacionais',
        'ativo': 1,
        'atualizado_em': agora,
      },
      where: '''
        codigo = '2.01.02'
        AND nome IN (
          'Pró-labore',
          'Remuneração dos proprietários',
          'Gastos pessoais do proprietário'
        )
      ''',
    );

    // Mantemos também a retirada que NÃO afeta resultado, mas com um nome
    // explícito para evitar confundir com o gasto pessoal usado no DRE.
    await database.update(
      'financeiro_plano_contas',
      {'nome': 'Retirada do sócio (não entra no DRE)', 'atualizado_em': agora},
      where: '''
        codigo = '9.04'
        AND nome IN (
          'Retiradas e gastos pessoais',
          'Retirada dos sócios',
          'Retirada do sócio (não entra no DRE)'
        )
      ''',
    );

    Future<void> garantirConta({
      required String codigo,
      required String nome,
      required String tipo,
      required String natureza,
      required String grupoDre,
      required String parentCodigo,
      required int ordem,
    }) async {
      final parentId = await _idPlanoContaPorCodigo(database, parentCodigo);
      await database.insert('financeiro_plano_contas', {
        'codigo': codigo,
        'nome': nome,
        'tipo': tipo,
        'natureza': natureza,
        'grupo_dre': grupoDre,
        'parent_id': parentId,
        'ativo': 1,
        'ordem': ordem,
        'criado_em': agora,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Novas categorias resumidas para quem está começando.
    await garantirConta(
      codigo: '1.03',
      nome: 'Venda de produtos',
      tipo: 'Entrada',
      natureza: 'Receita operacional',
      grupoDre: 'Receita Bruta',
      parentCodigo: '1',
      ordem: 130,
    );

    await garantirConta(
      codigo: '2.04.13',
      nome: 'Água, energia e internet',
      tipo: 'Saída',
      natureza: 'Despesa fixa',
      grupoDre: 'Despesas Operacionais',
      parentCodigo: '2.04',
      ordem: 253,
    );

    // Os nomes canônicos do plano de contas fazem parte do contrato
    // interno da V27 e são preservados para schema, migrações e histórico.
    //
    // Versões iniciais desta simplificação chegaram a gravar nomes mais
    // amigáveis diretamente no banco. Se isso ocorreu, restauramos apenas
    // esses aliases exatos. Nomes personalizados pelo usuário são preservados.
    const nomesCanonicos = <String, Map<String, String>>{
      '2.01': {'alias': 'Equipe', 'canonico': 'Colaboradores'},
      '2.01.01': {'alias': 'Funcionários', 'canonico': 'Folha de pagamento'},
      '2.02': {'alias': 'Custos das vendas', 'canonico': 'Custo de venda'},
      '2.03': {'alias': 'Produtos e materiais', 'canonico': 'Materiais'},
      '2.03.01': {
        'alias': 'Produtos e materiais usados nos serviços',
        'canonico': 'Produtos consumidos em serviços',
      },
      '2.04': {'alias': 'Despesas da empresa', 'canonico': 'Empresa'},
      '2.04.05': {'alias': 'Contabilidade', 'canonico': 'Contador'},
      '2.04.07': {'alias': 'Combustível e veículos', 'canonico': 'Combustível'},
      '2.05.01': {
        'alias': 'Tarifas e juros bancários',
        'canonico': 'Juros e tarifas bancárias',
      },
      '9': {
        'alias': 'Não afeta o resultado',
        'canonico': 'Movimentos sem efeito na DRE',
      },
      '9.03': {'alias': 'Aporte dos sócios', 'canonico': 'Aportes'},
      '9.04': {
        'alias': 'Retirada dos sócios',
        'canonico': 'Retiradas e gastos pessoais',
      },
      '9.05': {'alias': 'Ajuste de saldo', 'canonico': 'Correção de caixa'},
    };

    for (final item in nomesCanonicos.entries) {
      await database.update(
        'financeiro_plano_contas',
        {'nome': item.value['canonico'], 'atualizado_em': agora},
        where: 'codigo = ? AND nome = ?',
        whereArgs: [item.key, item.value['alias']],
      );
    }

    // Serviços específicos já são detalhados pelas próprias OS.
    // Mantemos as contas no banco para preservar qualquer histórico antigo,
    // mas elas deixam de aparecer na operação diária.
    const codigosLegadosServicos = <String>[
      '1.01.01',
      '1.01.02',
      '1.01.03',
      '1.01.04',
      '1.01.05',
      '1.01.06',
      '1.01.07',
    ];

    for (final codigo in codigosLegadosServicos) {
      await database.update(
        'financeiro_plano_contas',
        {'ativo': 0, 'atualizado_em': agora},
        where: 'codigo = ?',
        whereArgs: [codigo],
      );
    }

    // Consolida categorias redundantes para deixar o uso inicial objetivo.
    // Os registros antigos continuam vinculados às contas históricas.
    const codigosConsolidados = <String>[
      '2.01.03',
      '2.03.02',
      '2.04.02',
      '2.04.03',
      '2.04.04',
      '2.04.11',
      '2.04.12',
    ];

    for (final codigo in codigosConsolidados) {
      await database.update(
        'financeiro_plano_contas',
        {'ativo': 0, 'atualizado_em': agora},
        where: 'codigo = ?',
        whereArgs: [codigo],
      );
    }

    // Garante que as categorias automáticas essenciais nunca desapareçam.
    const codigosEssenciais = <String>[
      '1.01',
      '1.02.01',
      '1.99.01',
      '2.02.01',
      '2.03.01',
      '2.99.01',
      '9.01',
      '9.06',
    ];

    for (final codigo in codigosEssenciais) {
      await database.update(
        'financeiro_plano_contas',
        {'ativo': 1, 'atualizado_em': agora},
        where: 'codigo = ?',
        whereArgs: [codigo],
      );
    }
  }

  Future<int?> _idPlanoContaPorCodigo(Database database, String codigo) async {
    final resultado = await database.query(
      'financeiro_plano_contas',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return (resultado.first['id'] as num?)?.toInt();
  }

  Future<void> _criarTabelaContasFinanceiras(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_contas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL UNIQUE,
          tipo TEXT NOT NULL DEFAULT 'Conta bancária',
          instituicao TEXT NOT NULL DEFAULT '',
          saldo_inicial REAL NOT NULL DEFAULT 0,
          data_saldo_inicial TEXT,
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          CHECK (tipo IN (
            'Dinheiro',
            'Conta bancária',
            'Carteira digital',
            'Maquininha',
            'Outro'
          ))
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_contas_ativo_nome
        ON financeiro_contas (ativo, nome COLLATE NOCASE)
      ''');
  }

  Future<void> _inserirContaFinanceiraPadrao(Database database) async {
    final agora = DateTime.now().toIso8601String();

    await database.insert('financeiro_contas', {
      'nome': 'Caixa / Dinheiro',
      'tipo': 'Dinheiro',
      'instituicao': '',
      'saldo_inicial': 0,
      'data_saldo_inicial': null,
      'observacoes': 'Conta padrão criada pelo Imperium.',
      'ativo': 1,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _criarTabelaFornecedores(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS fornecedores (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          documento TEXT NOT NULL DEFAULT '',
          telefone TEXT NOT NULL DEFAULT '',
          email TEXT NOT NULL DEFAULT '',
          endereco TEXT NOT NULL DEFAULT '',
          cidade TEXT NOT NULL DEFAULT '',
          estado TEXT NOT NULL DEFAULT '',
          categoria TEXT NOT NULL DEFAULT '',
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_fornecedores_ativo_nome
        ON fornecedores (ativo, nome COLLATE NOCASE)
      ''');
  }

  Future<void> _criarTabelaTransferenciasFinanceiras(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_transferencias (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          conta_origem_id INTEGER NOT NULL,
          conta_destino_id INTEGER NOT NULL,
          valor REAL NOT NULL,
          data TEXT NOT NULL,
          descricao TEXT NOT NULL DEFAULT '',
          observacoes TEXT NOT NULL DEFAULT '',
          criado_em TEXT NOT NULL,
          FOREIGN KEY (conta_origem_id)
            REFERENCES financeiro_contas (id)
            ON DELETE RESTRICT,
          FOREIGN KEY (conta_destino_id)
            REFERENCES financeiro_contas (id)
            ON DELETE RESTRICT,
          CHECK (valor > 0),
          CHECK (conta_origem_id <> conta_destino_id)
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_transferencias_data
        ON financeiro_transferencias (data)
      ''');
  }

  Future<void> _criarTabelaCustosFixos(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_custos_fixos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          valor_mensal REAL NOT NULL DEFAULT 0,
          categoria TEXT NOT NULL DEFAULT 'Despesa fixa',
          dia_vencimento INTEGER,
          plano_conta_id INTEGER,
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          FOREIGN KEY (plano_conta_id)
            REFERENCES financeiro_plano_contas (id)
            ON DELETE SET NULL,
          CHECK (valor_mensal >= 0),
          CHECK (dia_vencimento IS NULL OR (dia_vencimento >= 1 AND dia_vencimento <= 31)),
          CHECK (ativo IN (0, 1))
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_custos_fixos_ativo_nome
        ON financeiro_custos_fixos (ativo, nome COLLATE NOCASE)
      ''');
  }

  Future<void> _criarTabelaColaboradoresCusto(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_colaboradores_custo (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          funcao TEXT NOT NULL DEFAULT '',
          remuneracao_mensal REAL NOT NULL DEFAULT 0,
          encargos_mensais REAL NOT NULL DEFAULT 0,
          outros_custos_mensais REAL NOT NULL DEFAULT 0,
          horas_produtivas_mes REAL NOT NULL DEFAULT 0,
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          CHECK (remuneracao_mensal >= 0),
          CHECK (encargos_mensais >= 0),
          CHECK (outros_custos_mensais >= 0),
          CHECK (horas_produtivas_mes >= 0),
          CHECK (ativo IN (0, 1))
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_colaboradores_custo_ativo_nome
        ON financeiro_colaboradores_custo (ativo, nome COLLATE NOCASE)
      ''');
  }

  Future<void> _criarTabelaMaoObraOrdemServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_os_mao_obra (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          colaborador_custo_id INTEGER,
          descricao TEXT NOT NULL DEFAULT '',
          horas REAL NOT NULL,
          custo_hora_snapshot REAL NOT NULL DEFAULT 0,
          custo_total REAL NOT NULL DEFAULT 0,
          data TEXT NOT NULL,
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          cancelado_em TEXT,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE,
          FOREIGN KEY (colaborador_custo_id)
            REFERENCES financeiro_colaboradores_custo (id)
            ON DELETE SET NULL,
          CHECK (horas > 0),
          CHECK (custo_hora_snapshot >= 0),
          CHECK (custo_total >= 0),
          CHECK (ativo IN (0, 1))
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_os_mao_obra_os_id
        ON financeiro_os_mao_obra (ordem_servico_id, ativo)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_os_mao_obra_colaborador_id
        ON financeiro_os_mao_obra (colaborador_custo_id, ativo)
      ''');
  }

  Future<void> _criarTabelaRegrasTaxaCartao(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_regras_taxa (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          forma_pagamento TEXT NOT NULL,
          parcelas INTEGER NOT NULL DEFAULT 1,
          conta_id INTEGER,
          taxa_percentual REAL NOT NULL DEFAULT 0,
          taxa_fixa REAL NOT NULL DEFAULT 0,
          prazo_recebimento_dias INTEGER NOT NULL DEFAULT 0,
          prioridade INTEGER NOT NULL DEFAULT 0,
          repassar_cliente INTEGER NOT NULL DEFAULT 0,
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          FOREIGN KEY (conta_id)
            REFERENCES financeiro_contas (id)
            ON DELETE SET NULL,
          CHECK (forma_pagamento IN ('Cartão de crédito', 'Cartão de débito')),
          CHECK (parcelas >= 1 AND parcelas <= 48),
          CHECK (taxa_percentual >= 0 AND taxa_percentual <= 100),
          CHECK (taxa_fixa >= 0),
          CHECK (prazo_recebimento_dias >= 0),
          CHECK (repassar_cliente IN (0, 1)),
          CHECK (ativo IN (0, 1))
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_regras_taxa_busca
        ON financeiro_regras_taxa (
          ativo,
          forma_pagamento,
          parcelas,
          conta_id,
          prioridade
        )
      ''');
  }

  Future<void> _criarTabelaMetasFinanceiras(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS financeiro_metas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ano INTEGER NOT NULL,
          mes INTEGER NOT NULL,
          tipo TEXT NOT NULL,
          plano_conta_id INTEGER,
          valor_meta REAL NOT NULL DEFAULT 0,
          observacoes TEXT NOT NULL DEFAULT '',
          ativo INTEGER NOT NULL DEFAULT 1,
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          FOREIGN KEY (plano_conta_id)
            REFERENCES financeiro_plano_contas (id)
            ON DELETE SET NULL,
          CHECK (mes >= 1 AND mes <= 12),
          CHECK (tipo IN ('Receita', 'Despesa', 'Resultado')),
          CHECK (valor_meta >= 0),
          CHECK (ativo IN (0, 1))
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_financeiro_metas_periodo
        ON financeiro_metas (ano, mes, tipo, ativo)
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
          ordem_servico_id INTEGER,
          pagamento_id INTEGER,
          plano_conta_id INTEGER,
          conta_id INTEGER,
          fornecedor_id INTEGER,
          transferencia_id INTEGER,
          natureza TEXT NOT NULL DEFAULT 'Não classificado',
          origem TEXT NOT NULL DEFAULT 'Manual',
          status TEXT NOT NULL DEFAULT 'Realizado',
          data_competencia TEXT,
          data_vencimento TEXT,
          data_pagamento TEXT,
          numero_documento TEXT NOT NULL DEFAULT '',
          observacoes TEXT NOT NULL DEFAULT '',
          impacta_dre INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (cliente_id)
            REFERENCES clientes (id)
            ON DELETE SET NULL,
          FOREIGN KEY (agendamento_id)
            REFERENCES agendamentos (id)
            ON DELETE SET NULL,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE SET NULL,
          FOREIGN KEY (pagamento_id)
            REFERENCES ordem_servico_pagamentos (id)
            ON DELETE SET NULL,
          FOREIGN KEY (plano_conta_id)
            REFERENCES financeiro_plano_contas (id)
            ON DELETE SET NULL,
          FOREIGN KEY (conta_id)
            REFERENCES financeiro_contas (id)
            ON DELETE SET NULL,
          FOREIGN KEY (fornecedor_id)
            REFERENCES fornecedores (id)
            ON DELETE SET NULL,
          FOREIGN KEY (transferencia_id)
            REFERENCES financeiro_transferencias (id)
            ON DELETE CASCADE,
          CHECK (status IN ('Previsto', 'Realizado', 'Cancelado')),
          CHECK (impacta_dre IN (0, 1))
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

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_ordem_servico_id
        ON movimentos_financeiros (ordem_servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_pagamento_id
        ON movimentos_financeiros (pagamento_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_plano_conta_id
        ON movimentos_financeiros (plano_conta_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_conta_id
        ON movimentos_financeiros (conta_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_fornecedor_id
        ON movimentos_financeiros (fornecedor_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_transferencia_id
        ON movimentos_financeiros (transferencia_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_status_vencimento
        ON movimentos_financeiros (status, data_vencimento)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_competencia
        ON movimentos_financeiros (data_competencia)
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
          revisada_em TEXT,
          motivo_ultima_revisao TEXT NOT NULL DEFAULT '',
          quantidade_revisoes INTEGER NOT NULL DEFAULT 0,
          assinatura_desatualizada INTEGER NOT NULL DEFAULT 0,
          status_pagamento TEXT NOT NULL DEFAULT 'Pendente',
          valor_recebido REAL NOT NULL DEFAULT 0,
          vencimento_pagamento TEXT,
          pagamento_atualizado_em TEXT,
          desconto_negociacao REAL NOT NULL DEFAULT 0,
          acrescimo_negociacao REAL NOT NULL DEFAULT 0,
          juros_parcelamento REAL NOT NULL DEFAULT 0,
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

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_status_pagamento
        ON ordens_servico (status_pagamento)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_vencimento_pagamento
        ON ordens_servico (vencimento_pagamento)
      ''');
  }

  Future<void> _criarTabelaRevisoesOrdemServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_revisoes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          numero_revisao INTEGER NOT NULL,
          tipo TEXT NOT NULL DEFAULT 'Correcao administrativa',
          motivo TEXT NOT NULL,
          dados_anteriores_json TEXT NOT NULL,
          dados_novos_json TEXT NOT NULL,
          criado_em TEXT NOT NULL,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE,
          UNIQUE (ordem_servico_id, numero_revisao)
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_revisoes_ordem_servico_id
        ON ordem_servico_revisoes (ordem_servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_revisoes_criado_em
        ON ordem_servico_revisoes (criado_em)
      ''');
  }

  Future<void> _criarTabelaAjustesFinanceirosOrdemServico(
    Database database,
  ) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_ajustes_financeiros (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          tipo TEXT NOT NULL,
          valor REAL NOT NULL,
          motivo TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'Ativo',
          origem TEXT NOT NULL DEFAULT 'Manual',
          regra_taxa_id INTEGER,
          pagamento_id INTEGER,
          criado_em TEXT NOT NULL,
          cancelado_em TEXT,
          motivo_cancelamento TEXT NOT NULL DEFAULT '',
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE,
          FOREIGN KEY (regra_taxa_id)
            REFERENCES financeiro_regras_taxa (id)
            ON DELETE SET NULL,
          FOREIGN KEY (pagamento_id)
            REFERENCES ordem_servico_pagamentos (id)
            ON DELETE SET NULL,
          CHECK (tipo IN ('Desconto', 'Acréscimo', 'Juros')),
          CHECK (status IN ('Ativo', 'Cancelado')),
          CHECK (valor > 0)
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_ajustes_financeiros_os_id
        ON ordem_servico_ajustes_financeiros (ordem_servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_ajustes_financeiros_status
        ON ordem_servico_ajustes_financeiros (status)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_ajustes_financeiros_pagamento
        ON ordem_servico_ajustes_financeiros (pagamento_id, status)
      ''');
  }

  Future<void> _criarTabelaPagamentosOrdemServico(Database database) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS ordem_servico_pagamentos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ordem_servico_id INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'Pago',
          valor REAL NOT NULL DEFAULT 0,
          forma_pagamento TEXT NOT NULL DEFAULT '',
          data_pagamento TEXT,
          parcela_numero INTEGER,
          total_parcelas INTEGER,
          vencimento TEXT,
          comprovante_caminho TEXT,
          observacoes TEXT NOT NULL DEFAULT '',
          taxa_percentual REAL,
          taxa_operacao REAL NOT NULL DEFAULT 0,
          valor_liquido REAL NOT NULL DEFAULT 0,
          regra_taxa_id INTEGER,
          parcelas_taxa INTEGER NOT NULL DEFAULT 1,
          estornado_em TEXT,
          motivo_estorno TEXT NOT NULL DEFAULT '',
          criado_em TEXT NOT NULL,
          atualizado_em TEXT NOT NULL,
          FOREIGN KEY (ordem_servico_id)
            REFERENCES ordens_servico (id)
            ON DELETE CASCADE,
          FOREIGN KEY (regra_taxa_id)
            REFERENCES financeiro_regras_taxa (id)
            ON DELETE SET NULL,
          CHECK (valor >= 0),
          CHECK (taxa_percentual IS NULL OR (taxa_percentual >= 0 AND taxa_percentual <= 100)),
          CHECK (taxa_operacao >= 0 AND taxa_operacao <= valor),
          CHECK (valor_liquido >= 0 AND valor_liquido <= valor),
          CHECK (parcelas_taxa >= 1 AND parcelas_taxa <= 48),
          CHECK (status IN ('Pendente', 'Pago', 'Estornado', 'Cancelado')),
          CHECK (parcela_numero IS NULL OR parcela_numero > 0),
          CHECK (total_parcelas IS NULL OR total_parcelas > 0)
        )
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_pagamentos_ordem_servico_id
        ON ordem_servico_pagamentos (ordem_servico_id)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_pagamentos_status
        ON ordem_servico_pagamentos (status)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_pagamentos_vencimento
        ON ordem_servico_pagamentos (vencimento)
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

  Future<void> _atualizarParaVersao21(Database database) async {
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'revisada_em',
      definicao: 'TEXT',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'motivo_ultima_revisao',
      definicao: "TEXT NOT NULL DEFAULT ''",
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'quantidade_revisoes',
      definicao: 'INTEGER NOT NULL DEFAULT 0',
    );

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'assinatura_desatualizada',
      definicao: 'INTEGER NOT NULL DEFAULT 0',
    );

    await _criarTabelaRevisoesOrdemServico(database);

    await database.execute('''
        UPDATE ordens_servico
        SET
          motivo_ultima_revisao =
            COALESCE(motivo_ultima_revisao, ''),
          quantidade_revisoes =
            COALESCE(quantidade_revisoes, 0),
          assinatura_desatualizada =
            COALESCE(assinatura_desatualizada, 0)
      ''');
  }

  Future<void> _atualizarParaVersao22(Database database) async {
    // A tabela de regras já precisa existir porque a definição atual de
    // pagamentos possui uma FK opcional para ela. Em bancos antigos ela fica
    // vazia até a migração financeira da v26.
    await _criarTabelaRegrasTaxaCartao(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'status_pagamento',
      definicao: "TEXT NOT NULL DEFAULT 'Pendente'",
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'valor_recebido',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'vencimento_pagamento',
      definicao: 'TEXT',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'pagamento_atualizado_em',
      definicao: 'TEXT',
    );

    await _criarTabelaPagamentosOrdemServico(database);

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_status_pagamento
        ON ordens_servico (status_pagamento)
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_ordens_servico_vencimento_pagamento
        ON ordens_servico (vencimento_pagamento)
      ''');

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'movimentos_financeiros',
      coluna: 'ordem_servico_id',
      definicao: 'INTEGER REFERENCES ordens_servico (id) ON DELETE SET NULL',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'movimentos_financeiros',
      coluna: 'pagamento_id',
      definicao:
          'INTEGER REFERENCES ordem_servico_pagamentos (id) ON DELETE SET NULL',
    );

    if (await _tabelaExiste(database, 'movimentos_financeiros')) {
      await database.execute('''
          CREATE INDEX IF NOT EXISTS
          idx_movimentos_ordem_servico_id
          ON movimentos_financeiros (ordem_servico_id)
        ''');
      await database.execute('''
          CREATE INDEX IF NOT EXISTS
          idx_movimentos_pagamento_id
          ON movimentos_financeiros (pagamento_id)
        ''');
    }

    final agora = DateTime.now().toIso8601String();

    await database.execute('''
        UPDATE ordens_servico
        SET
          valor_recebido = CASE
            WHEN LOWER(status) = 'finalizada'
              AND COALESCE(lancado_financeiro, 0) = 1
            THEN MAX(COALESCE(valor_total, 0) - COALESCE(desconto, 0), 0)
            ELSE COALESCE(valor_recebido, 0)
          END,
          status_pagamento = CASE
            WHEN LOWER(status) = 'cancelada' THEN 'Cancelado'
            WHEN LOWER(status) = 'finalizada'
              AND MAX(COALESCE(valor_total, 0) - COALESCE(desconto, 0), 0) = 0
              THEN 'Pago'
            WHEN LOWER(status) = 'finalizada'
              AND COALESCE(lancado_financeiro, 0) = 1
              THEN 'Pago'
            ELSE COALESCE(NULLIF(TRIM(status_pagamento), ''), 'Pendente')
          END,
          pagamento_atualizado_em = CASE
            WHEN LOWER(status) = 'finalizada'
              THEN COALESCE(
                pagamento_atualizado_em,
                data_finalizacao,
                data_inicio,
                data_abertura,
                '$agora'
              )
            ELSE pagamento_atualizado_em
          END
      ''');

    await database.execute('''
        INSERT INTO ordem_servico_pagamentos (
          ordem_servico_id,
          status,
          valor,
          forma_pagamento,
          data_pagamento,
          observacoes,
          criado_em,
          atualizado_em
        )
        SELECT
          os.id,
          'Pago',
          MAX(COALESCE(os.valor_total, 0) - COALESCE(os.desconto, 0), 0),
          CASE
            WHEN TRIM(COALESCE(os.forma_pagamento, '')) = ''
              THEN 'Não informado'
            ELSE os.forma_pagamento
          END,
          COALESCE(os.data_finalizacao, os.data_inicio, os.data_abertura, '$agora'),
          'Pagamento migrado automaticamente da versão anterior.',
          COALESCE(os.data_finalizacao, os.data_inicio, os.data_abertura, '$agora'),
          '$agora'
        FROM ordens_servico os
        WHERE LOWER(os.status) = 'finalizada'
          AND COALESCE(os.lancado_financeiro, 0) = 1
          AND MAX(COALESCE(os.valor_total, 0) - COALESCE(os.desconto, 0), 0) > 0
          AND NOT EXISTS (
            SELECT 1
            FROM ordem_servico_pagamentos p
            WHERE p.ordem_servico_id = os.id
          )
      ''');

    if (await _tabelaExiste(database, 'movimentos_financeiros')) {
      await database.execute('''
          UPDATE movimentos_financeiros
          SET ordem_servico_id = (
            SELECT os.id
            FROM ordens_servico os
            WHERE movimentos_financeiros.descricao =
              'Ordem de Serviço finalizada: ' || os.numero
            LIMIT 1
          )
          WHERE ordem_servico_id IS NULL
            AND LOWER(tipo) = 'entrada'
            AND descricao LIKE 'Ordem de Serviço finalizada:%'
        ''');
      await database.execute('''
          UPDATE movimentos_financeiros
          SET pagamento_id = (
            SELECT p.id
            FROM ordem_servico_pagamentos p
            WHERE p.ordem_servico_id = movimentos_financeiros.ordem_servico_id
              AND p.status = 'Pago'
            ORDER BY p.id ASC
            LIMIT 1
          )
          WHERE pagamento_id IS NULL
            AND ordem_servico_id IS NOT NULL
            AND LOWER(tipo) = 'entrada'
        ''');
    }
  }

  Future<void> _atualizarParaVersao23(Database database) async {
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'desconto_negociacao',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'acrescimo_negociacao',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordens_servico',
      coluna: 'juros_parcelamento',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await _criarTabelaAjustesFinanceirosOrdemServico(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_pagamentos',
      coluna: 'taxa_percentual',
      definicao: 'REAL',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_pagamentos',
      coluna: 'taxa_operacao',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_pagamentos',
      coluna: 'valor_liquido',
      definicao: 'REAL NOT NULL DEFAULT 0',
    );

    await database.execute('''
        UPDATE ordens_servico
        SET
          desconto_negociacao = COALESCE(desconto_negociacao, 0),
          acrescimo_negociacao = COALESCE(acrescimo_negociacao, 0),
          juros_parcelamento = COALESCE(juros_parcelamento, 0)
      ''');

    if (await _tabelaExiste(database, 'ordem_servico_pagamentos')) {
      await database.execute('''
          UPDATE ordem_servico_pagamentos
          SET
            taxa_operacao = COALESCE(taxa_operacao, 0),
            valor_liquido = CASE
              WHEN status = 'Pago'
                THEN MAX(COALESCE(valor, 0) - COALESCE(taxa_operacao, 0), 0)
              ELSE 0
            END
        ''');
    }
  }

  Future<void> _atualizarParaVersao24(Database database) async {
    await _criarTabelaPlanoContasFinanceiro(database);
    await _inserirPlanoContasFinanceiroPadrao(database);
    await _criarTabelaContasFinanceiras(database);
    await _inserirContaFinanceiraPadrao(database);
    await _criarTabelaFornecedores(database);
    await _criarTabelaTransferenciasFinanceiras(database);

    final novasColunas = <String, String>{
      'plano_conta_id':
          'INTEGER REFERENCES financeiro_plano_contas (id) ON DELETE SET NULL',
      'conta_id':
          'INTEGER REFERENCES financeiro_contas (id) ON DELETE SET NULL',
      'fornecedor_id':
          'INTEGER REFERENCES fornecedores (id) ON DELETE SET NULL',
      'transferencia_id':
          'INTEGER REFERENCES financeiro_transferencias (id) ON DELETE CASCADE',
      'natureza': "TEXT NOT NULL DEFAULT 'Não classificado'",
      'origem': "TEXT NOT NULL DEFAULT 'Manual'",
      'status': "TEXT NOT NULL DEFAULT 'Realizado'",
      'data_competencia': 'TEXT',
      'data_vencimento': 'TEXT',
      'data_pagamento': 'TEXT',
      'numero_documento': "TEXT NOT NULL DEFAULT ''",
      'observacoes': "TEXT NOT NULL DEFAULT ''",
      'impacta_dre': 'INTEGER NOT NULL DEFAULT 1',
    };

    for (final item in novasColunas.entries) {
      await _adicionarColunaSeNecessario(
        database: database,
        tabela: 'movimentos_financeiros',
        coluna: item.key,
        definicao: item.value,
      );
    }

    if (!await _tabelaExiste(database, 'movimentos_financeiros')) {
      await _criarTabelaMovimentosFinanceiros(database);
      return;
    }

    await database.execute('''
        UPDATE movimentos_financeiros
        SET
          status = COALESCE(NULLIF(TRIM(status), ''), 'Realizado'),
          data_competencia = COALESCE(data_competencia, data),
          data_pagamento = CASE
            WHEN COALESCE(NULLIF(TRIM(status), ''), 'Realizado') = 'Realizado'
              THEN COALESCE(data_pagamento, data)
            ELSE data_pagamento
          END,
          origem = CASE
            WHEN pagamento_id IS NOT NULL
              AND LOWER(descricao) LIKE 'taxa da maquininha%'
              THEN 'Taxa de pagamento'
            WHEN pagamento_id IS NOT NULL
              AND LOWER(descricao) LIKE 'estorno de pagamento%'
              THEN 'Estorno de pagamento'
            WHEN pagamento_id IS NOT NULL
              THEN 'Pagamento de OS'
            WHEN ordem_servico_id IS NOT NULL
              THEN 'Ordem de Serviço'
            ELSE COALESCE(NULLIF(TRIM(origem), ''), 'Manual legado')
          END,
          numero_documento = COALESCE(numero_documento, ''),
          observacoes = COALESCE(observacoes, '')
      ''');

    await database.execute('''
        UPDATE movimentos_financeiros
        SET plano_conta_id = CASE
          WHEN LOWER(descricao) LIKE 'taxa da maquininha%'
            THEN (SELECT id FROM financeiro_plano_contas WHERE codigo = '2.02.01')
          WHEN LOWER(descricao) LIKE 'estorno de pagamento%'
            THEN (SELECT id FROM financeiro_plano_contas WHERE codigo = '1.02.01')
          WHEN LOWER(descricao) LIKE '%transfer%'
            THEN (SELECT id FROM financeiro_plano_contas WHERE codigo = '9.01')
          WHEN LOWER(tipo) = 'entrada'
            AND (
              LOWER(descricao) LIKE 'pagamento da os %'
              OR LOWER(descricao) LIKE 'ordem de serviço finalizada:%'
            )
            THEN (SELECT id FROM financeiro_plano_contas WHERE codigo = '1.01')
          WHEN LOWER(tipo) = 'entrada'
            THEN (SELECT id FROM financeiro_plano_contas WHERE codigo = '1.99.01')
          ELSE (SELECT id FROM financeiro_plano_contas WHERE codigo = '2.99.01')
        END
        WHERE plano_conta_id IS NULL
      ''');

    await database.execute('''
        UPDATE movimentos_financeiros
        SET
          natureza = COALESCE(
            (
              SELECT pc.natureza
              FROM financeiro_plano_contas pc
              WHERE pc.id = movimentos_financeiros.plano_conta_id
            ),
            COALESCE(NULLIF(TRIM(natureza), ''), 'Não classificado')
          ),
          impacta_dre = CASE
            WHEN COALESCE(
              (
                SELECT pc.grupo_dre
                FROM financeiro_plano_contas pc
                WHERE pc.id = movimentos_financeiros.plano_conta_id
              ),
              'Não DRE'
            ) = 'Não DRE'
              THEN 0
            ELSE 1
          END
      ''');

    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_plano_conta_id
        ON movimentos_financeiros (plano_conta_id)
      ''');
    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_conta_id
        ON movimentos_financeiros (conta_id)
      ''');
    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_fornecedor_id
        ON movimentos_financeiros (fornecedor_id)
      ''');
    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_transferencia_id
        ON movimentos_financeiros (transferencia_id)
      ''');
    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_status_vencimento
        ON movimentos_financeiros (status, data_vencimento)
      ''');
    await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_movimentos_competencia
        ON movimentos_financeiros (data_competencia)
      ''');
  }

  Future<void> _atualizarParaVersao25(Database database) async {
    await _criarTabelaCustosFixos(database);
    await _criarTabelaColaboradoresCusto(database);
    await _criarTabelaMaoObraOrdemServico(database);
  }

  Future<void> _atualizarParaVersao26(Database database) async {
    await _criarTabelaPlanoContasFinanceiro(database);
    await _inserirPlanoContasFinanceiroPadrao(database);
    await _criarTabelaRegrasTaxaCartao(database);
    await _criarTabelaMetasFinanceiras(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_pagamentos',
      coluna: 'regra_taxa_id',
      definicao:
          'INTEGER REFERENCES financeiro_regras_taxa (id) ON DELETE SET NULL',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_pagamentos',
      coluna: 'parcelas_taxa',
      definicao: 'INTEGER NOT NULL DEFAULT 1',
    );

    if (await _tabelaExiste(database, 'financeiro_plano_contas')) {
      await database.execute('''
        UPDATE financeiro_plano_contas
        SET
          nome = 'Produtos consumidos em serviços',
          natureza = 'Custo de produto consumido',
          atualizado_em = '${DateTime.now().toIso8601String()}'
        WHERE codigo = '2.03.01'
          AND nome = 'Produtos'
      ''');
    }

    if (await _tabelaExiste(database, 'movimentos_financeiros')) {
      await database.execute('''
        UPDATE movimentos_financeiros
        SET impacta_dre = 0
        WHERE plano_conta_id IN (
          SELECT id
          FROM financeiro_plano_contas
          WHERE grupo_dre = 'Não DRE'
        )
      ''');
    }
  }

  Future<void> _atualizarParaVersao27(Database database) async {
    await _criarTabelaRegrasTaxaCartao(database);

    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'financeiro_regras_taxa',
      coluna: 'repassar_cliente',
      definicao: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_ajustes_financeiros',
      coluna: 'origem',
      definicao: "TEXT NOT NULL DEFAULT 'Manual'",
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_ajustes_financeiros',
      coluna: 'regra_taxa_id',
      definicao:
          'INTEGER REFERENCES financeiro_regras_taxa (id) ON DELETE SET NULL',
    );
    await _adicionarColunaSeNecessario(
      database: database,
      tabela: 'ordem_servico_ajustes_financeiros',
      coluna: 'pagamento_id',
      definicao:
          'INTEGER REFERENCES ordem_servico_pagamentos (id) ON DELETE SET NULL',
    );

    if (await _tabelaExiste(database, 'ordem_servico_ajustes_financeiros')) {
      await database.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_os_ajustes_financeiros_pagamento
        ON ordem_servico_ajustes_financeiros (pagamento_id, status)
      ''');
    }
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
