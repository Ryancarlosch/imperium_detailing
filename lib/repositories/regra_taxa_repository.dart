import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/regra_taxa_cartao.dart';

class RegraTaxaRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<List<RegraTaxaCartao>> listar({bool incluirInativas = false}) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'financeiro_regras_taxa',
      where: incluirInativas ? null : 'ativo = 1',
      orderBy:
          'ativo DESC, forma_pagamento ASC, parcelas ASC, prioridade DESC, nome COLLATE NOCASE ASC',
    );
    return resultado
        .map((item) => RegraTaxaCartao.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<int> salvar(RegraTaxaCartao regra) async {
    final nome = regra.nome.trim();
    final forma = regra.formaPagamento.trim();

    if (nome.length < 2) {
      throw ArgumentError('Informe o nome da regra.');
    }
    if (forma != 'Cartão de crédito' && forma != 'Cartão de débito') {
      throw ArgumentError('Forma de pagamento inválida para regra de taxa.');
    }
    if (regra.parcelas < 1 || regra.parcelas > 48) {
      throw ArgumentError('As parcelas devem ficar entre 1 e 48.');
    }
    if (regra.taxaPercentual < 0 || regra.taxaPercentual > 100) {
      throw ArgumentError('A taxa percentual deve ficar entre 0% e 100%.');
    }
    if (regra.repassarCliente && regra.taxaPercentual >= 100) {
      throw ArgumentError(
        'Para repassar ao cliente, a taxa percentual deve ser menor que 100%.',
      );
    }
    if (regra.taxaFixa < 0) {
      throw ArgumentError('A taxa fixa não pode ser negativa.');
    }
    if (regra.prazoRecebimentoDias < 0) {
      throw ArgumentError('O prazo de recebimento não pode ser negativo.');
    }

    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();

    return database.transaction((transaction) async {
      if (regra.ativo) {
        final filtros = <String>[
          'forma_pagamento = ?',
          'parcelas = ?',
          'ativo = 1',
        ];
        final args = <Object?>[forma, regra.parcelas];
        if (regra.contaId == null) {
          filtros.add('conta_id IS NULL');
        } else {
          filtros.add('conta_id = ?');
          args.add(regra.contaId);
        }
        if (regra.id != null) {
          filtros.add('id <> ?');
          args.add(regra.id);
        }
        await transaction.update(
          'financeiro_regras_taxa',
          {'ativo': 0, 'atualizado_em': agora},
          where: filtros.join(' AND '),
          whereArgs: args,
        );
      }

      final mapa = regra.toMap(incluirId: false)
        ..['nome'] = nome
        ..['forma_pagamento'] = forma
        ..['atualizado_em'] = agora;

      if (regra.id == null) {
        mapa['criado_em'] = agora;
        return transaction.insert(
          'financeiro_regras_taxa',
          mapa,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      await transaction.update(
        'financeiro_regras_taxa',
        mapa,
        where: 'id = ?',
        whereArgs: [regra.id],
      );
      return regra.id!;
    });
  }

  Future<void> arquivar(int id) async {
    final database = await _appDatabase.database;
    await database.update(
      'financeiro_regras_taxa',
      {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<RegraTaxaCartao?> buscarAplicavel({
    required String formaPagamento,
    required int parcelas,
    int? contaId,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.rawQuery(
      '''
      SELECT *
      FROM financeiro_regras_taxa
      WHERE ativo = 1
        AND forma_pagamento = ?
        AND parcelas = ?
        AND (conta_id = ? OR conta_id IS NULL)
      ORDER BY
        CASE WHEN conta_id = ? THEN 0 ELSE 1 END,
        prioridade DESC,
        id DESC
      LIMIT 1
      ''',
      [formaPagamento.trim(), parcelas, contaId, contaId],
    );

    if (resultado.isEmpty) {
      return null;
    }
    return RegraTaxaCartao.fromMap(Map<String, dynamic>.from(resultado.first));
  }

  Future<Map<String, dynamic>?> calcular({
    required String formaPagamento,
    required int parcelas,
    required double valor,
    int? contaId,
  }) async {
    final regra = await buscarAplicavel(
      formaPagamento: formaPagamento,
      parcelas: parcelas,
      contaId: contaId,
    );
    if (regra == null) {
      return null;
    }

    final valorCobrado = regra.calcularValorCobrado(valor);
    final taxa = regra.calcularTaxa(valorCobrado);
    final acrescimo = (valorCobrado - valor)
        .clamp(0, double.infinity)
        .toDouble();

    return {
      'id': regra.id,
      'nome': regra.nome,
      'taxa_percentual': regra.taxaPercentual,
      'taxa_fixa': regra.taxaFixa,
      'taxa_operacao': taxa,
      'valor_base': valor,
      'valor_cobrado': valorCobrado,
      'acrescimo_cliente': acrescimo,
      'valor_liquido': (valorCobrado - taxa)
          .clamp(0, double.infinity)
          .toDouble(),
      'repassar_cliente': regra.repassarCliente,
      'parcelas': regra.parcelas,
      'prazo_recebimento_dias': regra.prazoRecebimentoDias,
    };
  }
}
