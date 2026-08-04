import '../database/app_database.dart';
import '../models/configuracao_estoque.dart';
import '../models/item_estoque.dart';
import '../models/movimentacao_estoque.dart';
import 'package:sqflite/sqflite.dart';

class EstoqueLote {
  const EstoqueLote({
    this.id,
    required this.itemEstoqueId,
    required this.dataCompra,
    required this.quantidadeOriginal,
    required this.quantidadeNormalizada,
    required this.quantidadeDisponivel,
    required this.unidadeOriginal,
    required this.unidadeBase,
    required this.valorTotalPago,
    required this.custoUnitario,
    required this.fornecedor,
    required this.observacao,
    required this.ativo,
    required this.criadoEm,
  });

  final int? id;
  final int itemEstoqueId;
  final String dataCompra;
  final double quantidadeOriginal;
  final double quantidadeNormalizada;
  final double quantidadeDisponivel;
  final String unidadeOriginal;
  final String unidadeBase;
  final double valorTotalPago;
  final double custoUnitario;
  final String fornecedor;
  final String observacao;
  final bool ativo;
  final String criadoEm;

  factory EstoqueLote.fromMap(Map<String, dynamic> map) {
    return EstoqueLote(
      id: (map['id'] as num?)?.toInt(),
      itemEstoqueId: (map['item_estoque_id'] as num?)?.toInt() ?? 0,
      dataCompra: map['data_compra']?.toString() ?? '',
      quantidadeOriginal: (map['quantidade_original'] as num?)?.toDouble() ?? 0,
      quantidadeNormalizada:
          (map['quantidade_normalizada'] as num?)?.toDouble() ??
          (map['quantidade_original'] as num?)?.toDouble() ??
          0,
      quantidadeDisponivel:
          (map['quantidade_disponivel'] as num?)?.toDouble() ?? 0,
      unidadeOriginal:
          map['unidade_original']?.toString().trim().isNotEmpty == true
          ? map['unidade_original'].toString().trim()
          : map['unidade_base']?.toString() ?? 'unidade',
      unidadeBase: map['unidade_base']?.toString() ?? 'unidade',
      valorTotalPago: (map['valor_total_pago'] as num?)?.toDouble() ?? 0,
      custoUnitario: (map['custo_unitario'] as num?)?.toDouble() ?? 0,
      fornecedor: map['fornecedor']?.toString() ?? '',
      observacao: map['observacao']?.toString() ?? '',
      ativo: (map['ativo'] as num?)?.toInt() != 0,
      criadoEm: map['criado_em']?.toString() ?? '',
    );
  }
}

class LoteConsumoPlanejado {
  const LoteConsumoPlanejado({
    required this.loteId,
    required this.quantidade,
    required this.custoUnitario,
  });

  final int loteId;
  final double quantidade;
  final double custoUnitario;

  double get custoTotal => quantidade * custoUnitario;
}

class EstimativaConsumoFifo {
  const EstimativaConsumoFifo({
    required this.quantidadeSolicitada,
    required this.quantidadeDisponivel,
    required this.custoTotalEstimado,
    required this.consumos,
    required this.suficiente,
  });

  final double quantidadeSolicitada;
  final double quantidadeDisponivel;
  final double custoTotalEstimado;
  final List<LoteConsumoPlanejado> consumos;
  final bool suficiente;

  double get custoUnitarioEstimado {
    if (quantidadeSolicitada <= 0) {
      return 0;
    }

    return custoTotalEstimado / quantidadeSolicitada;
  }
}

class EstoqueRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  double _normalizarQuantidade(double quantidade, String unidade) {
    return quantidade * ItemEstoque.fatorNormalizacaoUnidade(unidade);
  }

  String _unidadeBase(String unidade) {
    return ItemEstoque.unidadeNormalizadaParaBase(unidade);
  }

  // ======================
  // PRODUTOS
  // ======================

  Future<int> inserirItem(ItemEstoque item) async {
    final database = await _appDatabase.database;

    return database.transaction((transaction) async {
      final dados = item.toMap();
      dados.remove('id');

      final itemId = await transaction.insert('itens_estoque', dados);

      if (item.quantidade > 0 && item.custoUnitarioEfetivo > 0) {
        final agora = DateTime.now().toIso8601String();
        final quantidadeOriginalInformada = item.quantidadeTotal > 0
            ? item.quantidadeTotal
            : item.quantidade;
        final quantidadeNormalizada = item.quantidade > 0
            ? item.quantidade
            : quantidadeOriginalInformada;
        final unidadeOriginal = item.unidade;

        await transaction.insert('estoque_lotes', {
          'item_estoque_id': itemId,
          'data_compra': agora,
          'quantidade_original': quantidadeOriginalInformada,
          'quantidade_normalizada': quantidadeNormalizada,
          'quantidade_disponivel': quantidadeNormalizada,
          'unidade_original': unidadeOriginal,
          'unidade_base': _unidadeBase(item.unidade),
          'valor_total_pago': item.valorTotalPago > 0
              ? item.valorTotalPago
              : (quantidadeNormalizada * item.custoUnitarioEfetivo),
          'custo_unitario': item.custoUnitarioEfetivo,
          'fornecedor': item.fornecedor,
          'observacao': item.observacoes,
          'ativo': 1,
          'criado_em': agora,
        });

        await transaction.insert('movimentacoes_estoque', {
          'item_estoque_id': itemId,
          'tipo': 'ENTRADA',
          'quantidade': quantidadeNormalizada,
          'quantidade_anterior': 0,
          'quantidade_posterior': quantidadeNormalizada,
          'custo_unitario': item.custoUnitarioEfetivo,
          'observacoes': 'Entrada inicial do cadastro do produto',
          'motivo': 'Compra inicial do cadastro',
          'origem': 'Cadastro de produto',
          'ordem_servico_id': null,
          'lote_id': null,
          'data': agora,
        });
      }

      return itemId;
    });
  }

  Future<List<ItemEstoque>> listarItens({bool incluirInativos = false}) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'itens_estoque',
      where: incluirInativos ? null : 'ativo = 1',
      orderBy: 'nome COLLATE NOCASE ASC, id ASC',
    );

    return resultado.map(ItemEstoque.fromMap).toList();
  }

  Future<ItemEstoque?> buscarItemPorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'itens_estoque',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ItemEstoque.fromMap(resultado.first);
  }

  Future<ItemEstoque?> buscarItemPorNome(String nome) async {
    final database = await _appDatabase.database;

    final nomeLimpo = nome.trim();

    if (nomeLimpo.isEmpty) {
      return null;
    }

    final resultado = await database.query(
      'itens_estoque',
      where: 'LOWER(TRIM(nome)) = LOWER(TRIM(?))',
      whereArgs: [nomeLimpo],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ItemEstoque.fromMap(resultado.first);
  }

  Future<int> atualizarItem(ItemEstoque item) async {
    if (item.id == null) {
      throw ArgumentError('Não é possível atualizar um item sem ID.');
    }

    final database = await _appDatabase.database;

    return database.transaction((transaction) async {
      final atual = await transaction.query(
        'itens_estoque',
        where: 'id = ?',
        whereArgs: [item.id],
        limit: 1,
      );

      if (atual.isEmpty) {
        throw Exception('Produto não encontrado para atualização.');
      }

      final existente = ItemEstoque.fromMap(atual.first);

      final dados = <String, dynamic>{
        'nome': item.nome,
        'categoria': item.categoria,
        'quantidade': item.quantidade,
        'quantidade_minima': item.quantidadeMinima,
        'unidade': item.unidade,
        // Mantemos campos de compra para compatibilidade, sem alterar lotes antigos.
        'valor_total_pago': existente.valorTotalPago,
        'quantidade_total': existente.quantidadeTotal,
        'custo_unitario': existente.custoUnitarioEfetivo,
        'custo_unitario_calculado': existente.custoUnitarioEfetivo,
        'fornecedor': item.fornecedor,
        'observacoes': item.observacoes,
        'ativo': item.ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      };

      final atualizado = await transaction.update(
        'itens_estoque',
        dados,
        where: 'id = ?',
        whereArgs: [item.id],
      );

      if ((item.quantidade - existente.quantidade).abs() > 0.000001) {
        await transaction.insert('movimentacoes_estoque', {
          'item_estoque_id': item.id,
          'tipo': 'AJUSTE',
          'quantidade': (item.quantidade - existente.quantidade).abs(),
          'quantidade_anterior': existente.quantidade,
          'quantidade_posterior': item.quantidade,
          'custo_unitario': existente.custoUnitarioEfetivo,
          'observacoes': 'Ajuste manual pela edição cadastral do produto',
          'origem': 'Edição de produto',
          'ordem_servico_id': null,
          'lote_id': null,
          'data': DateTime.now().toIso8601String(),
        });
      }

      return atualizado;
    });
  }

  Future<int> atualizarQuantidade(int id, double quantidade) async {
    if (quantidade < 0) {
      throw ArgumentError('A quantidade em estoque não pode ser negativa.');
    }

    final database = await _appDatabase.database;

    return database.update(
      'itens_estoque',
      {
        'quantidade': quantidade,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirItem(int id) async {
    final database = await _appDatabase.database;

    final usoServico = await database.query(
      'servico_produtos',
      columns: ['id'],
      where: 'item_estoque_id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (usoServico.isNotEmpty) {
      throw Exception(
        'Este produto está vinculado a serviços e não pode ser excluído.',
      );
    }

    final usoOrdem = await database.query(
      'ordem_servico_produtos',
      columns: ['id'],
      where: 'produto_id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (usoOrdem.isNotEmpty) {
      throw Exception(
        'Este produto está vinculado a Ordens de Serviço e não pode ser excluído.',
      );
    }

    return database.update(
      'itens_estoque',
      {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> alterarAtivo(int id, bool ativo) async {
    final database = await _appDatabase.database;

    return database.update(
      'itens_estoque',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> adicionarEntradaEstoque({
    required int itemId,
    required double valorTotalPago,
    required double quantidadeTotal,
    required String unidadeInformada,
    String fornecedor = '',
    String observacao = '',
    String origem = 'Compra de estoque',
    DateTime? dataCompra,
  }) async {
    if (valorTotalPago <= 0 || !valorTotalPago.isFinite) {
      throw Exception('Informe um valor total pago válido.');
    }

    if (quantidadeTotal <= 0 || !quantidadeTotal.isFinite) {
      throw Exception('Informe uma quantidade total válida.');
    }

    final quantidadeNormalizada = _normalizarQuantidade(
      quantidadeTotal,
      unidadeInformada,
    );

    if (quantidadeNormalizada <= 0 || !quantidadeNormalizada.isFinite) {
      throw Exception('Não foi possível normalizar a quantidade informada.');
    }

    final custoUnitario = valorTotalPago / quantidadeNormalizada;

    if (!custoUnitario.isFinite || custoUnitario.isNaN || custoUnitario <= 0) {
      throw Exception('Custo unitário inválido para este lote.');
    }

    final database = await _appDatabase.database;
    final momento = (dataCompra ?? DateTime.now()).toIso8601String();

    await database.transaction((transaction) async {
      final itemResultado = await transaction.query(
        'itens_estoque',
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );

      if (itemResultado.isEmpty) {
        throw Exception('Produto não encontrado.');
      }

      final item = ItemEstoque.fromMap(itemResultado.first);
      final quantidadeAnterior = item.quantidade;
      final quantidadePosterior = quantidadeAnterior + quantidadeNormalizada;

      final loteId = await transaction.insert('estoque_lotes', {
        'item_estoque_id': itemId,
        'data_compra': momento,
        'quantidade_original': quantidadeTotal,
        'quantidade_normalizada': quantidadeNormalizada,
        'quantidade_disponivel': quantidadeNormalizada,
        'unidade_original': unidadeInformada,
        'unidade_base': _unidadeBase(unidadeInformada),
        'valor_total_pago': valorTotalPago,
        'custo_unitario': custoUnitario,
        'fornecedor': fornecedor.trim(),
        'observacao': observacao.trim(),
        'ativo': 1,
        'criado_em': momento,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await transaction.update(
        'itens_estoque',
        {
          'quantidade': quantidadePosterior,
          'unidade': _unidadeBase(unidadeInformada),
          'valor_total_pago': valorTotalPago,
          'quantidade_total': quantidadeNormalizada,
          'custo_unitario': custoUnitario,
          'custo_unitario_calculado': custoUnitario,
          'fornecedor': fornecedor.trim().isEmpty
              ? item.fornecedor
              : fornecedor.trim(),
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

      await transaction.insert('movimentacoes_estoque', {
        'item_estoque_id': itemId,
        'tipo': 'ENTRADA',
        'quantidade': quantidadeNormalizada,
        'quantidade_anterior': quantidadeAnterior,
        'quantidade_posterior': quantidadePosterior,
        'custo_unitario': custoUnitario,
        'observacoes': observacao.trim().isEmpty
            ? 'Entrada por compra/lote'
            : observacao.trim(),
        'motivo': 'Nova entrada de estoque',
        'origem': origem,
        'ordem_servico_id': null,
        'lote_id': loteId,
        'data': momento,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  Future<List<EstoqueLote>> listarLotesDoItem(int itemId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'estoque_lotes',
      where: 'item_estoque_id = ?',
      whereArgs: [itemId],
      orderBy: 'data_compra ASC, id ASC',
    );

    return resultado.map(EstoqueLote.fromMap).toList();
  }

  Future<List<LoteConsumoPlanejado>> planejarConsumoFifo({
    required int itemId,
    required double quantidadeNecessaria,
  }) async {
    if (quantidadeNecessaria <= 0) {
      return const <LoteConsumoPlanejado>[];
    }

    final lotes = await listarLotesDoItem(itemId);
    final lotesComSaldo = lotes
        .where((lote) => lote.ativo && lote.quantidadeDisponivel > 0)
        .toList();

    final disponivel = lotesComSaldo.fold<double>(
      0,
      (total, lote) => total + lote.quantidadeDisponivel,
    );

    if (disponivel + 0.000001 < quantidadeNecessaria) {
      throw Exception(
        'Estoque insuficiente. Necessário: ${quantidadeNecessaria.toStringAsFixed(3)}. '
        'Disponível: ${disponivel.toStringAsFixed(3)}.',
      );
    }

    final consumos = <LoteConsumoPlanejado>[];
    var restante = quantidadeNecessaria;

    for (final lote in lotesComSaldo) {
      if (restante <= 0) {
        break;
      }

      final consumo = restante < lote.quantidadeDisponivel
          ? restante
          : lote.quantidadeDisponivel;

      consumos.add(
        LoteConsumoPlanejado(
          loteId: lote.id ?? 0,
          quantidade: consumo,
          custoUnitario: lote.custoUnitario,
        ),
      );

      restante -= consumo;
    }

    if (restante > 0.000001) {
      throw Exception('Não foi possível montar o consumo FIFO completo.');
    }

    return consumos;
  }

  Future<EstimativaConsumoFifo> estimarConsumoFifo({
    required int itemId,
    required double quantidadeNecessaria,
  }) async {
    if (quantidadeNecessaria <= 0) {
      return const EstimativaConsumoFifo(
        quantidadeSolicitada: 0,
        quantidadeDisponivel: 0,
        custoTotalEstimado: 0,
        consumos: <LoteConsumoPlanejado>[],
        suficiente: true,
      );
    }

    final lotes = await listarLotesDoItem(itemId);
    final lotesComSaldo = lotes
        .where((lote) => lote.ativo && lote.quantidadeDisponivel > 0)
        .toList();

    final disponivel = lotesComSaldo.fold<double>(
      0,
      (total, lote) => total + lote.quantidadeDisponivel,
    );

    var restante = quantidadeNecessaria;
    final consumos = <LoteConsumoPlanejado>[];

    for (final lote in lotesComSaldo) {
      if (restante <= 0) {
        break;
      }

      final consumo = restante < lote.quantidadeDisponivel
          ? restante
          : lote.quantidadeDisponivel;

      consumos.add(
        LoteConsumoPlanejado(
          loteId: lote.id ?? 0,
          quantidade: consumo,
          custoUnitario: lote.custoUnitario,
        ),
      );

      restante -= consumo;
    }

    final custoTotal = consumos.fold<double>(
      0,
      (total, consumo) => total + consumo.custoTotal,
    );

    return EstimativaConsumoFifo(
      quantidadeSolicitada: quantidadeNecessaria,
      quantidadeDisponivel: disponivel,
      custoTotalEstimado: custoTotal,
      consumos: consumos,
      suficiente: disponivel + 0.000001 >= quantidadeNecessaria,
    );
  }

  // ======================
  // MOVIMENTAÇÕES
  // ======================

  Future<void> registrarMovimentacao(MovimentacaoEstoque movimentacao) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'itens_estoque',
        where: 'id = ?',
        whereArgs: [movimentacao.itemId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw Exception('Produto não encontrado.');
      }

      final item = ItemEstoque.fromMap(resultado.first);

      if (movimentacao.quantidade < 0) {
        throw Exception('A quantidade informada não pode ser negativa.');
      }

      final tipo = movimentacao.tipo.trim().toUpperCase();
      final quantidadeAnterior = item.quantidade;

      double novaQuantidade = quantidadeAnterior;

      switch (tipo) {
        case 'ENTRADA':
          if (movimentacao.quantidade <= 0) {
            throw Exception('A quantidade de entrada deve ser maior que zero.');
          }

          novaQuantidade += movimentacao.quantidade;
          break;

        case 'SAIDA':
          if (movimentacao.quantidade <= 0) {
            throw Exception('A quantidade de saída deve ser maior que zero.');
          }

          if (movimentacao.quantidade > quantidadeAnterior) {
            throw Exception(
              'Quantidade de saída maior que o estoque disponível.',
            );
          }

          novaQuantidade -= movimentacao.quantidade;
          break;

        case 'AJUSTE':
          if (movimentacao.quantidade < 0) {
            throw Exception(
              'A quantidade final do ajuste não pode ser negativa.',
            );
          }

          if (movimentacao.motivo.trim().isEmpty) {
            throw Exception('Informe o motivo do ajuste manual.');
          }

          novaQuantidade = movimentacao.quantidade;
          break;

        default:
          throw Exception('Tipo de movimentação inválido.');
      }

      final dadosMovimentacao = movimentacao.toMap();

      final quantidadeMovimentada = tipo == 'AJUSTE'
          ? (novaQuantidade - quantidadeAnterior).abs()
          : movimentacao.quantidade;

      final custoUnitario =
          movimentacao.custoUnitario != null && movimentacao.custoUnitario! >= 0
          ? movimentacao.custoUnitario!
          : item.custoUnitarioEfetivo;

      dadosMovimentacao['tipo'] = tipo;
      dadosMovimentacao['quantidade'] = quantidadeMovimentada;
      dadosMovimentacao['quantidade_anterior'] = quantidadeAnterior;
      dadosMovimentacao['quantidade_posterior'] = novaQuantidade;
      dadosMovimentacao['custo_unitario'] = custoUnitario;
      dadosMovimentacao['motivo'] = movimentacao.motivo.trim();
      dadosMovimentacao['origem'] = movimentacao.origem.trim().isEmpty
          ? 'Manual'
          : movimentacao.origem.trim();
      if (tipo == 'AJUSTE') {
        dadosMovimentacao['origem'] = 'Ajuste manual';
      }
      dadosMovimentacao['lote_id'] = movimentacao.loteId;

      dadosMovimentacao.remove('id');

      await transaction.insert('movimentacoes_estoque', dadosMovimentacao);

      await transaction.update(
        'itens_estoque',
        {
          'quantidade': novaQuantidade,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [movimentacao.itemId],
      );
    });
  }

  Future<List<MovimentacaoEstoque>> listarMovimentacoes() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'movimentacoes_estoque',
      orderBy: 'data DESC, id DESC',
    );

    return resultado.map(MovimentacaoEstoque.fromMap).toList();
  }

  Future<List<MovimentacaoEstoque>> listarMovimentacoesDoItem(
    int itemId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'movimentacoes_estoque',
      where: 'item_estoque_id = ?',
      whereArgs: [itemId],
      orderBy: 'data DESC, id DESC',
    );

    return resultado.map(MovimentacaoEstoque.fromMap).toList();
  }

  // ======================
  // CONFIGURAÇÕES
  // ======================

  Future<ConfiguracaoEstoque> obterConfiguracao() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'configuracoes_estoque',
      orderBy: 'id ASC',
      limit: 1,
    );

    if (resultado.isEmpty) {
      final configuracao = ConfiguracaoEstoque.padrao();

      final id = await salvarConfiguracao(configuracao);

      return configuracao.copyWith(id: id);
    }

    return ConfiguracaoEstoque.fromMap(resultado.first);
  }

  Future<int> salvarConfiguracao(ConfiguracaoEstoque configuracao) async {
    final database = await _appDatabase.database;

    final dados = configuracao.toMap();

    if (configuracao.id == null) {
      dados.remove('id');

      return database.insert('configuracoes_estoque', dados);
    }

    dados.remove('id');

    await database.update(
      'configuracoes_estoque',
      dados,
      where: 'id = ?',
      whereArgs: [configuracao.id],
    );

    return configuracao.id!;
  }
}
