import '../database/app_database.dart';
import '../models/servico_catalogo.dart';
import '../models/servico_produto.dart';

class ServicoRepository {
  Future<int> inserirServico(
    ServicoCatalogo servico, {
    List<ServicoProduto> produtos =
        const <ServicoProduto>[],
  }) async {
    final database =
        await AppDatabase.instance.database;

    return database.transaction<int>(
      (transaction) async {
        final servicoId = await transaction.insert(
          'servicos_catalogo',
          servico.toMap(incluirId: false),
        );

        for (var indice = 0;
            indice < produtos.length;
            indice++) {
          final produto = produtos[indice];

          await transaction.insert(
            'servico_produtos',
            {
              ...produto.toMap(incluirId: false),
              'servico_id': servicoId,
              'ordem': indice,
            },
          );
        }

        return servicoId;
      },
    );
  }

  Future<int> atualizarServico(
    ServicoCatalogo servico, {
    List<ServicoProduto> produtos =
        const <ServicoProduto>[],
  }) async {
    final id = servico.id;

    if (id == null) {
      throw Exception(
        'Não é possível atualizar um serviço sem ID.',
      );
    }

    final database =
        await AppDatabase.instance.database;

    return database.transaction<int>(
      (transaction) async {
        final atualizados = await transaction.update(
          'servicos_catalogo',
          servico.toMap(incluirId: false),
          where: 'id = ?',
          whereArgs: [id],
        );

        if (atualizados == 0) {
          throw Exception(
            'Serviço não encontrado para atualização.',
          );
        }

        await transaction.delete(
          'servico_produtos',
          where: 'servico_id = ?',
          whereArgs: [id],
        );

        for (var indice = 0;
            indice < produtos.length;
            indice++) {
          final produto = produtos[indice];

          await transaction.insert(
            'servico_produtos',
            {
              ...produto.toMap(incluirId: false),
              'servico_id': id,
              'ordem': indice,
            },
          );
        }

        return atualizados;
      },
    );
  }

  Future<List<ServicoCatalogo>> listarServicos({
    bool somenteAtivos = false,
    String pesquisa = '',
  }) async {
    final database =
        await AppDatabase.instance.database;

    final condicoes = <String>[];
    final argumentos = <Object?>[];

    if (somenteAtivos) {
      condicoes.add('ativo = 1');
    }

    final termo = pesquisa.trim();

    if (termo.isNotEmpty) {
      condicoes.add(
        '(nome LIKE ? OR categoria LIKE ?)',
      );

      argumentos.addAll([
        '%$termo%',
        '%$termo%',
      ]);
    }

    final resultado = await database.query(
      'servicos_catalogo',
      where: condicoes.isEmpty
          ? null
          : condicoes.join(' AND '),
      whereArgs:
          argumentos.isEmpty ? null : argumentos,
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC',
    );

    return resultado
        .map(ServicoCatalogo.fromMap)
        .toList();
  }

  Future<List<ServicoProduto>>
      listarProdutosDoServico(
    int servicoId,
  ) async {
    final database =
        await AppDatabase.instance.database;

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

    return resultado
        .map(ServicoProduto.fromMap)
        .toList();
  }

  Future<int> alterarAtivo(
    int id,
    bool ativo,
  ) async {
    final database =
        await AppDatabase.instance.database;

    return database.update(
      'servicos_catalogo',
      {
        'ativo': ativo ? 1 : 0,
        'atualizado_em':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirServico(
    int id,
  ) async {
    final database =
        await AppDatabase.instance.database;

    return database.delete(
      'servicos_catalogo',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>>
      listarProdutosDisponiveis() async {
    final database =
        await AppDatabase.instance.database;

    return database.query(
      'itens_estoque',
      columns: [
        'id',
        'nome',
        'unidade',
        'custo_unitario',
        'quantidade',
      ],
      orderBy: 'nome COLLATE NOCASE ASC',
    );
  }
}
