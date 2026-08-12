import '../database/app_database.dart';
import '../repositories/ponto_repository.dart';
import '../services/ponto_nuvem_service.dart';

class PontoSincronizadoRepository extends PontoRepository {
  final PontoNuvemService _nuvem = PontoNuvemService.instance;

  Future<bool> _usarNuvem() async {
    try {
      return await _nuvem.pontoHibridoAtivo;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> garantirEstrutura() async {
    await super.garantirEstrutura();
    await _nuvem.garantirEstruturaLocal();

    try {
      if (await _usarNuvem()) {
        await _nuvem.sincronizarJornada();
        await _nuvem.sincronizarConfig();
      }
    } catch (_) {
      // O SQLite continua disponível se a nuvem estiver temporariamente fora.
    }
  }

  @override
  Future<double> obterAdicionalHoraExtra() async {
    try {
      if (await _usarNuvem()) {
        await _nuvem.sincronizarConfig();
      }
    } catch (_) {
      // Fallback local.
    }

    return super.obterAdicionalHoraExtra();
  }

  @override
  Future<void> salvarAdicionalHoraExtra(double percentual) async {
    if (await _usarNuvem()) {
      await _nuvem.salvarConfig(percentual);
      return;
    }

    await super.salvarAdicionalHoraExtra(percentual);
  }

  @override
  Future<List<Map<String, dynamic>>> listarJornada() async {
    try {
      if (await _usarNuvem()) {
        await _nuvem.sincronizarJornada();
      }
    } catch (_) {
      // Fallback local.
    }

    return super.listarJornada();
  }

  @override
  Future<void> salvarJornadaDia({
    required int diaSemana,
    required bool ativo,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
  }) async {
    if (await _usarNuvem()) {
      await _nuvem.salvarJornada(
        diaSemana: diaSemana,
        ativo: ativo,
        entrada: entrada,
        intervaloInicio: intervaloInicio,
        intervaloFim: intervaloFim,
        saida: saida,
      );
      return;
    }

    await super.salvarJornadaDia(
      diaSemana: diaSemana,
      ativo: ativo,
      entrada: entrada,
      intervaloInicio: intervaloInicio,
      intervaloFim: intervaloFim,
      saida: saida,
    );
  }

  @override
  Future<Map<String, dynamic>> obterEstadoBatidaHoje(
    int colaboradorId, {
    DateTime? agora,
  }) async {
    final momento = agora ?? DateTime.now();

    try {
      if (await _usarNuvem()) {
        await _nuvem.sincronizarDia(
          colaboradorLocalId: colaboradorId,
          data: momento,
        );
      }
    } catch (_) {
      // Leitura local continua disponível.
    }

    return super.obterEstadoBatidaHoje(colaboradorId, agora: momento);
  }

  @override
  Future<Map<String, dynamic>> registrarBatida({
    required int colaboradorId,
    DateTime? momento,
  }) async {
    if (momento == null && await _usarNuvem()) {
      final resultado = await _nuvem.registrarBatida(colaboradorId);

      if (resultado != null) {
        return resultado;
      }
    }

    // `momento` é usado por testes/rotinas locais e permanece determinístico.
    return super.registrarBatida(
      colaboradorId: colaboradorId,
      momento: momento,
    );
  }

  @override
  Future<Map<String, dynamic>?> buscarRegistro({
    required int colaboradorId,
    required DateTime data,
  }) async {
    try {
      if (await _usarNuvem()) {
        await _nuvem.sincronizarDia(
          colaboradorLocalId: colaboradorId,
          data: data,
        );
      }
    } catch (_) {
      // Fallback local.
    }

    return super.buscarRegistro(colaboradorId: colaboradorId, data: data);
  }

  @override
  Future<int> salvarRegistro({
    required int colaboradorId,
    required DateTime data,
    required String situacao,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
    String observacoes = '',
    String motivoAjuste = '',
  }) async {
    if (await _usarNuvem()) {
      await _nuvem.salvarRegistroAdmin(
        colaboradorLocalId: colaboradorId,
        data: data,
        situacao: situacao,
        entrada: entrada,
        intervaloInicio: intervaloInicio,
        intervaloFim: intervaloFim,
        saida: saida,
        observacoes: observacoes,
        motivo: motivoAjuste,
      );

      final local = await super.buscarRegistro(
        colaboradorId: colaboradorId,
        data: data,
      );

      final id = local?['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();

      throw StateError(
        'Registro foi salvo na nuvem, mas o espelho local falhou.',
      );
    }

    return super.salvarRegistro(
      colaboradorId: colaboradorId,
      data: data,
      situacao: situacao,
      entrada: entrada,
      intervaloInicio: intervaloInicio,
      intervaloFim: intervaloFim,
      saida: saida,
      observacoes: observacoes,
      motivoAjuste: motivoAjuste,
    );
  }

  @override
  Future<void> removerRegistro({
    required int registroId,
    required String motivo,
  }) async {
    if (await _usarNuvem()) {
      final local = await _registroLocalPorId(registroId);

      if (local == null) {
        throw StateError('Registro de ponto não encontrado.');
      }

      final colaboradorId = _int(local['colaborador_id']);
      final data = DateTime.tryParse(local['data']?.toString() ?? '');

      if (colaboradorId <= 0 || data == null) {
        throw StateError('Registro local inválido.');
      }

      await _nuvem.removerRegistroAdmin(
        colaboradorLocalId: colaboradorId,
        data: data,
        motivo: motivo,
      );

      await super.removerRegistro(registroId: registroId, motivo: motivo);
      return;
    }

    await super.removerRegistro(registroId: registroId, motivo: motivo);
  }

  @override
  Future<Set<String>> listarDiasCorrigidos({
    required int colaboradorId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    if (await _usarNuvem()) {
      try {
        return await _nuvem.listarDiasCorrigidos(
          colaboradorLocalId: colaboradorId,
          inicio: inicio,
          fim: fim,
        );
      } catch (_) {
        // Fallback para o histórico local.
      }
    }

    return super.listarDiasCorrigidos(
      colaboradorId: colaboradorId,
      inicio: inicio,
      fim: fim,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listarHistoricoAjustes({
    required int colaboradorId,
    required DateTime data,
  }) async {
    if (await _usarNuvem()) {
      final remoto = await _nuvem.listarAjustes(
        colaboradorLocalId: colaboradorId,
        data: data,
      );

      if (remoto.isNotEmpty) {
        return remoto;
      }
    }

    return super.listarHistoricoAjustes(
      colaboradorId: colaboradorId,
      data: data,
    );
  }

  @override
  Future<Map<String, dynamic>> obterEspelhoMes({
    required int colaboradorId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    try {
      if (await _usarNuvem()) {
        await _nuvem.sincronizarPeriodo(
          colaboradorLocalId: colaboradorId,
          inicio: inicio,
          fim: fim,
        );
      }
    } catch (_) {
      // Fallback local.
    }

    return super.obterEspelhoMes(
      colaboradorId: colaboradorId,
      inicio: inicio,
      fim: fim,
    );
  }

  @override
  Future<Map<String, dynamic>> obterFechamentoMes({
    required int colaboradorId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    try {
      if (await _usarNuvem()) {
        await _nuvem.sincronizarPeriodo(
          colaboradorLocalId: colaboradorId,
          inicio: inicio,
          fim: fim,
        );
      }
    } catch (_) {
      // Fallback local.
    }

    return super.obterFechamentoMes(
      colaboradorId: colaboradorId,
      inicio: inicio,
      fim: fim,
    );
  }

  @override
  Future<void> fecharCompetencia({
    required int colaboradorId,
    required DateTime competencia,
  }) async {
    if (await _usarNuvem()) {
      final inicio = DateTime(competencia.year, competencia.month, 1);
      final fim = DateTime(competencia.year, competencia.month + 1, 0);

      final resumo = await obterFechamentoMes(
        colaboradorId: colaboradorId,
        inicio: inicio,
        fim: fim,
      );

      final pendencias = _int(resumo['pendencias']);
      final incompletos = _int(resumo['incompletos']);

      if (pendencias > 0 || incompletos > 0) {
        throw StateError(
          'Resolva pendências e pontos incompletos antes de fechar o mês.',
        );
      }

      await _nuvem.fecharCompetencia(
        colaboradorLocalId: colaboradorId,
        competencia: competencia,
        snapshot: resumo,
      );

      // A função de nuvem já sincroniza o fechamento para o SQLite.
      return;
    }

    await super.fecharCompetencia(
      colaboradorId: colaboradorId,
      competencia: competencia,
    );
  }

  @override
  Future<void> reabrirCompetencia({
    required int colaboradorId,
    required DateTime competencia,
    required String motivo,
  }) async {
    if (await _usarNuvem()) {
      await _nuvem.reabrirCompetencia(
        colaboradorLocalId: colaboradorId,
        competencia: competencia,
        motivo: motivo,
      );

      // A função de nuvem já sincroniza a reabertura para o SQLite.
      return;
    }

    await super.reabrirCompetencia(
      colaboradorId: colaboradorId,
      competencia: competencia,
      motivo: motivo,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listarHistoricoFechamento({
    required int colaboradorId,
    required DateTime competencia,
  }) async {
    if (await _usarNuvem()) {
      final remoto = await _nuvem.listarHistoricoFechamento(
        colaboradorLocalId: colaboradorId,
        competencia: competencia,
      );

      if (remoto.isNotEmpty) return remoto;
    }

    return super.listarHistoricoFechamento(
      colaboradorId: colaboradorId,
      competencia: competencia,
    );
  }

  Future<Map<String, dynamic>?> _registroLocalPorId(int id) async {
    final database = await AppDatabase.instance.database;
    final resultado = await database.query(
      'financeiro_ponto_registros',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return Map<String, dynamic>.from(resultado.first);
  }

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
