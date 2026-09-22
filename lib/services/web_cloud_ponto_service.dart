import '../database/app_database.dart';
import 'supabase_bootstrap.dart';

class WebCloudPontoService {
  WebCloudPontoService._();

  static final WebCloudPontoService instance = WebCloudPontoService._();

  Future<String> _empresaId() async {
    final empresaId = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresaId.isEmpty) {
      throw StateError('Selecione uma empresa antes de usar o Ponto.');
    }
    return empresaId;
  }

  dynamic get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }
    return client;
  }

  Future<List<Map<String, dynamic>>> listarColaboradores() async {
    final empresaId = await _empresaId();
    final dados = await _client
        .from('ponto_colaboradores')
        .select(
          'id,nome,funcao,ativo,auth_user_id,origem_local_id,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('nome');

    return _mapas(dados);
  }

  Future<List<Map<String, dynamic>>> listarRegistros({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final empresaId = await _empresaId();
    final dados = await _client
        .from('ponto_registros')
        .select(
          'id,colaborador_id,data,situacao,entrada,intervalo_inicio,'
          'intervalo_fim,saida,observacoes,criado_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .gte('data', _data(inicio))
        .lte('data', _data(fim))
        .order('data', ascending: false);

    return _mapas(dados);
  }

  Future<List<Map<String, dynamic>>> listarJornada() async {
    final empresaId = await _empresaId();
    final dados = await _client
        .from('ponto_jornada')
        .select(
          'dia_semana,ativo,entrada,intervalo_inicio,intervalo_fim,'
          'saida,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .order('dia_semana');

    return _mapas(dados);
  }

  Future<Map<String, dynamic>> obterConfig() async {
    final empresaId = await _empresaId();
    final item = await _client
        .from('ponto_config')
        .select('adicional_hora_extra,atualizado_em')
        .eq('empresa_id', empresaId)
        .maybeSingle();

    if (item == null) {
      return const <String, dynamic>{'adicional_hora_extra': 50.0};
    }
    return Map<String, dynamic>.from(item as Map);
  }

  Future<void> vincularUsuario({
    required String colaboradorId,
    required String email,
  }) async {
    final empresaId = await _empresaId();
    final emailNormalizado = email.trim().toLowerCase();
    if (emailNormalizado.isEmpty || !emailNormalizado.contains('@')) {
      throw ArgumentError('Informe um e-mail válido.');
    }

    await _client.rpc(
      'ponto_vincular_usuario_colaborador',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorId,
        'p_email': emailNormalizado,
      },
    );
  }

  Future<void> salvarRegistroAdmin({
    required String colaboradorId,
    required DateTime data,
    required String situacao,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
    String observacoes = '',
    String motivo = '',
  }) async {
    final empresaId = await _empresaId();

    await _client.rpc(
      'ponto_salvar_registro_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorId,
        'p_data': _data(data),
        'p_situacao': situacao,
        'p_entrada': _horaNula(entrada),
        'p_intervalo_inicio': _horaNula(intervaloInicio),
        'p_intervalo_fim': _horaNula(intervaloFim),
        'p_saida': _horaNula(saida),
        'p_observacoes': observacoes.trim(),
        'p_motivo': motivo.trim(),
      },
    );
  }

  Future<void> removerRegistroAdmin({
    required String registroId,
    required String motivo,
  }) async {
    final empresaId = await _empresaId();
    await _client.rpc(
      'ponto_remover_registro_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_registro_id': registroId,
        'p_motivo': motivo.trim(),
      },
    );
  }

  Future<void> salvarJornada({
    required int diaSemana,
    required bool ativo,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
  }) async {
    final empresaId = await _empresaId();

    await _client.rpc(
      'ponto_salvar_jornada_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_dia_semana': diaSemana,
        'p_ativo': ativo,
        'p_entrada': _horaNula(entrada),
        'p_intervalo_inicio': _horaNula(intervaloInicio),
        'p_intervalo_fim': _horaNula(intervaloFim),
        'p_saida': _horaNula(saida),
      },
    );
  }

  Future<void> salvarConfig(double adicionalHoraExtra) async {
    final empresaId = await _empresaId();
    await _client.rpc(
      'ponto_salvar_config_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_adicional_hora_extra': adicionalHoraExtra,
      },
    );
  }


  Future<void> fecharCompetencia({
    required String colaboradorId,
    required DateTime competencia,
    required Map<String, dynamic> snapshot,
  }) async {
    final pendencias = _int(snapshot['pendencias']);
    final incompletos = _int(snapshot['incompletos']);
    if (pendencias > 0 || incompletos > 0) {
      throw StateError(
        'Resolva as pendências e pontos incompletos antes de fechar o mês.',
      );
    }

    final fim = DateTime(competencia.year, competencia.month + 1, 0);
    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);
    if (!hojeDia.isAfter(fim)) {
      throw StateError(
        'O mês só pode ser fechado depois que a competência terminar.',
      );
    }

    final empresaId = await _empresaId();
    await _client.rpc(
      'ponto_fechar_competencia_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorId,
        'p_competencia': _data(DateTime(competencia.year, competencia.month, 1)),
        'p_snapshot': snapshot,
      },
    );
  }

  Future<void> reabrirCompetencia({
    required String colaboradorId,
    required DateTime competencia,
    required String motivo,
  }) async {
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe o motivo da reabertura com pelo menos 5 caracteres.',
      );
    }

    final empresaId = await _empresaId();
    await _client.rpc(
      'ponto_reabrir_competencia_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorId,
        'p_competencia': _data(DateTime(competencia.year, competencia.month, 1)),
        'p_motivo': motivoLimpo,
      },
    );
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static List<Map<String, dynamic>> _mapas(dynamic dados) {
    if (dados is! List) return const [];
    return dados
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static String _data(DateTime data) {
    final y = data.year.toString().padLeft(4, '0');
    final m = data.month.toString().padLeft(2, '0');
    final d = data.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String? _horaNula(String? valor) {
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
