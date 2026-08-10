import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class FidelidadeFaixa {
  const FidelidadeFaixa({
    required this.mesesMinimos,
    required this.percentual,
    this.ativo = true,
    this.ordem = 0,
  });

  final int mesesMinimos;
  final double percentual;
  final bool ativo;
  final int ordem;
}

class FidelidadeConfig {
  const FidelidadeConfig({
    this.modo = 'desativado',
    this.descontoMaximoPercentual = 10,
    this.permitirParceiro = false,
    this.faixas = const <FidelidadeFaixa>[
      FidelidadeFaixa(mesesMinimos: 12, percentual: 3, ordem: 0),
      FidelidadeFaixa(mesesMinimos: 24, percentual: 5, ordem: 1),
      FidelidadeFaixa(mesesMinimos: 36, percentual: 7, ordem: 2),
    ],
  });

  final String modo;
  final double descontoMaximoPercentual;
  final bool permitirParceiro;
  final List<FidelidadeFaixa> faixas;

  bool get ativa => modo != 'desativado';
  bool get sugerir => modo == 'sugerir';
  bool get automatica => modo == 'automatico';
}

class FidelidadeBeneficio {
  const FidelidadeBeneficio({
    required this.clienteId,
    required this.clienteDesde,
    required this.mesesRelacionamento,
    required this.percentual,
    required this.faixaMeses,
  });

  final int clienteId;
  final DateTime? clienteDesde;
  final int mesesRelacionamento;
  final double percentual;
  final int? faixaMeses;

  bool get elegivel => clienteDesde != null && percentual > 0;
}

class DescontoDocumentoSnapshot {
  const DescontoDocumentoSnapshot({
    required this.documentoTipo,
    required this.documentoId,
    required this.origem,
    required this.valorDesconto,
    required this.percentual,
    required this.valorSugerido,
    this.clienteDesde,
    this.faixaMeses,
    this.perfilPreco = 'informado',
  });

  final String documentoTipo;
  final int documentoId;
  final String origem;
  final double valorDesconto;
  final double percentual;
  final double valorSugerido;
  final DateTime? clienteDesde;
  final int? faixaMeses;
  final String perfilPreco;
}

class FidelidadeRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  static const Set<String> _modosValidos = {
    'desativado',
    'sugerir',
    'automatico',
  };

  Future<void> _garantirEstrutura(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_fidelidade_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        modo TEXT NOT NULL DEFAULT 'desativado',
        desconto_maximo_percentual REAL NOT NULL DEFAULT 10,
        permitir_parceiro INTEGER NOT NULL DEFAULT 0,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_fidelidade_faixas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        meses_minimos INTEGER NOT NULL,
        percentual REAL NOT NULL,
        ativo INTEGER NOT NULL DEFAULT 1,
        ordem INTEGER NOT NULL DEFAULT 0,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_cliente_fidelidade (
        cliente_id INTEGER PRIMARY KEY,
        cliente_desde TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_desconto_documentos (
        documento_tipo TEXT NOT NULL,
        documento_id INTEGER NOT NULL,
        origem TEXT NOT NULL,
        valor_desconto REAL NOT NULL DEFAULT 0,
        percentual REAL NOT NULL DEFAULT 0,
        valor_sugerido REAL NOT NULL DEFAULT 0,
        cliente_desde TEXT,
        faixa_meses INTEGER,
        perfil_preco TEXT NOT NULL DEFAULT 'informado',
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (documento_tipo, documento_id)
      )
    ''');

    final agora = DateTime.now().toIso8601String();

    await executor.insert(
      'financeiro_fidelidade_config',
      {
        'id': 1,
        'modo': 'desativado',
        'desconto_maximo_percentual': 10,
        'permitir_parceiro': 0,
        'atualizado_em': agora,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final quantidade = Sqflite.firstIntValue(
          await executor.rawQuery(
            'SELECT COUNT(*) FROM financeiro_fidelidade_faixas',
          ),
        ) ??
        0;

    if (quantidade == 0) {
      final padroes = <Map<String, dynamic>>[
        {'meses': 12, 'percentual': 3.0, 'ordem': 0},
        {'meses': 24, 'percentual': 5.0, 'ordem': 1},
        {'meses': 36, 'percentual': 7.0, 'ordem': 2},
      ];

      for (final item in padroes) {
        await executor.insert(
          'financeiro_fidelidade_faixas',
          {
            'meses_minimos': item['meses'],
            'percentual': item['percentual'],
            'ativo': 1,
            'ordem': item['ordem'],
            'atualizado_em': agora,
          },
        );
      }
    }
  }

  Future<FidelidadeConfig> carregarConfig() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final configRows = await database.query(
      'financeiro_fidelidade_config',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    final config = configRows.isEmpty
        ? const <String, dynamic>{}
        : configRows.first;

    final faixasRows = await database.query(
      'financeiro_fidelidade_faixas',
      orderBy: 'meses_minimos ASC, ordem ASC, id ASC',
    );

    final faixas = faixasRows
        .map(
          (item) => FidelidadeFaixa(
            mesesMinimos: _int(item['meses_minimos']),
            percentual: _double(item['percentual']),
            ativo: _bool(item['ativo']),
            ordem: _int(item['ordem']),
          ),
        )
        .where((item) => item.mesesMinimos > 0)
        .toList();

    return FidelidadeConfig(
      modo: _modo(config['modo']?.toString()),
      descontoMaximoPercentual: _double(
        config['desconto_maximo_percentual'],
        padrao: 10,
      ),
      permitirParceiro: _bool(config['permitir_parceiro']),
      faixas: faixas.isEmpty
          ? const FidelidadeConfig().faixas
          : List<FidelidadeFaixa>.unmodifiable(faixas),
    );
  }

  Future<void> salvarConfig(FidelidadeConfig config) async {
    if (!_modosValidos.contains(config.modo)) {
      throw ArgumentError('Modo de fidelidade inválido.');
    }

    if (config.descontoMaximoPercentual < 0 ||
        config.descontoMaximoPercentual >= 95) {
      throw ArgumentError(
        'O desconto máximo de fidelidade deve ficar entre 0% e 94,9%.',
      );
    }

    final faixasAtivas = config.faixas.where((item) => item.ativo).toList();

    for (final faixa in faixasAtivas) {
      if (faixa.mesesMinimos <= 0) {
        throw ArgumentError('O tempo mínimo da fidelidade deve ser positivo.');
      }

      if (faixa.percentual < 0 || faixa.percentual >= 95) {
        throw ArgumentError(
          'Os percentuais de fidelidade devem ficar entre 0% e 94,9%.',
        );
      }
    }

    final ordenadas = [...config.faixas]
      ..sort((a, b) => a.mesesMinimos.compareTo(b.mesesMinimos));

    for (var i = 1; i < ordenadas.length; i++) {
      if (ordenadas[i].mesesMinimos == ordenadas[i - 1].mesesMinimos) {
        throw ArgumentError(
          'Não use duas faixas de fidelidade com o mesmo tempo mínimo.',
        );
      }
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _garantirEstrutura(transaction);

      final agora = DateTime.now().toIso8601String();

      await transaction.update(
        'financeiro_fidelidade_config',
        {
          'modo': config.modo,
          'desconto_maximo_percentual': config.descontoMaximoPercentual,
          'permitir_parceiro': config.permitirParceiro ? 1 : 0,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [1],
      );

      await transaction.delete('financeiro_fidelidade_faixas');

      for (var i = 0; i < ordenadas.length; i++) {
        final faixa = ordenadas[i];

        await transaction.insert(
          'financeiro_fidelidade_faixas',
          {
            'meses_minimos': faixa.mesesMinimos,
            'percentual': faixa.percentual,
            'ativo': faixa.ativo ? 1 : 0,
            'ordem': i,
            'atualizado_em': agora,
          },
        );
      }
    });
  }

  Future<DateTime?> buscarClienteDesde(int clienteId) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final rows = await database.query(
      'financeiro_cliente_fidelidade',
      columns: ['cliente_desde'],
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return DateTime.tryParse((rows.first['cliente_desde'] ?? '').toString());
  }

  Future<void> salvarClienteDesde(
    int clienteId,
    DateTime? clienteDesde,
  ) async {
    if (clienteId <= 0) {
      throw ArgumentError('Cliente inválido.');
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    if (clienteDesde == null) {
      await database.delete(
        'financeiro_cliente_fidelidade',
        where: 'cliente_id = ?',
        whereArgs: [clienteId],
      );
      return;
    }

    final data = DateTime(
      clienteDesde.year,
      clienteDesde.month,
      clienteDesde.day,
    );

    if (data.isAfter(DateTime.now())) {
      throw ArgumentError('A data "Cliente desde" não pode estar no futuro.');
    }

    final agora = DateTime.now().toIso8601String();

    await database.insert(
      'financeiro_cliente_fidelidade',
      {
        'cliente_id': clienteId,
        'cliente_desde': data.toIso8601String(),
        'atualizado_em': agora,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<FidelidadeBeneficio> avaliarCliente(
    int clienteId, {
    DateTime? dataReferencia,
  }) async {
    final config = await carregarConfig();
    final clienteDesde = await buscarClienteDesde(clienteId);
    final referencia = dataReferencia ?? DateTime.now();

    if (clienteDesde == null) {
      return FidelidadeBeneficio(
        clienteId: clienteId,
        clienteDesde: null,
        mesesRelacionamento: 0,
        percentual: 0,
        faixaMeses: null,
      );
    }

    final meses = _mesesCompletos(clienteDesde, referencia);

    FidelidadeFaixa? escolhida;

    for (final faixa in config.faixas) {
      if (!faixa.ativo || meses < faixa.mesesMinimos) {
        continue;
      }

      if (escolhida == null ||
          faixa.mesesMinimos > escolhida.mesesMinimos) {
        escolhida = faixa;
      }
    }

    final percentual = escolhida == null
        ? 0.0
        : escolhida.percentual.clamp(
            0,
            config.descontoMaximoPercentual,
          ).toDouble();

    return FidelidadeBeneficio(
      clienteId: clienteId,
      clienteDesde: clienteDesde,
      mesesRelacionamento: meses,
      percentual: percentual,
      faixaMeses: escolhida?.mesesMinimos,
    );
  }

  Future<void> registrarDescontoDocumento(
    DescontoDocumentoSnapshot snapshot,
  ) async {
    if (snapshot.documentoId <= 0) {
      throw ArgumentError('Documento inválido para registrar desconto.');
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    await database.insert(
      'financeiro_desconto_documentos',
      {
        'documento_tipo': snapshot.documentoTipo.trim().toUpperCase(),
        'documento_id': snapshot.documentoId,
        'origem': snapshot.origem.trim().isEmpty
            ? 'manual'
            : snapshot.origem.trim(),
        'valor_desconto': snapshot.valorDesconto,
        'percentual': snapshot.percentual,
        'valor_sugerido': snapshot.valorSugerido,
        'cliente_desde': snapshot.clienteDesde?.toIso8601String(),
        'faixa_meses': snapshot.faixaMeses,
        'perfil_preco': snapshot.perfilPreco,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DescontoDocumentoSnapshot?> buscarDescontoDocumento({
    required String documentoTipo,
    required int documentoId,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final rows = await database.query(
      'financeiro_desconto_documentos',
      where: 'documento_tipo = ? AND documento_id = ?',
      whereArgs: [documentoTipo.trim().toUpperCase(), documentoId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final item = rows.first;

    return DescontoDocumentoSnapshot(
      documentoTipo: (item['documento_tipo'] ?? '').toString(),
      documentoId: _int(item['documento_id']),
      origem: (item['origem'] ?? 'manual').toString(),
      valorDesconto: _double(item['valor_desconto']),
      percentual: _double(item['percentual']),
      valorSugerido: _double(item['valor_sugerido']),
      clienteDesde: DateTime.tryParse(
        (item['cliente_desde'] ?? '').toString(),
      ),
      faixaMeses: item['faixa_meses'] == null
          ? null
          : _int(item['faixa_meses']),
      perfilPreco: (item['perfil_preco'] ?? 'informado').toString(),
    );
  }

  Future<void> excluirDescontoDocumento({
    required String documentoTipo,
    required int documentoId,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    await database.delete(
      'financeiro_desconto_documentos',
      where: 'documento_tipo = ? AND documento_id = ?',
      whereArgs: [documentoTipo.trim().toUpperCase(), documentoId],
    );
  }

  int _mesesCompletos(DateTime inicio, DateTime fim) {
    if (fim.isBefore(inicio)) {
      return 0;
    }

    var meses = (fim.year - inicio.year) * 12 + (fim.month - inicio.month);

    if (fim.day < inicio.day) {
      meses--;
    }

    return meses < 0 ? 0 : meses;
  }

  String _modo(String? valor) {
    final texto = (valor ?? '').trim().toLowerCase();
    return _modosValidos.contains(texto) ? texto : 'desativado';
  }

  int _int(dynamic valor, {int padrao = 0}) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? padrao;
  }

  double _double(dynamic valor, {double padrao = 0}) {
    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(
          valor?.toString().replaceAll(',', '.') ?? '',
        ) ??
        padrao;
  }

  bool _bool(dynamic valor) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor != 0;
    }

    final texto = valor?.toString().trim().toLowerCase() ?? '';

    return texto == '1' || texto == 'true' || texto == 'sim';
  }
}
