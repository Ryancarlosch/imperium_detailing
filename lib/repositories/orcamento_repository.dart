import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/item_orcamento.dart';
import '../models/orcamento.dart';

class OrcamentoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<int> inserirOrcamento(Orcamento orcamento) async {
    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
      final dadosOrcamento = _dadosPrincipais(orcamento);

      final orcamentoId = await transaction.insert(
        'orcamentos',
        dadosOrcamento,
      );

      await _salvarItens(
        transaction: transaction,
        orcamentoId: orcamentoId,
        itens: orcamento.itens,
        orcamentoAntigo: orcamento,
      );

      return orcamentoId;
    });
  }

  Future<List<Map<String, dynamic>>> listarOrcamentosComDetalhes() async {
    final database = await _appDatabase.database;

    return database.rawQuery('''
      SELECT
        o.*,
        c.nome AS cliente_nome,
        c.telefone AS cliente_telefone,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa,
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
      GROUP BY o.id
      ORDER BY
        o.data_emissao DESC,
        o.id DESC
    ''');
  }

  Future<Map<String, dynamic>?> buscarOrcamentoComDetalhes(int id) async {
    final database = await _appDatabase.database;

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

    detalhes['itens'] = itens.map((item) => item.toMap()).toList();

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

  Future<int> atualizarOrcamento(Orcamento orcamento) async {
    final orcamentoId = orcamento.id;

    if (orcamentoId == null) {
      throw ArgumentError('Não é possível atualizar um orçamento sem ID.');
    }

    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
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

      return quantidadeAtualizada;
    });
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
      await transaction.delete(
        'orcamento_itens',
        where: 'orcamento_id = ?',
        whereArgs: [id],
      );

      return transaction.delete('orcamentos', where: 'id = ?', whereArgs: [id]);
    });
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
