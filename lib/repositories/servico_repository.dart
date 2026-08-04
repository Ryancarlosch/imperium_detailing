import '../database/app_database.dart';
import '../models/servico_catalogo.dart';
import '../models/servico_produto.dart';

class ServicoCategoria {
  const ServicoCategoria({this.id, required this.nome, required this.ativo});

  final int? id;
  final String nome;
  final bool ativo;
}

class ServicoRepository {
  Future<int?> _resolverCategoriaId(dynamic executor, String categoria) async {
    final nome = categoria.trim();

    if (nome.isEmpty) {
      return null;
    }

    final existente = await executor.query(
      'servico_categorias',
      columns: ['id'],
      where: 'LOWER(TRIM(nome)) = LOWER(TRIM(?))',
      whereArgs: [nome],
      limit: 1,
    );

    if (existente.isNotEmpty) {
      final id = existente.first['id'];

      if (id is int) {
        return id;
      }

      if (id is num) {
        return id.toInt();
      }
    }

    final agora = DateTime.now().toIso8601String();

    return executor.insert('servico_categorias', {
      'nome': nome,
      'ativo': 1,
      'criado_em': agora,
      'atualizado_em': agora,
    });
  }

  void _validarProdutosServico(List<ServicoProduto> produtos) {
    for (final produto in produtos) {
      if (produto.quantidadePadrao <= 0) {
        throw Exception(
          'A quantidade padrão dos produtos do serviço deve ser maior que zero.',
        );
      }
    }
  }

  Future<int> inserirServico(
    ServicoCatalogo servico, {
    List<ServicoProduto> produtos = const <ServicoProduto>[],
  }) async {
    _validarProdutosServico(produtos);

    final database = await AppDatabase.instance.database;

    return database.transaction<int>((transaction) async {
      final categoriaId = await _resolverCategoriaId(
        transaction,
        servico.categoria,
      );

      final servicoId = await transaction.insert('servicos_catalogo', {
        ...servico.toMap(incluirId: false),
        'categoria_id': categoriaId,
      });

      for (var indice = 0; indice < produtos.length; indice++) {
        final produto = produtos[indice];

        await transaction.insert('servico_produtos', {
          ...produto.toMap(incluirId: false),
          'servico_id': servicoId,
          'ordem': indice,
        });
      }

      return servicoId;
    });
  }

  Future<int> atualizarServico(
    ServicoCatalogo servico, {
    List<ServicoProduto> produtos = const <ServicoProduto>[],
  }) async {
    _validarProdutosServico(produtos);

    final id = servico.id;

    if (id == null) {
      throw Exception('Não é possível atualizar um serviço sem ID.');
    }

    final database = await AppDatabase.instance.database;

    return database.transaction<int>((transaction) async {
      final categoriaId = await _resolverCategoriaId(
        transaction,
        servico.categoria,
      );

      final atualizados = await transaction.update(
        'servicos_catalogo',
        {...servico.toMap(incluirId: false), 'categoria_id': categoriaId},
        where: 'id = ?',
        whereArgs: [id],
      );

      if (atualizados == 0) {
        throw Exception('Serviço não encontrado para atualização.');
      }

      await transaction.delete(
        'servico_produtos',
        where: 'servico_id = ?',
        whereArgs: [id],
      );

      for (var indice = 0; indice < produtos.length; indice++) {
        final produto = produtos[indice];

        await transaction.insert('servico_produtos', {
          ...produto.toMap(incluirId: false),
          'servico_id': id,
          'ordem': indice,
        });
      }

      return atualizados;
    });
  }

