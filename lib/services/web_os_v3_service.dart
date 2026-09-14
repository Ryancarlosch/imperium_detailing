import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebOsV3Service {
  WebOsV3Service._();

  static final WebOsV3Service instance = WebOsV3Service._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de editar a OS.');
    }
    return empresa;
  }

  Future<Map<String, dynamic>> carregarEdicao(String ordemId) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();

    final ordem = await client
        .from('imperium_ordens_servico')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', ordemId)
        .isFilter('excluido_em', null)
        .single();

    final itens = await client
        .from('imperium_ordem_servico_itens')
        .select()
        .eq('empresa_id', empresaId)
        .eq('ordem_servico_id', ordemId)
        .isFilter('excluido_em', null)
        .order('ordem');

    return <String, dynamic>{
      'ordem': Map<String, dynamic>.from(ordem),
      'itens': (itens as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    };
  }

  Future<Map<String, dynamic>> salvarEdicao({
    required Map<String, dynamic> original,
    required String status,
    required String dataAbertura,
    required String dataInicio,
    required String horaEntrada,
    required String horaSaida,
    required String funcionarioResponsavel,
    required String observacoes,
    required String quilometragemEntrada,
    required String combustivelEntrada,
    required double desconto,
    required List<Map<String, Object?>> itens,
  }) async {
    if (status != 'Aberta' && status != 'Em andamento') {
      throw StateError(
        'O Web só pode editar OS Aberta ou Em andamento. '
        'Finalização continua no fluxo transacional.',
      );
    }

    if (itens.isEmpty) {
      throw ArgumentError('A OS precisa ter pelo menos um serviço.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final ordem = Map<String, dynamic>.from(original['ordem'] as Map);
    final originais = (original['itens'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final dispositivoId = await WebOrigemService.instance.dispositivoId();
    final enviados = <Map<String, Object?>>[];

    for (var i = 0; i < itens.length; i++) {
      final item = Map<String, Object?>.from(itens[i]);

      if ((item['servico'] ?? '').toString().trim().isEmpty) {
        throw ArgumentError('Todo serviço precisa ter nome.');
      }

      final quantidade = _double(item['quantidade']);
      final valor = _double(item['valor_unitario']);

      if (quantidade <= 0 || valor < 0) {
        throw ArgumentError(
          'Quantidade deve ser positiva e valor não pode ser negativo.',
        );
      }

      if ((item['id'] ?? '').toString().trim().isEmpty) {
        item['origem_local_id'] = await WebOrigemService.instance
            .proximoLocalId();
      }

      item['ordem'] = i;
      item['quantidade'] = quantidade;
      item['valor_unitario'] = valor;
      item['concluido'] = item['concluido'] == true;
      enviados.add(item);
    }

    final baseItens = originais
        .map(
          (item) => <String, Object?>{
            'id': item['id'].toString(),
            'atualizado_em': item['atualizado_em']?.toString(),
          },
        )
        .toList();

    final resposta = await client.rpc(
      'imperium_os_web_editar_v3',
      params: <String, dynamic>{
        'p_empresa_id': empresaId,
        'p_ordem_id': ordem['id'].toString(),
        'p_os_atualizado_em': ordem['atualizado_em']?.toString(),
        'p_header': <String, Object?>{
          'status': status,
          'data_abertura': dataAbertura.trim(),
          'data_inicio': dataInicio.trim(),
          'hora_entrada': horaEntrada.trim(),
          'hora_saida': horaSaida.trim(),
          'funcionario_responsavel': funcionarioResponsavel.trim(),
          'observacoes': observacoes.trim(),
          'quilometragem_entrada': quilometragemEntrada.trim(),
          'combustivel_entrada': combustivelEntrada.trim(),
          'desconto': desconto < 0 ? 0 : desconto,
        },
        'p_itens_base': baseItens,
        'p_itens': enviados,
        'p_origem_dispositivo': dispositivoId,
      },
    );

    return Map<String, dynamic>.from(resposta as Map);
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
