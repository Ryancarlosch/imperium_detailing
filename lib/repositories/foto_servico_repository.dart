import '../database/app_database.dart';
import '../models/foto_servico.dart';

class FotoServicoRepository {
  Future<int> inserirFoto(
      FotoServico foto,
      ) async {
    final database =
    await AppDatabase.instance.database;

    return database.insert(
      'fotos_servico',
      foto.toMap(),
    );
  }

  Future<List<FotoServico>> listarFotos() async {
    final database =
    await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      orderBy: 'id DESC',
    );

    return resultado
        .map(
          (map) => FotoServico.fromMap(map),
    )
        .toList();
  }

  Future<List<Map<String, dynamic>>>
  listarFotosComDetalhes() async {
    final database =
    await AppDatabase.instance.database;

    return database.rawQuery(
      '''
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
      ''',
    );
  }

  Future<List<FotoServico>> listarFotosDoCliente(
      int clienteId,
      ) async {
    final database =
    await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'id DESC',
    );

    return resultado
        .map(
          (map) => FotoServico.fromMap(map),
    )
        .toList();
  }

  Future<List<FotoServico>> listarFotosDoVeiculo(
      int veiculoId,
      ) async {
    final database =
    await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: 'veiculo_id = ?',
      whereArgs: [veiculoId],
      orderBy: 'id DESC',
    );

    return resultado
        .map(
          (map) => FotoServico.fromMap(map),
    )
        .toList();
  }

  /// Busca as fotos que pertencem simultaneamente
  /// ao cliente e ao veículo informados.
  ///
  /// Esse método será usado pelo PDF da Ordem de Serviço.
  Future<List<FotoServico>>
  listarFotosDoClienteEVeiculo({
    required int clienteId,
    required int veiculoId,
    int? limite,
  }) async {
    final database =
    await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: '''
        cliente_id = ?
        AND veiculo_id = ?
      ''',
      whereArgs: [
        clienteId,
        veiculoId,
      ],
      orderBy: 'id DESC',
      limit: limite,
    );

    return resultado
        .map(
          (map) => FotoServico.fromMap(map),
    )
        .toList();
  }

  /// Retorna os registros mais recentes com os caminhos
  /// das fotos de antes e depois de determinado veículo.
  ///
  /// O retorno em Map facilita a utilização no serviço de PDF.
  Future<List<Map<String, dynamic>>>
  listarFotosParaOrdemServico({
    required int clienteId,
    required int veiculoId,
    int limite = 6,
  }) async {
    final database =
    await AppDatabase.instance.database;

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
      whereArgs: [
        clienteId,
        veiculoId,
      ],
      orderBy: 'id DESC',
      limit: limite,
    );
  }

  /// Retorna apenas o registro de fotos mais recente
  /// pertencente ao cliente e ao veículo.
  Future<FotoServico?>
  buscarFotoMaisRecenteDoClienteEVeiculo({
    required int clienteId,
    required int veiculoId,
  }) async {
    final database =
    await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: '''
        cliente_id = ?
        AND veiculo_id = ?
      ''',
      whereArgs: [
        clienteId,
        veiculoId,
      ],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return FotoServico.fromMap(
      resultado.first,
    );
  }

  Future<FotoServico?> buscarFotoPorId(
      int id,
      ) async {
    final database =
    await AppDatabase.instance.database;

    final resultado = await database.query(
      'fotos_servico',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return FotoServico.fromMap(
      resultado.first,
    );
  }

  Future<int> atualizarFoto(
      FotoServico foto,
      ) async {
    if (foto.id == null) {
      throw Exception(
        'Não foi possível atualizar a foto sem ID.',
      );
    }

    final database =
    await AppDatabase.instance.database;

    return database.update(
      'fotos_servico',
      foto.toMap(),
      where: 'id = ?',
      whereArgs: [foto.id],
    );
  }

  Future<int> excluirFoto(
      int id,
      ) async {
    final database =
    await AppDatabase.instance.database;

    return database.delete(
      'fotos_servico',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}