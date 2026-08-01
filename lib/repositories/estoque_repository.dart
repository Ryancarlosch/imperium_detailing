import '../database/app_database.dart';
import '../models/configuracao_estoque.dart';
import '../models/item_estoque.dart';
import '../models/movimentacao_estoque.dart';

class EstoqueRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  // ======================
  // PRODUTOS
  // ======================

  Future<int> inserirItem(ItemEstoque item) async {
    final database = await _appDatabase.database;

    final dados = item.toMap();
    dados.remove('id');

    return database.insert('itens_estoque', dados);
  }

  Future<List<ItemEstoque>> listarItens() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'itens_estoque',
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

    final dados = item.toMap();
    dados.remove('id');

    return database.update(
      'itens_estoque',
      dados,
      where: 'id = ?',
      whereArgs: [item.id],
    );
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

    return database.delete('itens_estoque', where: 'id = ?', whereArgs: [id]);
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
          : item.custoUnitario;

      dadosMovimentacao['tipo'] = tipo;
      dadosMovimentacao['quantidade'] = quantidadeMovimentada;
      dadosMovimentacao['quantidade_anterior'] = quantidadeAnterior;
      dadosMovimentacao['quantidade_posterior'] = novaQuantidade;
      dadosMovimentacao['custo_unitario'] = custoUnitario;
      dadosMovimentacao['origem'] = movimentacao.origem.trim().isEmpty
          ? 'Manual'
          : movimentacao.origem.trim();

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
