import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/item_orcamento.dart';
import '../models/orcamento.dart';

class OrcamentoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<void> _garantirEstruturaPerfil(dynamic executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_preco_documentos (
        documento_tipo TEXT NOT NULL,
        documento_id INTEGER NOT NULL,
        perfil TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (documento_tipo, documento_id)
      )
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_orcamento_item_catalogo (
        orcamento_id INTEGER NOT NULL,
        ordem INTEGER NOT NULL,
        servico_catalogo_id INTEGER NOT NULL,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (orcamento_id, ordem)
      )
    ''');
  }

  Future<void> _salvarPerfilComExecutor(
    dynamic executor, {
    required int orcamentoId,
    required String perfil,
  }) async {
    final agora = DateTime.now().toIso8601String();

    await executor.insert('financeiro_preco_documentos', {
      'documento_tipo': 'ORCAMENTO',
      'documento_id': orcamentoId,
      'perfil': perfil.trim().isEmpty ? 'informado' : perfil.trim(),
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _salvarMapeamentoCatalogo(
    DatabaseExecutor executor, {
    required int orcamentoId,
    Map<int, int?> servicoCatalogoPorOrdem = const <int, int?>{},
  }) async {
    await executor.delete(
      'financeiro_orcamento_item_catalogo',
      where: 'orcamento_id = ?',
      whereArgs: [orcamentoId],
    );

    final agora = DateTime.now().toIso8601String();

    for (final entry in servicoCatalogoPorOrdem.entries) {
      final servicoId = entry.value;

      if (entry.key < 0 || servicoId == null || servicoId <= 0) {
        continue;
      }

      await executor.insert(
        'financeiro_orcamento_item_catalogo',
        {
          'orcamento_id': orcamentoId,
          'ordem': entry.key,
          'servico_catalogo_id': servicoId,
          'atualizado_em': agora,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> inserirOrcamento(
    Orcamento orcamento, {
    String perfilPreco = 'informado',
    Map<int, int?> servicoCatalogoPorOrdem = const <int, int?>{},
  }) async {
    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
      await _garantirEstruturaPerfil(transaction);

      final dadosOrcamento = _dadosPrincipais(orcamento);

      final orcamentoId = await transaction.insert(
        'orcamentos',
        dadosOrcamento,
      );

      await _salvarPerfilComExecutor(
        transaction,
        orcamentoId: orcamentoId,
        perfil: perfilPreco,
      );

      await _salvarItens(
        transaction: transaction,
        orcamentoId: orcamentoId,
        itens: orcamento.itens,
        orcamentoAntigo: orcamento,
      );

      await _salvarMapeamentoCatalogo(
        transaction,
        orcamentoId: orcamentoId,
        servicoCatalogoPorOrdem: servicoCatalogoPorOrdem,
      );

      return orcamentoId;
    });
  }

  Future<List<Map<String, dynamic>>> listarOrcamentosComDetalhes() async {
    final database = await _appDatabase.database;
    await _garantirEstruturaPerfil(database);

    return database.rawQuery('''
      SELECT
        o.*,
        c.nome AS cliente_nome,
        c.telefone AS cliente_telefone,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa,
        COALESCE(
          (
            SELECT pdoc.perfil
            FROM financeiro_preco_documentos pdoc
            WHERE pdoc.documento_tipo = 'ORCAMENTO'
              AND pdoc.documento_id = o.id
            LIMIT 1
          ),
          'informado'
        ) AS perfil_preco,
        COUNT(i.id) AS quantidade_itens,
        COALESCE(
          GROUP_CONCAT(NULLIF(TRIM(i.servico), ''), ', '),
          NULLIF(TRIM(o.servico), ''),
          'Serviço'
        ) AS servicos_resumo,
        COALESCE(
          SUM(
            i.quantidade *
            i.valor_unitario
          ),
          o.valor,
          0
        ) AS subtotal_itens,
        CASE
          WHEN (
            COALESCE(
              SUM(
                i.quantidade *
                i.valor_unitario
              ),
              o.valor,
              0
            ) -
            COALESCE(o.desconto, 0)
          ) < 0
            THEN 0
          ELSE
            COALESCE(
              SUM(
                i.quantidade *
                i.valor_unitario
              ),
              o.valor,
              0
            ) -
            COALESCE(o.desconto, 0)
        END AS valor_total
      FROM orcamentos o
      INNER JOIN clientes c
        ON c.id = o.cliente_id
      LEFT JOIN veiculos v
        ON v.id = o.veiculo_id
      LEFT JOIN orcamento_itens i
        ON i.orcamento_id = o.id
      GROUP BY o.id
      ORDER BY
        o.data_emissao DESC,
        o.id DESC
    ''');
  }

  Future<Map<String, dynamic>?> buscarOrcamentoComDetalhes(int id) async {
    final database = await _appDatabase.database;
    await _garantirEstruturaPerfil(database);

    final resultado = await database.rawQuery(
      '''
      SELECT
        o.*,
        c.nome AS cliente_nome,
        c.telefone AS cliente_telefone,
        c.email AS cliente_email,
        c.endereco AS cliente_endereco,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa,
        v.cor AS veiculo_cor,
        v.ano AS veiculo_ano,
        COALESCE(
          (
            SELECT pdoc.perfil
            FROM financeiro_preco_documentos pdoc
            WHERE pdoc.documento_tipo = 'ORCAMENTO'
              AND pdoc.documento_id = o.id
            LIMIT 1
          ),
          'informado'
        ) AS perfil_preco,
        COUNT(i.id) AS quantidade_itens,
        COALESCE(
          SUM(
            i.quantidade *
            i.valor_unitario
          ),
          o.valor,
          0
        ) AS subtotal_itens,
        CASE
          WHEN (
            COALESCE(
              SUM(
                i.quantidade *
                i.valor_unitario
              ),
              o.valor,
              0
            ) -
            COALESCE(o.desconto, 0)
          ) < 0
            THEN 0
          ELSE
            COALESCE(
              SUM(
                i.quantidade *
                i.valor_unitario
              ),
              o.valor,
              0
            ) -
            COALESCE(o.desconto, 0)
        END AS valor_total
      FROM orcamentos o
      INNER JOIN clientes c
        ON c.id = o.cliente_id
      LEFT JOIN veiculos v
        ON v.id = o.veiculo_id
      LEFT JOIN orcamento_itens i
        ON i.orcamento_id = o.id
      WHERE o.id = ?
      GROUP BY o.id
      LIMIT 1
      ''',
      [id],
    );

    if (resultado.isEmpty) {
      return null;
    }

    final detalhes = Map<String, dynamic>.from(resultado.first);

    final itens = await listarItensDoOrcamento(id);
    final mapeamento = await buscarMapeamentoCatalogo(id);

    detalhes['itens'] = List<Map<String, dynamic>>.generate(
      itens.length,
      (indice) => {
        ...itens[indice].toMap(),
        'servico_catalogo_id': mapeamento[indice],
      },
    );

    return detalhes;
  }

  Future<Orcamento?> buscarPorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'orcamentos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    final itens = await listarItensDoOrcamento(id);

    return Orcamento.fromMap(resultado.first, itens: itens);
  }

  Future<List<ItemOrcamento>> listarItensDoOrcamento(int orcamentoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'orcamento_itens',
      where: 'orcamento_id = ?',
      whereArgs: [orcamentoId],
      orderBy: 'ordem ASC, id ASC',
    );

    return resultado.map(ItemOrcamento.fromMap).toList();
  }

  Future<int> atualizarOrcamento(
    Orcamento orcamento, {
    String? perfilPreco,
    Map<int, int?>? servicoCatalogoPorOrdem,
  }) async {
    final orcamentoId = orcamento.id;

    if (orcamentoId == null) {
      throw ArgumentError('Não é possível atualizar um orçamento sem ID.');
    }

    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
      await _garantirEstruturaPerfil(transaction);

      final quantidadeAtualizada = await transaction.update(
        'orcamentos',
        _dadosPrincipais(orcamento),
        where: 'id = ?',
        whereArgs: [orcamentoId],
      );

      await transaction.delete(
        'orcamento_itens',
        where: 'orcamento_id = ?',
        whereArgs: [orcamentoId],
      );

      await _salvarItens(
        transaction: transaction,
        orcamentoId: orcamentoId,
        itens: orcamento.itens,
        orcamentoAntigo: orcamento,
      );

      if (perfilPreco != null) {
        await _salvarPerfilComExecutor(
          transaction,
          orcamentoId: orcamentoId,
          perfil: perfilPreco,
        );
      }

      if (servicoCatalogoPorOrdem != null) {
        await _salvarMapeamentoCatalogo(
          transaction,
          orcamentoId: orcamentoId,
          servicoCatalogoPorOrdem: servicoCatalogoPorOrdem,
        );
      }

      return quantidadeAtualizada;
    });
  }

  Future<Map<int, int>> buscarMapeamentoCatalogo(int orcamentoId) async {
    final database = await _appDatabase.database;
    await _garantirEstruturaPerfil(database);

    final rows = await database.query(
      'financeiro_orcamento_item_catalogo',
      columns: ['ordem', 'servico_catalogo_id'],
      where: 'orcamento_id = ?',
      whereArgs: [orcamentoId],
      orderBy: 'ordem ASC',
    );

    final resultado = <int, int>{};

    for (final row in rows) {
      final ordem = _converterInt(row['ordem']);
      final servicoId = _converterInt(row['servico_catalogo_id']);

      if (ordem != null && servicoId != null && servicoId > 0) {
        resultado[ordem] = servicoId;
      }
    }

    return resultado;
  }

  Future<void> registrarPerfilPreco(int orcamentoId, String perfil) async {
    if (orcamentoId <= 0) {
      throw ArgumentError('Orçamento inválido.');
    }

    final database = await _appDatabase.database;
    await _garantirEstruturaPerfil(database);
    await _salvarPerfilComExecutor(
      database,
      orcamentoId: orcamentoId,
      perfil: perfil,
    );
  }

  Future<String> buscarPerfilPreco(int orcamentoId) async {
    final database = await _appDatabase.database;
    await _garantirEstruturaPerfil(database);

    final resultado = await database.query(
      'financeiro_preco_documentos',
      columns: ['perfil'],
      where: 'documento_tipo = ? AND documento_id = ?',
      whereArgs: ['ORCAMENTO', orcamentoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return 'informado';
    }

    final perfil = (resultado.first['perfil'] ?? '').toString().trim();
    return perfil.isEmpty ? 'informado' : perfil;
  }

  Future<int> atualizarStatus(int id, String status) async {
    final database = await _appDatabase.database;

    return database.update(
      'orcamentos',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirOrcamento(int id) async {
    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
      await _garantirEstruturaPerfil(transaction);

      await transaction.delete(
        'orcamento_itens',
        where: 'orcamento_id = ?',
        whereArgs: [id],
      );

      await transaction.delete(
        'financeiro_preco_documentos',
        where: 'documento_tipo = ? AND documento_id = ?',
        whereArgs: ['ORCAMENTO', id],
      );

      await transaction.delete(
        'financeiro_orcamento_item_catalogo',
        where: 'orcamento_id = ?',
        whereArgs: [id],
      );

      final tabelaDesconto = await transaction.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name = 'financeiro_desconto_documentos'
        LIMIT 1
        ''');

      if (tabelaDesconto.isNotEmpty) {
        await transaction.delete(
          'financeiro_desconto_documentos',
          where: 'documento_tipo = ? AND documento_id = ?',
          whereArgs: ['ORCAMENTO', id],
        );
      }

      return transaction.delete('orcamentos', where: 'id = ?', whereArgs: [id]);
    });
  }

  int? _converterInt(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  Map<String, dynamic> _dadosPrincipais(Orcamento orcamento) {
    final dados = orcamento.toMap();

    dados.remove('id');

    return dados;
  }

  Future<void> _salvarItens({
    required Transaction transaction,
    required int orcamentoId,
    required List<ItemOrcamento> itens,
    required Orcamento orcamentoAntigo,
  }) async {
    final itensParaSalvar = itens.isNotEmpty
        ? itens
        : _criarItemDeCompatibilidade(orcamentoAntigo);

    for (var indice = 0; indice < itensParaSalvar.length; indice++) {
      final item = itensParaSalvar[indice];

      final dadosItem = item
          .copyWith(orcamentoId: orcamentoId, ordem: indice)
          .toMap();

      dadosItem.remove('id');

      await transaction.insert('orcamento_itens', dadosItem);
    }
  }

  List<ItemOrcamento> _criarItemDeCompatibilidade(Orcamento orcamento) {
    final servico = orcamento.servico.trim();

    final descricao = orcamento.descricao.trim();

    final valor = orcamento.valor > 0 ? orcamento.valor : orcamento.valorTotal;

    if (servico.isEmpty && valor <= 0) {
      return [];
    }

    return [
      ItemOrcamento(
        servico: servico.isEmpty ? 'Serviço' : servico,
        descricao: descricao,
        quantidade: 1,
        valorUnitario: valor,
        ordem: 0,
      ),
    ];
  }
}
