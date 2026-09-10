import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/movimento_financeiro.dart';

class NotaFiscalFinanceiroResumo {
  const NotaFiscalFinanceiroResumo({
    required this.status,
    required this.valorTotal,
    required this.valorPago,
    required this.valorPrevisto,
    required this.movimentos,
  });

  final String status;
  final double valorTotal;
  final double valorPago;
  final double valorPrevisto;
  final List<MovimentoFinanceiro> movimentos;

  bool get possuiLancamentosAtivos =>
      movimentos.any((item) => item.status != 'Cancelado');
}

class NotaFiscalFinanceiroService {
  NotaFiscalFinanceiroService({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => AppDatabase.instance.database);

  final Future<Database> Function() _databaseProvider;

  Future<List<Map<String, dynamic>>> listarContasAtivas() async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'financeiro_contas',
      columns: ['id', 'nome', 'tipo', 'instituicao', 'ativo'],
      where: 'ativo = 1',
      orderBy: 'nome COLLATE NOCASE ASC',
    );
    return rows.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> listarCategoriasCompra() async {
    final database = await _databaseProvider();
    final rows = await database.rawQuery('''
      SELECT
        pc.id,
        pc.codigo,
        pc.nome,
        pc.natureza,
        pc.grupo_dre,
        pc.tipo
      FROM financeiro_plano_contas pc
      WHERE pc.ativo = 1
        AND LOWER(pc.tipo) IN ('saída', 'saida')
        AND pc.codigo != '2.03.01'
        AND NOT EXISTS (
          SELECT 1
          FROM financeiro_plano_contas filho
          WHERE filho.parent_id = pc.id
            AND filho.ativo = 1
        )
      ORDER BY pc.ordem ASC, pc.codigo ASC, pc.nome COLLATE NOCASE ASC
    ''');
    return rows.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<int?> categoriaPadraoId(int notaFiscalId) async {
    final database = await _databaseProvider();
    final itens =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM notas_fiscais_entrada_itens
            WHERE nota_fiscal_id = ?
            ''',
            [notaFiscalId],
          ),
        ) ??
        0;

    var todosNoEstoque = itens > 0;
    if (todosNoEstoque) {
      final entradas =
          Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT COUNT(DISTINCT nota_fiscal_item_id)
              FROM movimentacoes_estoque
              WHERE nota_fiscal_id = ?
                AND nota_fiscal_item_id IS NOT NULL
                AND tipo = 'ENTRADA'
                AND origem = 'Nota fiscal de entrada'
              ''',
              [notaFiscalId],
            ),
          ) ??
          0;
      todosNoEstoque = entradas >= itens;
    }

    final codigo = todosNoEstoque ? '9.06' : '2.99.01';
    final rows = await database.query(
      'financeiro_plano_contas',
      columns: ['id'],
      where: 'codigo = ? AND ativo = 1',
      whereArgs: [codigo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _int(rows.first['id']);
  }

  Future<NotaFiscalFinanceiroResumo> obterResumo(int notaFiscalId) async {
    final database = await _databaseProvider();
    final nota = await _buscarNota(database, notaFiscalId);
    final movimentos = await _listarMovimentos(database, notaFiscalId);

    final ativos = movimentos
        .where((item) => item.status != 'Cancelado')
        .toList();
    final valorPago = ativos
        .where((item) => item.status == 'Realizado')
        .fold<double>(0, (total, item) => total + item.valor);
    final valorPrevisto = ativos
        .where((item) => item.status == 'Previsto')
        .fold<double>(0, (total, item) => total + item.valor);

    String status;
    if (ativos.isEmpty) {
      status = movimentos.any((item) => item.status == 'Cancelado')
          ? 'Cancelado'
          : 'Não lançado';
    } else if (ativos.every((item) => item.status == 'Realizado')) {
      status = 'Pago';
    } else if (ativos.any((item) => item.status == 'Realizado')) {
      status = 'Parcialmente pago';
    } else {
      status = 'Previsto';
    }

    return NotaFiscalFinanceiroResumo(
      status: status,
      valorTotal: _double(nota['valor_total']),
      valorPago: valorPago,
      valorPrevisto: valorPrevisto,
      movimentos: movimentos,
    );
  }

  Future<List<int>> criarLancamento({
    required int notaFiscalId,
    required bool jaPago,
    required int planoContaId,
    int? contaId,
    required String formaPagamento,
    DateTime? dataPagamento,
    int totalParcelas = 1,
    DateTime? primeiroVencimento,
  }) async {
    if (totalParcelas < 1 || totalParcelas > 48) {
      throw ArgumentError('A quantidade de parcelas deve ficar entre 1 e 48.');
    }
    if (jaPago && totalParcelas != 1) {
      throw ArgumentError(
        'Uma compra já paga deve ser lançada como pagamento único.',
      );
    }
    if (jaPago && contaId == null) {
      throw StateError('Selecione a conta utilizada no pagamento.');
    }
    if (!jaPago && primeiroVencimento == null) {
      throw ArgumentError('Informe o primeiro vencimento.');
    }

    final database = await _databaseProvider();
    return database.transaction<List<int>>((transaction) async {
      final nota = await _buscarNota(transaction, notaFiscalId);
      if ((nota['status_importacao'] ?? '').toString() != 'processada') {
        throw StateError(
          'A nota precisa estar processada antes do lançamento financeiro.',
        );
      }
      final situacaoFiscal = (nota['situacao_fiscal'] ?? '').toString();
      if (situacaoFiscal != 'autorizada') {
        throw StateError(
          'Somente documento fiscal autorizado pode gerar lançamento financeiro. '
          'Situação atual: $situacaoFiscal.',
        );
      }

      final valorTotal = _double(nota['valor_total']);
      if (valorTotal <= 0) {
        throw StateError(
          'A nota precisa possuir valor total maior que zero para o financeiro.',
        );
      }

      final existentes = await transaction.query(
        'movimentos_financeiros',
        columns: ['id'],
        where:
            "nota_fiscal_id = ? AND origem = 'Nota fiscal de entrada' "
            "AND status != 'Cancelado'",
        whereArgs: [notaFiscalId],
        limit: 1,
      );
      if (existentes.isNotEmpty) {
        throw StateError(
          'Esta nota já possui lançamento financeiro ativo. '
          'Reabra o financeiro da nota para consultar ou baixar as parcelas.',
        );
      }

      final categoria = await transaction.query(
        'financeiro_plano_contas',
        columns: ['id', 'codigo', 'natureza', 'grupo_dre', 'tipo', 'ativo'],
        where: 'id = ?',
        whereArgs: [planoContaId],
        limit: 1,
      );
      if (categoria.isEmpty || _int(categoria.first['ativo']) != 1) {
        throw StateError('A categoria financeira selecionada não está ativa.');
      }
      final tipoPlano = (categoria.first['tipo'] ?? '')
          .toString()
          .toLowerCase();
      if (tipoPlano != 'saída' && tipoPlano != 'saida') {
        throw StateError('Selecione uma categoria financeira de saída.');
      }
      final codigoPlano = (categoria.first['codigo'] ?? '').toString();
      if (codigoPlano == '2.03.01') {
        throw StateError(
          'Produtos consumidos em serviços são reconhecidos pelo FIFO. '
          'Para a compra do estoque use "Compra para estoque".',
        );
      }

      if (contaId != null) {
        await _validarContaAtiva(transaction, contaId);
      }

      final competencia = _dataCompetencia(nota);
      final pagamento = dataPagamento ?? DateTime.now();
      final valores = _dividirValor(valorTotal, totalParcelas);
      final ids = <int>[];
      final emitente = (nota['emitente_nome'] ?? 'Fornecedor')
          .toString()
          .trim();
      final modelo = _int(nota['modelo']);
      final numero = (nota['numero'] ?? '').toString().trim();
      final serie = (nota['serie'] ?? '').toString().trim();
      final tipoDocumento = modelo == 65 ? 'NFC-e' : 'NF-e';
      final numeroExibicao = numero.isEmpty
          ? (nota['chave_acesso'] ?? '').toString().substring(0, 8)
          : numero;
      final documentoBase = serie.isEmpty
          ? '$tipoDocumento $numeroExibicao'
          : '$tipoDocumento $numeroExibicao série $serie';
      final natureza = (categoria.first['natureza'] ?? 'Compra').toString();
      final impactaDre =
          (categoria.first['grupo_dre'] ?? '').toString() != 'Não DRE';
      final forma = formaPagamento.trim().isEmpty
          ? (jaPago ? 'Outro' : 'A definir')
          : formaPagamento.trim();

      for (var indice = 0; indice < totalParcelas; indice++) {
        final parcela = indice + 1;
        final vencimento = jaPago
            ? null
            : _adicionarMeses(primeiroVencimento!, indice);
        final dataBase = jaPago ? pagamento : vencimento!;
        final descricao = totalParcelas == 1
            ? 'Compra $documentoBase - $emitente'
            : 'Compra $documentoBase - $emitente - Parcela '
                  '$parcela/$totalParcelas';

        final id = await transaction.insert('movimentos_financeiros', {
          'tipo': 'Saída',
          'descricao': descricao,
          'valor': valores[indice],
          'forma_pagamento': forma,
          'data': dataBase.toIso8601String(),
          'cliente_id': null,
          'agendamento_id': null,
          'ordem_servico_id': null,
          'pagamento_id': null,
          'plano_conta_id': planoContaId,
          'conta_id': contaId,
          'fornecedor_id': _intNulo(nota['fornecedor_id']),
          'transferencia_id': null,
          'nota_fiscal_id': notaFiscalId,
          'parcela_numero': parcela,
          'total_parcelas': totalParcelas,
          'natureza': natureza,
          'origem': 'Nota fiscal de entrada',
          'status': jaPago ? 'Realizado' : 'Previsto',
          'data_competencia': competencia.toIso8601String(),
          'data_vencimento': vencimento?.toIso8601String(),
          'data_pagamento': jaPago ? pagamento.toIso8601String() : null,
          'numero_documento': totalParcelas == 1
              ? documentoBase
              : '$documentoBase $parcela/$totalParcelas',
          'observacoes':
              'Chave de acesso: ${(nota['chave_acesso'] ?? '').toString()}',
          'impacta_dre': impactaDre ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        ids.add(id);
      }

      return ids;
    });
  }

  Future<void> marcarParcelaComoPaga({
    required int movimentoId,
    required int contaId,
    required DateTime dataPagamento,
    required String formaPagamento,
  }) async {
    final database = await _databaseProvider();
    await database.transaction<void>((transaction) async {
      final rows = await transaction.query(
        'movimentos_financeiros',
        where:
            "id = ? AND nota_fiscal_id IS NOT NULL "
            "AND origem = 'Nota fiscal de entrada'",
        whereArgs: [movimentoId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Parcela financeira da nota não encontrada.');
      }
      if ((rows.first['status'] ?? '').toString() != 'Previsto') {
        throw StateError('Somente parcelas previstas podem ser baixadas.');
      }

      await _validarContaAtiva(transaction, contaId);
      final forma = formaPagamento.trim();
      if (forma.isEmpty) {
        throw ArgumentError('Informe a forma de pagamento.');
      }

      await transaction.update(
        'movimentos_financeiros',
        {
          'status': 'Realizado',
          'conta_id': contaId,
          'forma_pagamento': forma,
          'data_pagamento': dataPagamento.toIso8601String(),
          'data': dataPagamento.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [movimentoId],
      );
    });
  }

  Future<void> cancelarPlanejamento(int notaFiscalId) async {
    final database = await _databaseProvider();
    await database.transaction<void>((transaction) async {
      final realizados =
          Sqflite.firstIntValue(
            await transaction.rawQuery(
              '''
              SELECT COUNT(*)
              FROM movimentos_financeiros
              WHERE nota_fiscal_id = ?
                AND origem = 'Nota fiscal de entrada'
                AND status = 'Realizado'
              ''',
              [notaFiscalId],
            ),
          ) ??
          0;
      if (realizados > 0) {
        throw StateError(
          'Não é possível cancelar o planejamento porque já existe pagamento realizado.',
        );
      }

      await transaction.update(
        'movimentos_financeiros',
        {'status': 'Cancelado'},
        where:
            "nota_fiscal_id = ? AND origem = 'Nota fiscal de entrada' "
            "AND status = 'Previsto'",
        whereArgs: [notaFiscalId],
      );
    });
  }

  Future<Map<String, Object?>> _buscarNota(
    DatabaseExecutor database,
    int notaFiscalId,
  ) async {
    final rows = await database.query(
      'notas_fiscais_entrada',
      where: 'id = ?',
      whereArgs: [notaFiscalId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Nota fiscal não encontrada.');
    }
    return rows.first;
  }

  Future<List<MovimentoFinanceiro>> _listarMovimentos(
    DatabaseExecutor database,
    int notaFiscalId,
  ) async {
    final rows = await database.query(
      'movimentos_financeiros',
      where: "nota_fiscal_id = ? AND origem = 'Nota fiscal de entrada'",
      whereArgs: [notaFiscalId],
      orderBy: 'parcela_numero ASC, id ASC',
    );
    return rows
        .map(
          (item) =>
              MovimentoFinanceiro.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> _validarContaAtiva(
    DatabaseExecutor database,
    int contaId,
  ) async {
    final rows = await database.query(
      'financeiro_contas',
      columns: ['id', 'ativo'],
      where: 'id = ?',
      whereArgs: [contaId],
      limit: 1,
    );
    if (rows.isEmpty || _int(rows.first['ativo']) != 1) {
      throw StateError('A conta financeira selecionada não está ativa.');
    }
  }

  static DateTime _dataCompetencia(Map<String, Object?> nota) {
    final valor = (nota['data_emissao'] ?? '').toString().trim();
    final data = DateTime.tryParse(valor);
    if (data == null) {
      throw StateError('A nota fiscal não possui data de emissão válida.');
    }
    return data;
  }

  static List<double> _dividirValor(double valor, int parcelas) {
    final centavos = (valor * 100).round();
    final base = centavos ~/ parcelas;
    final resto = centavos % parcelas;
    return List<double>.generate(
      parcelas,
      (indice) => (base + (indice < resto ? 1 : 0)) / 100,
    );
  }

  static DateTime _adicionarMeses(DateTime data, int meses) {
    final primeiroDoMes = DateTime(data.year, data.month + meses, 1);
    final proximoMes = DateTime(primeiroDoMes.year, primeiroDoMes.month + 1, 1);
    final ultimoDia = proximoMes.subtract(const Duration(days: 1)).day;
    final dia = data.day > ultimoDia ? ultimoDia : data.day;
    return DateTime(
      primeiroDoMes.year,
      primeiroDoMes.month,
      dia,
      data.hour,
      data.minute,
      data.second,
      data.millisecond,
      data.microsecond,
    );
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    final convertido = _int(valor);
    return convertido <= 0 ? null : convertido;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
