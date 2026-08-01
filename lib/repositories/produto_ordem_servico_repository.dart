import '../database/app_database.dart';
import '../models/produto_ordem_servico.dart';

class ProdutoOrdemServicoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  void _validarProduto(ProdutoOrdemServico produto) {
    if (produto.produtoNome.trim().isEmpty) {
      throw Exception('Informe o nome do produto.');
    }

    if (produto.quantidade <= 0) {
      throw Exception('A quantidade do produto deve ser maior que zero.');
    }

    if (produto.custoUnitario < 0) {
      throw Exception('O custo unitário não pode ser negativo.');
    }
  }

  Future<int> inserirProduto(ProdutoOrdemServico produto) async {
    _validarProduto(produto);

    final database = await _appDatabase.database;

    final dados = produto.toMap();
    dados.remove('id');

    return database.insert('ordem_servico_produtos', dados);
  }

  Future<List<ProdutoOrdemServico>> listarProdutosPorOrdemServico(
    int ordemServicoId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_produtos',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: 'produto_nome ASC, id ASC',
    );

    return resultado.map(ProdutoOrdemServico.fromMap).toList();
  }

  Future<ProdutoOrdemServico?> buscarProdutoPorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_produtos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ProdutoOrdemServico.fromMap(resultado.first);
  }

  Future<ProdutoOrdemServico?> buscarProdutoNaOrdem({
    required int ordemServicoId,
    required int produtoId,
  }) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_produtos',
      where: 'ordem_servico_id = ? AND produto_id = ?',
      whereArgs: [ordemServicoId, produtoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return ProdutoOrdemServico.fromMap(resultado.first);
  }

  Future<int> atualizarProduto(ProdutoOrdemServico produto) async {
    _validarProduto(produto);

    if (produto.id == null) {
      throw ArgumentError('Não é possível atualizar um produto sem ID.');
    }

    final existente = await buscarProdutoPorId(produto.id!);

    if (existente == null) {
      throw Exception('Produto não encontrado para atualização.');
    }

    if (existente.baixadoEstoque) {
      throw Exception(
        'Este produto já teve baixa no estoque e não pode ser alterado.',
      );
    }

    final database = await _appDatabase.database;

    final dados = produto.toMap();
    dados.remove('id');

    return database.update(
      'ordem_servico_produtos',
      dados,
      where: 'id = ?',
      whereArgs: [produto.id],
    );
  }

  Future<int> salvarProduto(ProdutoOrdemServico produto) async {
    if (produto.id == null) {
      return inserirProduto(produto);
    }

    await atualizarProduto(produto);

    return produto.id!;
  }

  Future<int> adicionarOuSomarProduto(ProdutoOrdemServico produto) async {
    final produtoId = produto.produtoId;

    if (produtoId == null) {
      return inserirProduto(produto);
    }

    final existente = await buscarProdutoNaOrdem(
      ordemServicoId: produto.ordemServicoId,
      produtoId: produtoId,
    );

    if (existente == null) {
      return inserirProduto(produto);
    }

    if (existente.baixadoEstoque) {
      throw Exception(
        'Este produto já teve baixa no estoque e não pode ser alterado.',
      );
    }

    final atualizado = existente.copyWith(
      quantidade: existente.quantidade + produto.quantidade,
      produtoNome: produto.produtoNome,
      unidade: produto.unidade,
      custoUnitario: produto.custoUnitario,
    );

    await atualizarProduto(atualizado);

    return existente.id!;
  }

  Future<int> excluirProduto(int id) async {
    final database = await _appDatabase.database;

    final produto = await buscarProdutoPorId(id);

    if (produto == null) {
      return 0;
    }

    if (produto.baixadoEstoque) {
      throw Exception(
        'Este produto já teve baixa no estoque e não pode ser removido.',
      );
    }

    return database.delete(
      'ordem_servico_produtos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirProdutosDaOrdem(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final produtos = await listarProdutosPorOrdemServico(ordemServicoId);

    final possuiBaixado = produtos.any((produto) => produto.baixadoEstoque);

    if (possuiBaixado) {
      throw Exception('Existem produtos que já tiveram baixa no estoque.');
    }

    return database.delete(
      'ordem_servico_produtos',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
    );
  }

  Future<double> calcularCustoTotal(int ordemServicoId) async {
    final produtos = await listarProdutosPorOrdemServico(ordemServicoId);

    return produtos.fold<double>(
      0,
      (total, produto) => total + produto.custoTotal,
    );
  }

  Future<int> contarProdutos(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS quantidade
      FROM ordem_servico_produtos
      WHERE ordem_servico_id = ?
      ''',
      [ordemServicoId],
    );

    if (resultado.isEmpty) {
      return 0;
    }

    final valor = resultado.first['quantidade'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Future<bool> possuiProdutoBaixado(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_produtos',
      columns: ['id'],
      where: 'ordem_servico_id = ? AND baixado_estoque = 1',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    return resultado.isNotEmpty;
  }

  Future<int> marcarComoBaixado(int id) async {
    final database = await _appDatabase.database;

    return database.update(
      'ordem_servico_produtos',
      {'baixado_estoque': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> marcarComoNaoBaixado(int id) async {
    final database = await _appDatabase.database;

    return database.update(
      'ordem_servico_produtos',
      {'baixado_estoque': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
