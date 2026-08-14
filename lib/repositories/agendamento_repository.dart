import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/agendamento.dart';
import '../services/operacional_sync_service.dart';

class AgendamentoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final OperacionalSyncService _sync = OperacionalSyncService.instance;

  Future<void> _sincronizar() async {
    await _sync.tentarSincronizarTudo();
  }

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
    if (texto.isEmpty) return Duration.zero;

    final partes = texto.split(':');
    if (partes.length < 2) return Duration.zero;

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

    final comparacao = momentoA.compareTo(momentoB);
    if (comparacao != 0) return comparacao;

    final idA = (a['id'] as num?)?.toInt() ?? 0;
    final idB = (b['id'] as num?)?.toInt() ?? 0;
    return idA.compareTo(idB);
  }

  Future<int> inserirAgendamento(Agendamento agendamento) async {
    final database = await _appDatabase.database;
    final dados = agendamento.toMap()..remove('id');

    final id = await database.insert('agendamentos', dados);
    await _sincronizar();
    return id;
  }

  Future<List<Agendamento>> listarAgendamentos() async {
    await _sincronizar();
    final database = await _appDatabase.database;

    final resultado = await database.query('agendamentos');

    final lista =
        resultado.map((mapa) => Map<String, dynamic>.from(mapa)).toList()
          ..sort(_compararMapasAgendamento);

    return lista.map(Agendamento.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> listarAgendamentosComDetalhes() async {
    await _sincronizar();
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

    final lista =
        resultado.map((mapa) => Map<String, dynamic>.from(mapa)).toList()
          ..sort(_compararMapasAgendamento);

    return lista;
  }

  Future<Agendamento?> buscarAgendamentoPorId(int id) async {
    await _sincronizar();
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return Agendamento.fromMap(resultado.first);
  }

  Future<List<Agendamento>> listarAgendamentosPorData(String data) async {
    await _sincronizar();
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'data = ?',
      whereArgs: [data],
      orderBy: 'hora ASC',
    );

    return resultado.map(Agendamento.fromMap).toList();
  }

  Future<List<Agendamento>> listarAgendamentosDoCliente(int clienteId) async {
    await _sincronizar();
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'data DESC, hora DESC',
    );

    return resultado.map(Agendamento.fromMap).toList();
  }

  Future<List<Agendamento>> listarAgendamentosDoVeiculo(int veiculoId) async {
    await _sincronizar();
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'agendamentos',
      where: 'veiculo_id = ?',
      whereArgs: [veiculoId],
      orderBy: 'data DESC, hora DESC',
    );

    return resultado.map(Agendamento.fromMap).toList();
  }

  Future<int> atualizarAgendamento(Agendamento agendamento) async {
    if (agendamento.id == null) {
      throw ArgumentError('Não é possível atualizar um agendamento sem ID.');
    }

    final database = await _appDatabase.database;
    final dados = agendamento.toMap()..remove('id');

    final alterados = await database.update(
      'agendamentos',
      dados,
      where: 'id = ?',
      whereArgs: [agendamento.id],
    );

    await _sincronizar();
    return alterados;
  }

  Future<int> atualizarStatus(int id, String status) async {
    final database = await _appDatabase.database;

    final alterados = await database.update(
      'agendamentos',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );

    await _sincronizar();
    return alterados;
  }

  Future<int> atualizarStatusComTransacao(
    Transaction transaction,
    int id,
    String status,
  ) async {
    // A próxima sincronização detecta a mudança pelo hash da linha.
    return transaction.update(
      'agendamentos',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> excluirAgendamento(int id) async {
    final database = await _appDatabase.database;

    final excluidos = await database.delete(
      'agendamentos',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (excluidos > 0) {
      await _sync.registrarExclusaoAgendamento(id);
      await _sincronizar();
    }

    return excluidos;
  }
}
