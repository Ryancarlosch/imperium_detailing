import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/foto_servico.dart';

class ExclusaoFotoServicoResultado {
  const ExclusaoFotoServicoResultado({
    required this.registrosExcluidos,
    required this.arquivosComFalha,
  });

  final int registrosExcluidos;
  final List<String> arquivosComFalha;
}

class FotoServicoRepository {
  Future<int> inserirFoto(FotoServico foto) async {
    final database = await AppDatabase.instance.database;

    return database.insert('fotos_servico', foto.toMap());
  }

  Future<List<FotoServico>> listarFotos() async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query('fotos_servico', orderBy: 'id DESC');

    return resultado.map((map) => FotoServico.fromMap(map)).toList();
  }

  Future<List<Map<String, dynamic>>> listarFotosComDetalhes() async {
    final database = await AppDatabase.instance.database;

    return database.rawQuery('''
      SELECT
        fotos_servico.id,
        fotos_servico.cliente_id,
        fotos_servico.veiculo_id,
        fotos_servico.caminho_antes,
        fotos_servico.caminho_depois,
        fotos_servico.descricao,
        fotos_servico.data,
        clientes.nome AS cliente_nome,
        veiculos.marca AS veiculo_marca,
        veiculos.modelo AS veiculo_modelo,
        veiculos.placa AS veiculo_placa
      FROM fotos_servico
      INNER JOIN clientes
        ON clientes.id = fotos_servico.cliente_id
      INNER JOIN veiculos
        ON veiculos.id = fotos_servico.veiculo_id
      ORDER BY fotos_servico.id DESC
      ''');
  }

  Future<List<FotoServico>> listarFotosDoCliente(int clienteId) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'id DESC',
    );

    return resultado.map((map) => FotoServico.fromMap(map)).toList();
  }

  Future<List<FotoServico>> listarFotosDoVeiculo(int veiculoId) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: 'veiculo_id = ?',
      whereArgs: [veiculoId],
      orderBy: 'id DESC',
    );

    return resultado.map((map) => FotoServico.fromMap(map)).toList();
  }

  /// Busca as fotos que pertencem simultaneamente
  /// ao cliente e ao veículo informados.
  ///
  /// Esse método será usado pelo PDF da Ordem de Serviço.
  Future<List<FotoServico>> listarFotosDoClienteEVeiculo({
    required int clienteId,
    required int veiculoId,
    int? limite,
  }) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: '''
        cliente_id = ?
        AND veiculo_id = ?
      ''',
      whereArgs: [clienteId, veiculoId],
      orderBy: 'id DESC',
      limit: limite,
    );

    return resultado.map((map) => FotoServico.fromMap(map)).toList();
  }

  /// Retorna os registros mais recentes com os caminhos
  /// das fotos de antes e depois de determinado veículo.
  ///
  /// O retorno em Map facilita a utilização no serviço de PDF.
  Future<List<Map<String, dynamic>>> listarFotosParaOrdemServico({
    required int clienteId,
    required int veiculoId,
    int limite = 6,
  }) async {
    final database = await AppDatabase.instance.database;

    if (limite <= 0) {
      return [];
    }

    return database.query(
      'fotos_servico',
      columns: [
        'id',
        'cliente_id',
        'veiculo_id',
        'caminho_antes',
        'caminho_depois',
        'descricao',
        'data',
      ],
      where: '''
        cliente_id = ?
        AND veiculo_id = ?
      ''',
      whereArgs: [clienteId, veiculoId],
      orderBy: 'id DESC',
      limit: limite,
    );
  }

  /// Retorna apenas o registro de fotos mais recente
  /// pertencente ao cliente e ao veículo.
  Future<FotoServico?> buscarFotoMaisRecenteDoClienteEVeiculo({
    required int clienteId,
    required int veiculoId,
  }) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: '''
        cliente_id = ?
        AND veiculo_id = ?
      ''',
      whereArgs: [clienteId, veiculoId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return FotoServico.fromMap(resultado.first);
  }

  Future<List<Map<String, dynamic>>> listarGaleriaCompletaDoVeiculo(
    int veiculoId,
  ) async {
    final database = await AppDatabase.instance.database;

    return database.rawQuery(
      '''
      SELECT *
      FROM (
        SELECT
          fotos_servico.id,
          fotos_servico.cliente_id,
          fotos_servico.veiculo_id,
          fotos_servico.caminho_antes,
          fotos_servico.caminho_depois,
          fotos_servico.descricao,
          fotos_servico.data,
          clientes.nome AS cliente_nome,
          veiculos.marca AS veiculo_marca,
          veiculos.modelo AS veiculo_modelo,
          veiculos.placa AS veiculo_placa,
          'geral' AS origem,
          fotos_servico.id AS origem_id,
          CASE
            WHEN INSTR(fotos_servico.data, 'T') > 0
            THEN fotos_servico.data
            WHEN INSTR(fotos_servico.data, '/') > 0
            THEN SUBSTR(fotos_servico.data, 7, 4)
              || '-'
              || SUBSTR(fotos_servico.data, 4, 2)
              || '-'
              || SUBSTR(fotos_servico.data, 1, 2)
              || 'T00:00:00'
            ELSE fotos_servico.data
          END AS data_ordenacao
        FROM fotos_servico
        INNER JOIN clientes
          ON clientes.id = fotos_servico.cliente_id
        INNER JOIN veiculos
          ON veiculos.id = fotos_servico.veiculo_id
        WHERE fotos_servico.veiculo_id = ?

        UNION ALL

        SELECT
          ordem_servico_fotos.id,
          ordens_servico.cliente_id,
          ordens_servico.veiculo_id,
          CASE
            WHEN ordem_servico_fotos.etapa = 'Antes'
            THEN ordem_servico_fotos.caminho
            ELSE ''
          END AS caminho_antes,
          CASE
            WHEN ordem_servico_fotos.etapa = 'Depois'
            THEN ordem_servico_fotos.caminho
            ELSE ''
          END AS caminho_depois,
          CASE
            WHEN TRIM(COALESCE(ordem_servico_fotos.descricao, '')) != ''
            THEN ordem_servico_fotos.descricao
            ELSE 'Foto vinculada à OS ' || ordens_servico.numero
          END AS descricao,
          ordem_servico_fotos.data,
          clientes.nome AS cliente_nome,
          veiculos.marca AS veiculo_marca,
          veiculos.modelo AS veiculo_modelo,
          veiculos.placa AS veiculo_placa,
          'ordem_servico' AS origem,
          ordem_servico_fotos.id AS origem_id,
          CASE
            WHEN INSTR(ordem_servico_fotos.data, 'T') > 0
            THEN ordem_servico_fotos.data
            WHEN INSTR(ordem_servico_fotos.data, '/') > 0
            THEN SUBSTR(ordem_servico_fotos.data, 7, 4)
              || '-'
              || SUBSTR(ordem_servico_fotos.data, 4, 2)
              || '-'
              || SUBSTR(ordem_servico_fotos.data, 1, 2)
              || 'T00:00:00'
            ELSE ordem_servico_fotos.data
          END AS data_ordenacao
        FROM ordem_servico_fotos
        INNER JOIN ordens_servico
          ON ordens_servico.id = ordem_servico_fotos.ordem_servico_id
        INNER JOIN clientes
          ON clientes.id = ordens_servico.cliente_id
        INNER JOIN veiculos
          ON veiculos.id = ordens_servico.veiculo_id
        WHERE ordens_servico.veiculo_id = ?
      ) galeria
      ORDER BY
        galeria.data_ordenacao DESC,
        galeria.origem_id DESC
      ''',
      [veiculoId, veiculoId],
    );
  }

  Future<Map<String, int>> contarFotosAntesEDepoisDoVeiculo(
    int veiculoId,
  ) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        (
          SELECT COUNT(*)
          FROM fotos_servico
          WHERE veiculo_id = ?
        )
        +
        (
          SELECT COUNT(*)
          FROM ordem_servico_fotos
          INNER JOIN ordens_servico
            ON ordens_servico.id = ordem_servico_fotos.ordem_servico_id
          WHERE ordens_servico.veiculo_id = ?
        ) AS registros,
        (
          SELECT COALESCE(SUM(
            CASE
              WHEN TRIM(COALESCE(caminho_antes, '')) != ''
              THEN 1
              ELSE 0
            END
          ), 0)
          FROM fotos_servico
          WHERE veiculo_id = ?
        )
        +
        (
          SELECT COUNT(*)
          FROM ordem_servico_fotos
          INNER JOIN ordens_servico
            ON ordens_servico.id = ordem_servico_fotos.ordem_servico_id
          WHERE ordens_servico.veiculo_id = ?
            AND ordem_servico_fotos.etapa = 'Antes'
        ) AS fotos_antes,
        (
          SELECT COALESCE(SUM(
            CASE
              WHEN TRIM(COALESCE(caminho_depois, '')) != ''
              THEN 1
              ELSE 0
            END
          ), 0)
          FROM fotos_servico
          WHERE veiculo_id = ?
        )
        +
        (
          SELECT COUNT(*)
          FROM ordem_servico_fotos
          INNER JOIN ordens_servico
            ON ordens_servico.id = ordem_servico_fotos.ordem_servico_id
          WHERE ordens_servico.veiculo_id = ?
            AND ordem_servico_fotos.etapa = 'Depois'
        ) AS fotos_depois
      ''',
      [veiculoId, veiculoId, veiculoId, veiculoId, veiculoId, veiculoId],
    );

    if (resultado.isEmpty) {
      return {
        'registros': 0,
        'fotos_antes': 0,
        'fotos_depois': 0,
        'total_imagens': 0,
      };
    }

    final linha = resultado.first;

    int converter(dynamic valor) {
      if (valor is int) {
        return valor;
      }

      if (valor is num) {
        return valor.toInt();
      }

      return int.tryParse(valor?.toString() ?? '') ?? 0;
    }

    final registros = converter(linha['registros']);

    final fotosAntes = converter(linha['fotos_antes']);

    final fotosDepois = converter(linha['fotos_depois']);

    return {
      'registros': registros,
      'fotos_antes': fotosAntes,
      'fotos_depois': fotosDepois,
      'total_imagens': fotosAntes + fotosDepois,
    };
  }

  Future<Map<String, dynamic>?> buscarUltimoRegistroFotograficoDoVeiculo(
    int veiculoId,
  ) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: 'veiculo_id = ?',
      whereArgs: [veiculoId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(resultado.first);
  }

  Future<FotoServico?> buscarFotoPorId(int id) async {
    final database = await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return FotoServico.fromMap(resultado.first);
  }

  Future<int> atualizarFoto(FotoServico foto) async {
    if (foto.id == null) {
      throw Exception('Não foi possível atualizar a foto sem ID.');
    }

    final database = await AppDatabase.instance.database;

    return database.update(
      'fotos_servico',
      foto.toMap(),
      where: 'id = ?',
      whereArgs: [foto.id],
    );
  }

  Future<int> excluirFoto(int id) async {
    final database = await AppDatabase.instance.database;

    return database.delete('fotos_servico', where: 'id = ?', whereArgs: [id]);
  }

  Future<ExclusaoFotoServicoResultado> excluirFotoComArquivos(int id) async {
    final database = await AppDatabase.instance.database;

    final registro = await database.query(
      'fotos_servico',
      columns: ['id', 'caminho_antes', 'caminho_depois'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (registro.isEmpty) {
      return const ExclusaoFotoServicoResultado(
        registrosExcluidos: 0,
        arquivosComFalha: [],
      );
    }

    final registroAtual = registro.first;

    final registrosExcluidos = await database.delete(
      'fotos_servico',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (registrosExcluidos <= 0) {
      return const ExclusaoFotoServicoResultado(
        registrosExcluidos: 0,
        arquivosComFalha: [],
      );
    }

    final caminhos = <String>{
      _normalizarCaminho(registroAtual['caminho_antes']),
      _normalizarCaminho(registroAtual['caminho_depois']),
    }..removeWhere((valor) => valor.isEmpty);

    final arquivosComFalha = <String>[];

    for (final caminho in caminhos) {
      try {
        await excluirArquivoSeNaoReferenciado(
          caminho,
          ignorarFotoServicoId: id,
        );
      } catch (_) {
        arquivosComFalha.add(caminho);
      }
    }

    return ExclusaoFotoServicoResultado(
      registrosExcluidos: registrosExcluidos,
      arquivosComFalha: arquivosComFalha,
    );
  }

  Future<void> excluirArquivoSeNaoReferenciado(
    String caminho, {
    int? ignorarFotoServicoId,
    int? ignorarOrdemServicoFotoId,
  }) async {
    final caminhoLimpo = caminho.trim();

    if (caminhoLimpo.isEmpty) {
      return;
    }

    final database = await AppDatabase.instance.database;

    final totalReferencias = await _contarReferenciasDeArquivo(
      database: database,
      caminho: caminhoLimpo,
      ignorarFotoServicoId: ignorarFotoServicoId,
      ignorarOrdemServicoFotoId: ignorarOrdemServicoFotoId,
    );

    if (totalReferencias > 0) {
      return;
    }

    final arquivo = File(caminhoLimpo);

    if (!await arquivo.exists()) {
      return;
    }

    await arquivo.delete();
  }

  String _normalizarCaminho(dynamic valor) {
    return (valor ?? '').toString().trim();
  }

  Future<int> _contarReferenciasDeArquivo({
    required Database database,
    required String caminho,
    int? ignorarFotoServicoId,
    int? ignorarOrdemServicoFotoId,
  }) async {
    final filtrosFotosServico = <String>[
      '(caminho_antes = ? OR caminho_depois = ?)',
    ];

    final argsFotosServico = <dynamic>[caminho, caminho];

    if (ignorarFotoServicoId != null) {
      filtrosFotosServico.add('id != ?');
      argsFotosServico.add(ignorarFotoServicoId);
    }

    final filtrosFotosOS = <String>['caminho = ?'];
    final argsFotosOS = <dynamic>[caminho];

    if (ignorarOrdemServicoFotoId != null) {
      filtrosFotosOS.add('id != ?');
      argsFotosOS.add(ignorarOrdemServicoFotoId);
    }

    final resultadoFotosServico = await database.rawQuery('''
      SELECT COUNT(*) AS total
      FROM fotos_servico
      WHERE ${filtrosFotosServico.join(' AND ')}
      ''', argsFotosServico);

    final resultadoFotosOS = await database.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ordem_servico_fotos
      WHERE ${filtrosFotosOS.join(' AND ')}
      ''', argsFotosOS);

    return _converterParaInt(resultadoFotosServico.first['total']) +
        _converterParaInt(resultadoFotosOS.first['total']);
  }

  int _converterParaInt(dynamic valor) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