  Future<List<ServicoCatalogo>> listarServicos({
    bool somenteAtivos = false,
    String pesquisa = '',
    int? categoriaId,
  }) async {
    final database = await AppDatabase.instance.database;

    final condicoes = <String>[];
    final argumentos = <Object?>[];

    if (somenteAtivos) {
      condicoes.add('s.ativo = 1');
    }

    final termo = pesquisa.trim();

    if (termo.isNotEmpty) {
      condicoes.add('''
        (
          s.nome LIKE ?
          OR COALESCE(NULLIF(c.nome, ''), s.categoria, '') LIKE ?
        )
      ''');

      argumentos.addAll(['%$termo%', '%$termo%']);
    }

    if (categoriaId != null) {
      condicoes.add('s.categoria_id = ?');
      argumentos.add(categoriaId);
    }

    final resultado = await database.rawQuery('''
      SELECT
        s.id,
        s.nome,
        s.categoria_id,
        COALESCE(NULLIF(c.nome, ''), s.categoria, '') AS categoria,
        s.descricao,
        s.observacoes_padrao,
        s.preco_minimo,
        s.preco_padrao,
        s.preco_maximo,
        s.duracao_minutos,
        s.ativo,
        s.criado_em,
        s.atualizado_em
      FROM servicos_catalogo s
      LEFT JOIN servico_categorias c
        ON c.id = s.categoria_id
      ${condicoes.isEmpty ? '' : 'WHERE ${condicoes.join(' AND ')}'}
      ORDER BY s.ativo DESC, s.nome COLLATE NOCASE ASC
      ''', argumentos);

    return resultado.map(ServicoCatalogo.fromMap).toList();
  }

  Future<List<ServicoCategoria>> listarCategorias({
    bool somenteAtivas = true,
  }) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'servico_categorias',
      where: somenteAtivas ? 'ativo = 1' : null,
      orderBy: 'nome COLLATE NOCASE ASC',
    );

    return resultado
        .map(
          (mapa) => ServicoCategoria(
            id: (mapa['id'] as num?)?.toInt(),
            nome: mapa['nome']?.toString() ?? '',
            ativo: (mapa['ativo'] as num?)?.toInt() != 0,
          ),
        )
        .toList();
  }

  Future<int> criarCategoria(String nome) async {
    final database = await AppDatabase.instance.database;

    final nomeLimpo = nome.trim();

    if (nomeLimpo.isEmpty) {
      throw Exception('Informe o nome da categoria.');
    }

    final existente = await database.query(
      'servico_categorias',
      columns: ['id'],
      where: 'LOWER(TRIM(nome)) = LOWER(TRIM(?))',
      whereArgs: [nomeLimpo],
      limit: 1,
    );

    if (existente.isNotEmpty) {
      final id = existente.first['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();
    }

    final agora = DateTime.now().toIso8601String();

    return database.insert('servico_categorias', {
      'nome': nomeLimpo,
      'ativo': 1,
      'criado_em': agora,
      'atualizado_em': agora,
    });
  }

  Future<List<ServicoProduto>> listarProdutosDoServico(int servicoId) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        sp.*,
        ie.nome AS produto_nome,
        ie.custo_unitario AS custo_unitario
      FROM servico_produtos sp
      INNER JOIN itens_estoque ie
        ON ie.id = sp.item_estoque_id
      WHERE sp.servico_id = ?
      ORDER BY sp.ordem ASC, sp.id ASC
      ''',
      [servicoId],
    );

    return resultado.map(ServicoProduto.fromMap).toList();
  }

  Future<int> alterarAtivo(int id, bool ativo) async {
    final database = await AppDatabase.instance.database;

    return database.update(
      'servicos_catalogo',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirServico(int id) async {
    // Nesta sprint mantemos exclusão lógica para preservar histórico.
    return alterarAtivo(id, false);
  }

  Future<List<Map<String, dynamic>>> listarProdutosDisponiveis() async {
    final database = await AppDatabase.instance.database;

    return database.query(
      'itens_estoque',
      columns: [
        'id',
        'nome',
        'unidade',
        'quantidade',
        'custo_unitario',
        'custo_unitario_calculado',
      ],
      where: 'ativo = 1',
      orderBy: 'nome COLLATE NOCASE ASC',
    );
  }
}
