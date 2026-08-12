import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/plano_conta_financeiro.dart';

enum PlanoContaSecao { receita, custoVenda, despesaEmpresa, naoAfetaResultado }

class PlanoContasRepository {
  static const Set<String> codigosAutomaticos = <String>{
    '1.01',
    '1.02.01',
    '2.02.01',
    '2.03.01',
    '9.01',
    '9.04',
    '9.06',
  };

  static const Set<String> codigosProtegidos = <String>{
    '1',
    '1.01',
    '1.02',
    '1.02.01',
    '1.99',
    '1.99.01',
    '2',
    '2.01',
    '2.01.02',
    '2.02',
    '2.02.01',
    '2.03',
    '2.03.01',
    '2.04',
    '2.05',
    '2.99',
    '2.99.01',
    '9',
    '9.01',
    '9.04',
    '9.06',
  };

  Future<List<PlanoContaFinanceiro>> listar({
    bool incluirInativos = false,
  }) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'financeiro_plano_contas',
      where: incluirInativos ? null : 'ativo = 1',
      orderBy: 'ordem ASC, codigo ASC, nome COLLATE NOCASE ASC',
    );

    return resultado
        .map(
          (item) =>
              PlanoContaFinanceiro.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  /// Compatibilidade com o motor financeiro já existente.
  /// Retorna somente categorias ativas que podem receber lançamentos
  /// diretamente, sem filhos ativos.
  Future<List<PlanoContaFinanceiro>> listarFolhasParaTipo(String tipo) async {
    final database = await AppDatabase.instance.database;
    final tipoLimpo = tipo.trim();

    final resultado = await database.rawQuery(
      '''
      SELECT pc.*
      FROM financeiro_plano_contas pc
      WHERE pc.ativo = 1
        AND LOWER(pc.tipo) = LOWER(?)
        AND NOT EXISTS (
          SELECT 1
          FROM financeiro_plano_contas filho
          WHERE filho.parent_id = pc.id
            AND filho.ativo = 1
        )
      ORDER BY pc.ordem ASC, pc.codigo ASC, pc.nome COLLATE NOCASE ASC
      ''',
      [tipoLimpo],
    );

    return resultado
        .map(
          (item) =>
              PlanoContaFinanceiro.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<PlanoContaFinanceiro?> buscarPorId(int id) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'financeiro_plano_contas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return PlanoContaFinanceiro.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Future<int> inserir(PlanoContaFinanceiro conta) async {
    final database = await AppDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final dados = conta.toMap(incluirId: false)
      ..['criado_em'] = conta.criadoEm.isEmpty ? agora : conta.criadoEm
      ..['atualizado_em'] = agora;

    return database.insert(
      'financeiro_plano_contas',
      dados,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> atualizar(PlanoContaFinanceiro conta) async {
    final id = conta.id;
    if (id == null) {
      throw ArgumentError('Categoria financeira sem ID.');
    }

    final database = await AppDatabase.instance.database;
    final atual = await buscarPorId(id);
    if (atual == null) {
      throw StateError('Categoria financeira não encontrada.');
    }

    final dados = conta.toMap(incluirId: false)
      ..remove('criado_em')
      ..['atualizado_em'] = DateTime.now().toIso8601String();

    if (codigosProtegidos.contains(atual.codigo)) {
      dados['codigo'] = atual.codigo;
      dados['tipo'] = atual.tipo;
      dados['natureza'] = atual.natureza;
      dados['grupo_dre'] = atual.grupoDre;
      dados['parent_id'] = atual.parentId;
      dados['ativo'] = 1;
    } else if (await possuiMovimentacoes(id)) {
      // Uma categoria já usada pode mudar de nome, mas não deve mudar
      // sua classificação histórica.
      dados['codigo'] = atual.codigo;
      dados['tipo'] = atual.tipo;
      dados['natureza'] = atual.natureza;
      dados['grupo_dre'] = atual.grupoDre;
      dados['parent_id'] = atual.parentId;
    }

    return database.update(
      'financeiro_plano_contas',
      dados,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<PlanoContaFinanceiro> criarCategoriaSimplificada({
    required String nome,
    required PlanoContaSecao secao,
  }) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.length < 3) {
      throw ArgumentError('Informe um nome com pelo menos 3 caracteres.');
    }

    final database = await AppDatabase.instance.database;
    final configuracao = _configuracaoSecao(secao);
    final parentId = await _idPorCodigo(database, configuracao.parentCodigo);
    if (parentId == null) {
      throw StateError(
        'A categoria base ${configuracao.parentCodigo} não foi encontrada.',
      );
    }

    final codigo = await _gerarCodigoPersonalizado(
      database,
      configuracao.prefixoCodigo,
    );
    final agora = DateTime.now().toIso8601String();

    final id = await database.insert('financeiro_plano_contas', {
      'codigo': codigo,
      'nome': nomeLimpo,
      'tipo': configuracao.tipo,
      'natureza': configuracao.natureza,
      'grupo_dre': configuracao.grupoDre,
      'parent_id': parentId,
      'ativo': 1,
      'ordem': configuracao.ordemBase + _numeroSufixo(codigo),
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    final criado = await buscarPorId(id);
    if (criado == null) {
      throw StateError('Não foi possível recuperar a categoria criada.');
    }
    return criado;
  }

  Future<void> renomear({required int id, required String nome}) async {
    final conta = await buscarPorId(id);
    if (conta == null) {
      throw StateError('Categoria financeira não encontrada.');
    }

    final nomeLimpo = nome.trim();
    if (nomeLimpo.length < 3) {
      throw ArgumentError('Informe um nome com pelo menos 3 caracteres.');
    }

    final database = await AppDatabase.instance.database;
    await database.update(
      'financeiro_plano_contas',
      {'nome': nomeLimpo, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> alterarAtivo({required int id, required bool ativo}) async {
    final conta = await buscarPorId(id);
    if (conta == null) {
      throw StateError('Categoria financeira não encontrada.');
    }

    if (!ativo && codigosProtegidos.contains(conta.codigo)) {
      throw StateError(
        'Esta categoria é usada automaticamente pelo Imperium e não pode ser desativada.',
      );
    }

    final database = await AppDatabase.instance.database;
    await database.update(
      'financeiro_plano_contas',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluir(int id) async {
    final conta = await buscarPorId(id);
    if (conta == null) return 0;

    if (codigosProtegidos.contains(conta.codigo)) {
      throw StateError(
        'Esta categoria pertence ao sistema e não pode ser excluída.',
      );
    }

    if (await possuiMovimentacoes(id)) {
      throw StateError(
        'Esta categoria já possui lançamentos. Desative-a em vez de excluir.',
      );
    }

    final database = await AppDatabase.instance.database;
    final filhos =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM financeiro_plano_contas WHERE parent_id = ?',
            [id],
          ),
        ) ??
        0;
    if (filhos > 0) {
      throw StateError(
        'Esta categoria possui subcategorias e não pode ser excluída.',
      );
    }

    return database.delete(
      'financeiro_plano_contas',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> possuiMovimentacoes(int id) async {
    final database = await AppDatabase.instance.database;
    final total =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM movimentos_financeiros WHERE plano_conta_id = ?',
            [id],
          ),
        ) ??
        0;
    return total > 0;
  }

  bool ehAutomatica(PlanoContaFinanceiro conta) {
    return codigosAutomaticos.contains(conta.codigo);
  }

  bool ehProtegida(PlanoContaFinanceiro conta) {
    return codigosProtegidos.contains(conta.codigo);
  }

  String nomeExibicao(PlanoContaFinanceiro conta) {
    final nome = conta.nome.trim();

    switch (conta.codigo) {
      case '2.01.01':
        return nome == 'Folha de pagamento' ? 'Funcionários' : nome;
      case '2.01.02':
        return 'Gastos pessoais do proprietário';
      case '2.03.01':
        return nome == 'Produtos consumidos em serviços'
            ? 'Produtos e materiais usados nos serviços'
            : nome;
      case '2.04.05':
        return nome == 'Contador' ? 'Contabilidade' : nome;
      case '2.04.07':
        return nome == 'Combustível' ? 'Combustível e veículos' : nome;
      case '2.05.01':
        return nome == 'Juros e tarifas bancárias'
            ? 'Tarifas e juros bancários'
            : nome;
      case '9.03':
        return nome == 'Aportes' ? 'Aporte dos sócios' : nome;
      case '9.04':
        return 'Retirada do sócio (não entra no DRE)';
      case '9.05':
        return nome == 'Correção de caixa' ? 'Ajuste de saldo' : nome;
      default:
        return nome;
    }
  }

  String descricaoUso(PlanoContaFinanceiro conta) {
    switch (conta.codigo) {
      case '1.01':
        return 'Receitas das Ordens de Serviço. O Imperium classifica automaticamente.';
      case '1.02.01':
        return 'Estornos e cancelamentos de recebimentos. Gerado automaticamente quando necessário.';
      case '1.02.02':
        return 'Descontos comerciais concedidos ao cliente.';
      case '1.02.03':
        return 'Impostos diretamente relacionados ao faturamento.';
      case '1.03':
        return 'Receitas obtidas com venda avulsa de produtos.';
      case '1.99.01':
        return 'Receitas que não se encaixam nas categorias principais.';
      case '2.01.01':
        return 'Salários e custos recorrentes da equipe.';
      case '2.01.02':
        return 'Valores efetivamente pagos ou gastos pelo proprietário. '
            'Entram nas despesas da DRE e podem ser detalhados por lançamento.';
      case '2.02.01':
        return 'Taxas das maquininhas de cartão. O Imperium lança automaticamente.';
      case '2.02.02':
        return 'Comissões pagas sobre vendas ou serviços.';
      case '2.03.01':
        return 'Custo dos produtos consumidos nas OS, calculado pelo estoque.';
      case '2.04.01':
        return 'Aluguel do espaço utilizado pela empresa.';
      case '2.04.05':
        return 'Contabilidade e serviços contábeis.';
      case '2.04.06':
        return 'Impostos e obrigações da empresa não ligados diretamente ao faturamento.';
      case '2.04.07':
        return 'Combustível e gastos com veículos usados pela empresa.';
      case '2.04.08':
        return 'Manutenção de equipamentos, instalações ou veículos.';
      case '2.04.09':
        return 'Anúncios, divulgação e ações de marketing.';
      case '2.04.10':
        return 'Aplicativos, sistemas e assinaturas usados pela empresa.';
      case '2.04.13':
        return 'Água, energia elétrica, internet e telefone.';
      case '2.05.01':
        return 'Tarifas bancárias, juros e outros custos financeiros.';
      case '2.99.01':
        return 'Despesas que não se encaixam nas categorias principais.';
      case '9.01':
        return 'Transferências entre suas próprias contas. Não alteram o resultado.';
      case '9.02':
        return 'Entrada ou saída de recursos de empréstimos. Não é receita nem despesa operacional.';
      case '9.03':
        return 'Dinheiro colocado pelos sócios na empresa. Não é faturamento.';
      case '9.04':
        return 'Use somente quando a retirada não deve reduzir o resultado '
            'da empresa. Esta categoria fica fora da DRE.';
      case '9.05':
        return 'Correções manuais para ajustar um saldo ao valor real.';
      case '9.06':
        return 'Compra de mercadoria para estoque. O custo entra na DRE quando o produto é consumido.';
      default:
        if (conta.grupoDre == 'Custos Variáveis') {
          return 'Custo ligado diretamente à venda ou execução dos serviços.';
        }
        if (conta.grupoDre == 'Não DRE') {
          return 'Movimentação de caixa que não altera lucro ou prejuízo.';
        }
        if (conta.tipo == 'Entrada') {
          return 'Categoria personalizada de receita.';
        }
        return 'Categoria personalizada de despesa.';
    }
  }

  String tituloSecao(PlanoContaFinanceiro conta) {
    if (conta.grupoDre == 'Não DRE') {
      return 'Não afeta o resultado';
    }
    if (conta.grupoDre == 'Custos Variáveis') {
      return 'Custos das vendas';
    }
    if (conta.grupoDre == 'Deduções' ||
        conta.grupoDre == 'Receita Bruta' ||
        conta.grupoDre == 'Outras Receitas') {
      return 'Receitas e deduções';
    }
    return 'Despesas da empresa';
  }

  _SecaoConfig _configuracaoSecao(PlanoContaSecao secao) {
    switch (secao) {
      case PlanoContaSecao.receita:
        return const _SecaoConfig(
          parentCodigo: '1.99',
          prefixoCodigo: '1.99.9',
          tipo: 'Entrada',
          natureza: 'Outras receitas',
          grupoDre: 'Outras Receitas',
          ordemBase: 195,
        );
      case PlanoContaSecao.custoVenda:
        return const _SecaoConfig(
          parentCodigo: '2.02',
          prefixoCodigo: '2.02.9',
          tipo: 'Saída',
          natureza: 'Custo variável',
          grupoDre: 'Custos Variáveis',
          ordemBase: 225,
        );
      case PlanoContaSecao.despesaEmpresa:
        return const _SecaoConfig(
          parentCodigo: '2.04',
          prefixoCodigo: '2.04.9',
          tipo: 'Saída',
          natureza: 'Despesa operacional',
          grupoDre: 'Despesas Operacionais',
          ordemBase: 255,
        );
      case PlanoContaSecao.naoAfetaResultado:
        return const _SecaoConfig(
          parentCodigo: '9',
          prefixoCodigo: '9.9',
          tipo: 'Neutro',
          natureza: 'Movimento patrimonial',
          grupoDre: 'Não DRE',
          ordemBase: 970,
        );
    }
  }

  Future<int?> _idPorCodigo(Database database, String codigo) async {
    final resultado = await database.query(
      'financeiro_plano_contas',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return _int(resultado.first['id']);
  }

  Future<String> _gerarCodigoPersonalizado(
    Database database,
    String prefixo,
  ) async {
    for (var numero = 1; numero <= 999; numero++) {
      final codigo = '$prefixo${numero.toString().padLeft(2, '0')}';
      final existe =
          Sqflite.firstIntValue(
            await database.rawQuery(
              'SELECT COUNT(*) FROM financeiro_plano_contas WHERE codigo = ?',
              [codigo],
            ),
          ) ??
          0;
      if (existe == 0) return codigo;
    }
    throw StateError('Limite de categorias personalizadas atingido.');
  }

  int _numeroSufixo(String codigo) {
    if (codigo.length < 2) return 0;
    return int.tryParse(codigo.substring(codigo.length - 2)) ?? 0;
  }

  int? _int(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }
}

class _SecaoConfig {
  const _SecaoConfig({
    required this.parentCodigo,
    required this.prefixoCodigo,
    required this.tipo,
    required this.natureza,
    required this.grupoDre,
    required this.ordemBase,
  });

  final String parentCodigo;
  final String prefixoCodigo;
  final String tipo;
  final String natureza;
  final String grupoDre;
  final int ordemBase;
}
