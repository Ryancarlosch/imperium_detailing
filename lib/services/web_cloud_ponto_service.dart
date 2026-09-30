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

  Future<Map<String, dynamic>?> obterMeuColaborador() async {
    final empresaId = await _empresaId();
    final authUserId = _client.auth.currentUser?.id?.toString().trim() ?? '';
    if (authUserId.isEmpty) return null;

    final item = await _client
        .from('ponto_colaboradores')
        .select('id,nome,funcao,ativo,auth_user_id,atualizado_em')
        .eq('empresa_id', empresaId)
        .eq('auth_user_id', authUserId)
        .eq('ativo', true)
        .maybeSingle();

    if (item == null) return null;
    return Map<String, dynamic>.from(item as Map);
  }

  Future<Map<String, dynamic>?> obterMeuRegistroHoje() async {
    final colaborador = await obterMeuColaborador();
    if (colaborador == null) return null;
    final empresaId = await _empresaId();
    final hoje = _data(DateTime.now());
    final item = await _client
        .from('ponto_registros')
        .select(
          'id,colaborador_id,data,situacao,entrada,intervalo_inicio,'
          'intervalo_fim,saida,observacoes,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .eq('colaborador_id', colaborador['id'].toString())
        .eq('data', hoje)
        .maybeSingle();
    if (item == null) return null;
    return Map<String, dynamic>.from(item as Map);
  }

  Future<List<Map<String, dynamic>>> listarMeusRegistros({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final colaborador = await obterMeuColaborador();
    if (colaborador == null) return const [];
    final empresaId = await _empresaId();
    final dados = await _client
        .from('ponto_registros')
        .select(
          'id,colaborador_id,data,situacao,entrada,intervalo_inicio,'
          'intervalo_fim,saida,observacoes,criado_em,atualizado_em',
        )
        .eq('empresa_id', empresaId)
        .eq('colaborador_id', colaborador['id'].toString())
        .gte('data', _data(inicio))
        .lte('data', _data(fim))
        .order('data', ascending: false);
    return _mapas(dados);
  }

  Future<List<Map<String, dynamic>>> listarMinhasSolicitacoesAjuste({
    int limite = 50,
  }) async {
    final colaborador = await obterMeuColaborador();
    if (colaborador == null) return const [];
    final empresaId = await _empresaId();
    final dados = await _client.rpc(
      'ponto_minhas_solicitacoes_ajuste',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaborador['id'].toString(),
        'p_limite': limite.clamp(1, 200),
      },
    );
    return _mapas(dados);
  }

  Future<Map<String, dynamic>> solicitarMeuAjuste({
    required DateTime data,
    required String situacao,
    String? entrada,
    String? intervaloInicio,
    String? intervaloFim,
    String? saida,
    String observacoes = '',
    required String motivo,
  }) async {
    final colaborador = await obterMeuColaborador();
    if (colaborador == null) {
      throw StateError(
        'Seu usuário ainda não está vinculado a um funcionário ativo.',
      );
    }
    final motivoLimpo = motivo.trim();
    if (motivoLimpo.length < 5) {
      throw ArgumentError('Informe o motivo da correção com pelo menos 5 caracteres.');
    }
    final empresaId = await _empresaId();
    final resposta = await _client.rpc(
      'ponto_solicitar_ajuste',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaborador['id'].toString(),
        'p_data': _data(data),
        'p_situacao': situacao,
        'p_entrada': _horaNula(entrada),
        'p_intervalo_inicio': _horaNula(intervaloInicio),
        'p_intervalo_fim': _horaNula(intervaloFim),
        'p_saida': _horaNula(saida),
        'p_observacoes': observacoes.trim(),
        'p_motivo': motivoLimpo,
      },
    );
    if (resposta is Map) return Map<String, dynamic>.from(resposta);
    return const <String, dynamic>{};
  }

  Future<void> cancelarMinhaSolicitacaoAjuste(String solicitacaoId) async {
    final id = solicitacaoId.trim();
    if (id.isEmpty) throw ArgumentError('Solicitação inválida.');
    await _client.rpc(
      'ponto_cancelar_solicitacao_ajuste',
      params: {'p_solicitacao_id': id},
    );
  }

  Future<Map<String, dynamic>> registrarMinhaBatida() async {
    final colaborador = await obterMeuColaborador();
    if (colaborador == null) {
      throw StateError(
        'Seu usuário ainda não está vinculado a um funcionário ativo.',
      );
    }
    final empresaId = await _empresaId();
    final resposta = await _client.rpc(
      'ponto_registrar_batida',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaborador['id'].toString(),
      },
    );
    if (resposta is Map) return Map<String, dynamic>.from(resposta);
    throw StateError('O servidor não retornou a confirmação da batida.');
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

  Future<List<Map<String, dynamic>>> listarSolicitacoesAjusteAdmin({
    String status = 'Pendente',
    int limite = 100,
  }) async {
    final empresaId = await _empresaId();
    const permitidos = <String>{
      'Pendente',
      'Aprovada',
      'Rejeitada',
      'Cancelada',
      'Todos',
    };
    if (!permitidos.contains(status)) {
      throw ArgumentError('Status de solicitação inválido.');
    }

    final dados = await _client.rpc(
      'ponto_listar_solicitacoes_ajuste_admin',
      params: {
        'p_empresa_id': empresaId,
        'p_status': status,
        'p_limite': limite.clamp(1, 300),
      },
    );
    return _mapas(dados);
  }

  Future<void> decidirSolicitacaoAjuste({
    required String solicitacaoId,
    required bool aprovar,
    String motivo = '',
  }) async {
    final id = solicitacaoId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Solicitação de ajuste inválida.');
    }
    final motivoLimpo = motivo.trim();
    if (!aprovar && motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe o motivo da rejeição com pelo menos 5 caracteres.',
      );
    }

    await _client.rpc(
      'ponto_decidir_solicitacao_ajuste',
      params: {
        'p_solicitacao_id': id,
        'p_aprovar': aprovar,
        'p_motivo': motivoLimpo,
      },
    );
  }

  Future<Map<String, dynamic>> obterResumoCompetencia({
    required String colaboradorId,
    required DateTime competencia,
  }) async {
    final empresaId = await _empresaId();
    final inicio = DateTime(competencia.year, competencia.month, 1);
    final fim = DateTime(competencia.year, competencia.month + 1, 0);
    final registros = await listarRegistros(inicio: inicio, fim: fim);
    final solicitacoes = await listarSolicitacoesAjusteAdmin(
      status: 'Pendente',
    );

    final registrosColaborador = registros
        .where((e) => (e['colaborador_id'] ?? '').toString() == colaboradorId)
        .toList();
    final pendencias = solicitacoes.where((e) {
      return (e['colaborador_id'] ?? '').toString() == colaboradorId;
    }).length;
    final incompletos = registrosColaborador.where((e) {
      final situacao = (e['situacao'] ?? 'Trabalhado').toString();
      if (situacao != 'Trabalhado') return false;
      return _horaNula(e['entrada']?.toString()) == null ||
          _horaNula(e['saida']?.toString()) == null;
    }).length;

    return <String, dynamic>{
      'empresa_id': empresaId,
      'colaborador_id': colaboradorId,
      'competencia': _data(inicio),
      'pendencias': pendencias,
      'incompletos': incompletos,
      'registros': registrosColaborador.length,
    };
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
        'p_competencia': _data(
          DateTime(competencia.year, competencia.month, 1),
        ),
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
        'p_competencia': _data(
          DateTime(competencia.year, competencia.month, 1),
        ),
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
