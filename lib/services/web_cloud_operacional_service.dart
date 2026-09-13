import '../database/app_database.dart';
import '../domain/ordem_servico_valor.dart';
import 'supabase_bootstrap.dart';

class WebCloudOperacionalService {
  WebCloudOperacionalService._();

  static final WebCloudOperacionalService instance =
      WebCloudOperacionalService._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir o módulo Web.');
    }
    return empresa;
  }

  Future<List<Map<String, dynamic>>> _listar(
    String tabela, {
    String? orderBy,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final empresaId = await _empresaId();
    dynamic query = client.from(tabela).select().eq('empresa_id', empresaId);

    if (orderBy != null && orderBy.isNotEmpty) {
      query = query.order(orderBy);
    }

    final resposta = await query;
    return (resposta as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) {
          final excluido = item['excluido_em']?.toString().trim() ?? '';
          return excluido.isEmpty;
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarClientes() {
    return _listar('imperium_clientes', orderBy: 'nome');
  }

  Future<List<Map<String, dynamic>>> listarVeiculos() {
    return _listar('imperium_veiculos', orderBy: 'marca');
  }

  Future<List<Map<String, dynamic>>> listarAgendamentos() {
    return _listar('imperium_agendamentos', orderBy: 'data');
  }

  Future<List<Map<String, dynamic>>> listarOrdens() {
    return _listar('imperium_ordens_servico', orderBy: 'data_abertura');
  }

  Future<void> salvarCliente({
    String? id,
    required String nome,
    required String telefone,
    required String email,
    required String endereco,
    required String observacoes,
    bool ativo = true,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'nome': nome.trim(),
      'telefone': telefone.trim(),
      'email': email.trim(),
      'endereco': endereco.trim(),
      'observacoes': observacoes.trim(),
      'ativo': ativo,
      'arquivado_em': ativo ? null : DateTime.now().toUtc().toIso8601String(),
      'excluido_em': null,
    };

    if (id == null || id.isEmpty) {
      await client.from('imperium_clientes').insert(payload);
    } else {
      await client
          .from('imperium_clientes')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', id);
    }
  }

  Future<void> arquivarCliente(String id, bool arquivar) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    await client
        .from('imperium_clientes')
        .update(<String, dynamic>{
          'ativo': !arquivar,
          'arquivado_em': arquivar
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        })
        .eq('empresa_id', empresaId)
        .eq('id', id);
  }

  Future<void> salvarVeiculo({
    String? id,
    required String clienteId,
    required String marca,
    required String modelo,
    required String placa,
    required String cor,
    required String ano,
    required String observacoes,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'marca': marca.trim(),
      'modelo': modelo.trim(),
      'placa': placa.trim().toUpperCase(),
      'cor': cor.trim(),
      'ano': ano.trim(),
      'observacoes': observacoes.trim(),
      'excluido_em': null,
    };

    if (id == null || id.isEmpty) {
      await client.from('imperium_veiculos').insert(payload);
    } else {
      await client
          .from('imperium_veiculos')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', id);
    }
  }

  Future<void> excluirVeiculo(String id) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    await client
        .from('imperium_veiculos')
        .update(<String, dynamic>{
          'excluido_em': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('empresa_id', empresaId)
        .eq('id', id);
  }

  Future<void> salvarAgendamento({
    String? id,
    required String clienteId,
    required String veiculoId,
    required String servico,
    required String data,
    required String hora,
    required double valor,
    required String status,
    required String observacoes,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'servico': servico.trim(),
      'data': data.trim(),
      'hora': hora.trim(),
      'valor': valor,
      'status': status,
      'observacoes': observacoes.trim(),
      'excluido_em': null,
    };

    if (id == null || id.isEmpty) {
      await client.from('imperium_agendamentos').insert(payload);
    } else {
      await client
          .from('imperium_agendamentos')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', id);
    }
  }

  Future<void> excluirAgendamento(String id) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    await client
        .from('imperium_agendamentos')
        .update(<String, dynamic>{
          'excluido_em': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('empresa_id', empresaId)
        .eq('id', id);
  }

  Future<Map<String, Object?>> carregarResumo() async {
    final resultados = await Future.wait<List<Map<String, dynamic>>>([
      listarClientes(),
      listarVeiculos(),
      listarAgendamentos(),
      listarOrdens(),
    ]);

    final clientes = resultados[0];
    final veiculos = resultados[1];
    final agenda = resultados[2];
    final ordens = resultados[3];

    final agora = DateTime.now();
    var faturamentoMes = 0.0;
    var aReceber = 0.0;
    var ordensAbertas = 0;

    for (final item in ordens) {
      final status = (item['status'] ?? '').toString();

      if (status == 'Aberta' || status == 'Em andamento') {
        ordensAbertas++;
      }

      final negociado = OrdemServicoValor.valorNegociado(
        valorTotal: _double(item['valor_total']),
        desconto: _double(item['desconto']),
        descontoNegociacao: _double(item['desconto_negociacao']),
        acrescimoNegociacao: _double(item['acrescimo_negociacao']),
        jurosParcelamento: _double(item['juros_parcelamento']),
      );

      final recebido = _double(item['valor_recebido']);
      final pendente = (negociado - recebido).clamp(0, double.infinity);
      aReceber += pendente;

      if (status == 'Finalizada') {
        final data = _parseData(item['data_finalizacao']?.toString());
        if (data != null &&
            data.year == agora.year &&
            data.month == agora.month) {
          faturamentoMes += negociado;
        }
      }
    }

    final agendaAberta = agenda.where((item) {
      final status = (item['status'] ?? '').toString().toLowerCase();
      return status != 'cancelado' &&
          status != 'concluído' &&
          status != 'concluido';
    }).length;

    final clientesAtivos = clientes
        .where((item) => item['ativo'] != false)
        .length;

    return <String, Object?>{
      'clientes': clientesAtivos,
      'veiculos': veiculos.length,
      'agenda': agendaAberta,
      'os_abertas': ordensAbertas,
      'faturamento_mes': faturamentoMes,
      'a_receber': aReceber,
    };
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static DateTime? _parseData(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso;

    final partes = texto.split('/');
    if (partes.length != 3) return null;

    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);

    if (dia == null || mes == null || ano == null) return null;
    return DateTime(ano, mes, dia);
  }
}
