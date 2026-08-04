import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/agendamento.dart';

class AgendamentoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  DateTime _parseData(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final iso = DateTime.tryParse(texto);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    final partes = texto.split('/');
    if (partes.length == 3) {
      final dia = int.tryParse(partes[0]) ?? 1;
      final mes = int.tryParse(partes[1]) ?? 1;
      final ano = int.tryParse(partes[2]) ?? 1970;

      return DateTime(ano, mes, dia);
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Duration _parseHora(String valor) {
    final texto = valor.trim();

    if (texto.isEmpty) {
      return Duration.zero;
    }

    final partes = texto.split(':');
    if (partes.length < 2) {
      return Duration.zero;
    }

    final hora = int.tryParse(partes[0]) ?? 0;
    final minuto = int.tryParse(partes[1]) ?? 0;

    return Duration(hours: hora, minutes: minuto);
  }

  DateTime _momentoAgendamento(String data, String hora) {
    final base = _parseData(data);
    final horario = _parseHora(hora);

    return DateTime(
      base.year,
      base.month,
      base.day,
      horario.inHours,
      horario.inMinutes.remainder(60),
    );
  }

  int _compararMapasAgendamento(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final momentoA = _momentoAgendamento(
      (a['data'] ?? '').toString(),
      (a['hora'] ?? '').toString(),
    );

    final momentoB = _momentoAgendamento(
      (b['data'] ?? '').toString(),
      (b['hora'] ?? '').toString(),
    );

    final comparacaoDataHora = momentoA.compareTo(momentoB);
    if (comparacaoDataHora != 0) {
      return comparacaoDataHora;
    }

    final idA = (a['id'] as num?)?.toInt() ?? 0;
    final idB = (b['id'] as num?)?.toInt() ?? 0;

    return idA.compareTo(idB);
  }

  Future<int> inserirAgendamento(Agendamento agendamento) async {
    final database = await _appDatabase.database;

    final dados = agendamento.toMap();
    dados.remove('id');

    return database.insert('agendamentos', dados);
  }

  Future<List<Agendamento>> listarAgendamentos() async {
    final database = await _appDatabase.database;

    final resultado = await database.query('agendamentos');

    final listaOrdenada =
        resultado.map((mapa) => Map<String, dynamic>.from(mapa)).toList()
          ..sort(_compararMapasAgendamento);

    return listaOrdenada.map((mapa) => Agendamento.fromMap(mapa)).toList();
  }

  Future<List<Map<String, dynamic>>> listarAgendamentosComDetalhes() async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery('''
      SELECT
        a.*,
        c.nome AS cliente_nome,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa
      FROM agendamentos a
      INNER JOIN clientes c
        ON c.id = a.cliente_id
      INNER JOIN veiculos v
        ON v.id = a.veiculo_id
    ''');

    final listaOrdenada =
        resultado.map((mapa) => Map<String, dynamic>.from(mapa)).toList()
          ..sort(_compararMapasAgendamento);

    return listaOrdenada;
  }

  Future<Agendamento?> buscarAgendamentoPorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Agendamento.fromMap(resultado.first);
  }

  Future<List<Agendamento>> listarAgendamentosPorData(String data) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'data = ?',
      whereArgs: [data],
      orderBy: 'hora ASC',
    );

    return resultado.map((mapa) => Agendamento.fromMap(mapa)).toList();
  }

  Future<List<Agendamento>> listarAgendamentosDoCliente(int clienteId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'data DESC, hora DESC',
    );

    return resultado.map((mapa) => Agendamento.fromMap(mapa)).toList();
  }

  Future<List<Agendamento>> listarAgendamentosDoVeiculo(int veiculoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'veiculo_id = ?',
      whereArgs: [veiculoId],
      orderBy: 'data DESC, hora DESC',
    );

    return resultado.map((mapa) => Agendamento.fromMap(mapa)).toList();
  }

  Future<int> atualizarAgendamento(Agendamento agendamento) async {
    if (agendamento.id == null) {
      throw ArgumentError(
        'Não é possível atualizar um '
        'agendamento sem ID.',
      );
    }

    final database = await _appDatabase.database;

    final dados = agendamento.toMap();
    dados.remove('id');

    return database.update(
      'agendamentos',
      dados,
      where: 'id = ?',
      whereArgs: [agendamento.id],
    );
  }

  Future<int> atualizarStatus(int id, String status) async {
    final database = await _appDatabase.database;

    return database.update(
      'agendamentos',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> atualizarStatusComTransacao(
    Transaction transaction,
    int id,
    String status,
  ) async {
    return transaction.update(
      'agendamentos',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirAgendamento(int id) async {
    final database = await _appDatabase.database;

    return database.delete('agendamentos', where: 'id = ?', whereArgs: [id]);
  }
}
