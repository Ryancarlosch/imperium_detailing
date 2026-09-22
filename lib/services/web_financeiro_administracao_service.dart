import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebFinanceiroAdministracaoService {
  WebFinanceiroAdministracaoService._();

  static final WebFinanceiroAdministracaoService instance =
      WebFinanceiroAdministracaoService._();

  final WebOrigemService _origem = WebOrigemService.instance;

  Future<String> _empresaId() async {
    final id = (await AppDatabase.instance.empresaAtivaId ?? '').trim();
    if (id.isEmpty) {
      throw StateError('Nenhuma empresa ativa foi selecionada.');
    }
    return id;
  }

  dynamic get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }
    return client;
  }

  Future<List<Map<String, dynamic>>> _listar(
    String tabela, {
    String ordenarPor = 'criado_em',
    bool crescente = false,
  }) async {
    final empresaId = await _empresaId();
    final resposta = await _client
        .from(tabela)
        .select()
        .eq('empresa_id', empresaId)
        .isFilter('excluido_em', null)
        .order(ordenarPor, ascending: crescente);

    return (resposta as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarFornecedores() => _listar(
    'imperium_financeiro_fornecedores',
    ordenarPor: 'nome',
    crescente: true,
  );

  Future<List<Map<String, dynamic>>> listarRegrasTaxa() => _listar(
    'imperium_financeiro_regras_taxa',
    ordenarPor: 'prioridade',
    crescente: true,
  );

  Future<List<Map<String, dynamic>>> listarCustosFixos() => _listar(
    'imperium_financeiro_custos_fixos',
    ordenarPor: 'nome',
    crescente: true,
  );

  Future<List<Map<String, dynamic>>> listarMetas() =>
      _listar('imperium_financeiro_metas', ordenarPor: 'ano');

  Future<List<Map<String, dynamic>>> listarPlanoContas() => _listar(
    'imperium_financeiro_plano_contas',
    ordenarPor: 'codigo',
    crescente: true,
  );

  Future<List<Map<String, dynamic>>> listarContas() => _listar(
    'imperium_financeiro_contas',
    ordenarPor: 'nome',
    crescente: true,
  );

  Future<List<Map<String, dynamic>>> listarMovimentos() =>
      _listar('imperium_financeiro_movimentos', ordenarPor: 'data');

  Future<List<Map<String, dynamic>>> listarTransferencias() =>
      _listar('imperium_financeiro_transferencias', ordenarPor: 'data');

  Future<List<Map<String, dynamic>>> listarColaboradoresCusto() => _listar(
    'imperium_precificacao_colaboradores_custo',
    ordenarPor: 'nome',
    crescente: true,
  );

  Future<List<Map<String, dynamic>>> listarPagamentosColaboradores() => _listar(
    'imperium_financeiro_pagamentos_colaboradores',
    ordenarPor: 'data_pagamento',
  );

  Future<List<Map<String, dynamic>>> listarHistoricoColaboradores({
    String? colaboradorId,
  }) async {
    final empresaId = await _empresaId();
    var query = _client
        .from('imperium_precificacao_colaboradores_historico')
        .select()
        .eq('empresa_id', empresaId);
    final id = colaboradorId?.trim() ?? '';
    if (id.isNotEmpty) {
      query = query.eq('colaborador_id', id);
    }
    final resposta = await query.order('vigencia_em', ascending: false);
    return (resposta as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _salvar({
    required String tabela,
    required Map<String, Object?> valores,
    String? id,
  }) async {
    final empresaId = await _empresaId();
    final idLimpo = id?.trim() ?? '';

    if (idLimpo.isEmpty) {
      final origem = await _origem.proxima();
      await _client.from(tabela).insert(<String, Object?>{
        'empresa_id': empresaId,
        'origem_dispositivo': origem.dispositivoId,
        'origem_local_id': origem.localId,
        ...valores,
        'origem_criado_em': DateTime.now().toIso8601String(),
        'origem_atualizado_em': DateTime.now().toIso8601String(),
      });
      return;
    }

    await _client
        .from(tabela)
        .update(<String, Object?>{
          ...valores,
          'origem_atualizado_em': DateTime.now().toIso8601String(),
        })
        .eq('empresa_id', empresaId)
        .eq('id', idLimpo);
  }

  Future<void> salvarFornecedor({
    String? id,
    required String nome,
    String documento = '',
    String telefone = '',
    String email = '',
    String endereco = '',
    String cidade = '',
    String estado = '',
    String categoria = '',
    String observacoes = '',
    bool ativo = true,
  }) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.length < 2) {
      throw ArgumentError('Informe o nome do fornecedor.');
    }

    await _salvar(
      tabela: 'imperium_financeiro_fornecedores',
      id: id,
      valores: <String, Object?>{
        'nome': nomeLimpo,
        'documento': documento.trim(),
        'telefone': telefone.trim(),
        'email': email.trim(),
        'endereco': endereco.trim(),
        'cidade': cidade.trim(),
        'estado': estado.trim().toUpperCase(),
        'categoria': categoria.trim(),
        'observacoes': observacoes.trim(),
        'ativo': ativo,
        'excluido_em': null,
      },
    );
  }

  Future<void> salvarRegraTaxa({
    String? id,
    required String nome,
    required String formaPagamento,
    required int parcelas,
    String? contaId,
    required double taxaPercentual,
    required double taxaFixa,
    required int prazoRecebimentoDias,
    required int prioridade,
    required bool repassarCliente,
    String observacoes = '',
    bool ativo = true,
  }) async {
    if (nome.trim().isEmpty) {
      throw ArgumentError('Informe o nome da regra.');
    }
    if (parcelas < 1 || parcelas > 12) {
      throw ArgumentError('As parcelas devem ficar entre 1 e 12.');
    }
    if (taxaPercentual < 0 || taxaFixa < 0 || prazoRecebimentoDias < 0) {
      throw ArgumentError('Taxas e prazo não podem ser negativos.');
    }

    await _salvar(
      tabela: 'imperium_financeiro_regras_taxa',
      id: id,
      valores: <String, Object?>{
        'nome': nome.trim(),
        'forma_pagamento': formaPagamento.trim(),
        'parcelas': parcelas,
        'conta_id': _nulo(contaId),
        'taxa_percentual': taxaPercentual,
        'taxa_fixa': taxaFixa,
        'prazo_recebimento_dias': prazoRecebimentoDias,
        'prioridade': prioridade,
        'repassar_cliente': repassarCliente,
        'observacoes': observacoes.trim(),
        'ativo': ativo,
        'excluido_em': null,
      },
    );
  }

  Future<void> salvarCustoFixo({
    String? id,
    required String nome,
    required double valorMensal,
    String categoria = 'Despesa fixa',
    int? diaVencimento,
    String? planoContaId,
    String observacoes = '',
    bool ativo = true,
  }) async {
    if (nome.trim().isEmpty) {
      throw ArgumentError('Informe o nome do custo fixo.');
    }
    if (valorMensal < 0) {
      throw ArgumentError('O valor mensal não pode ser negativo.');
    }
    if (diaVencimento != null && (diaVencimento < 1 || diaVencimento > 31)) {
      throw ArgumentError('O dia de vencimento deve ficar entre 1 e 31.');
    }

    await _salvar(
      tabela: 'imperium_financeiro_custos_fixos',
      id: id,
      valores: <String, Object?>{
        'nome': nome.trim(),
        'valor_mensal': valorMensal,
        'categoria': categoria.trim().isEmpty
            ? 'Despesa fixa'
            : categoria.trim(),
        'dia_vencimento': diaVencimento,
        'plano_conta_id': _nulo(planoContaId),
        'observacoes': observacoes.trim(),
        'ativo': ativo,
        'excluido_em': null,
      },
    );
  }

  Future<void> salvarMeta({
    String? id,
    required int ano,
    required int mes,
    required String tipo,
    String? planoContaId,
    required double valorMeta,
    String observacoes = '',
    bool ativo = true,
  }) async {
    if (ano < 2020 || ano > 2100 || mes < 1 || mes > 12) {
      throw ArgumentError('Informe um período válido.');
    }
    if (tipo.trim().isEmpty) {
      throw ArgumentError('Informe o tipo da meta.');
    }
    if (valorMeta < 0) {
      throw ArgumentError('O valor da meta não pode ser negativo.');
    }

    await _salvar(
      tabela: 'imperium_financeiro_metas',
      id: id,
      valores: <String, Object?>{
        'ano': ano,
        'mes': mes,
        'tipo': tipo.trim(),
        'plano_conta_id': _nulo(planoContaId),
        'valor_meta': valorMeta,
        'observacoes': observacoes.trim(),
        'ativo': ativo,
        'excluido_em': null,
      },
    );
  }

  Future<void> salvarPlanoConta({
    String? id,
    required String codigo,
    required String nome,
    required String tipo,
    required String natureza,
    required String grupoDre,
    String? parentCodigo,
    int ordem = 0,
    bool ativo = true,
  }) async {
    if (codigo.trim().isEmpty || nome.trim().isEmpty) {
      throw ArgumentError('Informe código e nome do plano de contas.');
    }

    await _salvar(
      tabela: 'imperium_financeiro_plano_contas',
      id: id,
      valores: <String, Object?>{
        'codigo': codigo.trim(),
        'nome': nome.trim(),
        'tipo': tipo.trim(),
        'natureza': natureza.trim(),
        'grupo_dre': grupoDre.trim().isEmpty ? 'Não DRE' : grupoDre.trim(),
        'parent_codigo': _nulo(parentCodigo),
        'ordem': ordem,
        'ativo': ativo,
        'excluido_em': null,
      },
    );
  }

  Future<Map<String, dynamic>> salvarColaboradorCusto({
    String? id,
    required String nome,
    String funcao = '',
    required double remuneracaoMensal,
    required double encargosMensais,
    required double outrosCustosMensais,
    required double horasProdutivasMes,
    String observacoes = '',
    bool ativo = true,
    DateTime? vigencia,
    String motivo = '',
    String? atualizadoEmBase,
  }) async {
    if (nome.trim().length < 2) {
      throw ArgumentError('Informe o nome do funcionário.');
    }
    if (remuneracaoMensal < 0 ||
        encargosMensais < 0 ||
        outrosCustosMensais < 0) {
      throw ArgumentError('Os custos de mão de obra não podem ser negativos.');
    }
    if (horasProdutivasMes <= 0) {
      throw ArgumentError('Informe as horas produtivas mensais.');
    }

    final empresaId = await _empresaId();
    final historicoOrigem = await _origem.proxima();
    final idLimpo = id?.trim() ?? '';
    final colaboradorOrigem = idLimpo.isEmpty
        ? await _origem.proxima()
        : historicoOrigem;
    final base = atualizadoEmBase?.trim() ?? '';

    final raw = await _client.rpc(
      'imperium_precificacao_salvar_colaborador_web',
      params: <String, Object?>{
        'p_empresa_id': empresaId,
        'p_colaborador_id': idLimpo.isEmpty ? null : idLimpo,
        'p_nome': nome.trim(),
        'p_funcao': funcao.trim(),
        'p_remuneracao_mensal': remuneracaoMensal,
        'p_encargos_mensais': encargosMensais,
        'p_outros_custos_mensais': outrosCustosMensais,
        'p_horas_produtivas_mes': horasProdutivasMes,
        'p_observacoes': observacoes.trim(),
        'p_ativo': ativo,
        'p_origem_dispositivo': historicoOrigem.dispositivoId,
        'p_colaborador_local_id': idLimpo.isEmpty
            ? colaboradorOrigem.localId
            : 0,
        'p_historico_local_id': historicoOrigem.localId,
        'p_vigencia_em': (vigencia ?? DateTime.now()).toIso8601String(),
        'p_motivo': motivo.trim(),
        'p_atualizado_em_base': base.isEmpty ? null : base,
      },
    );

    if (raw is! Map) {
      throw StateError('O funcionário não retornou um resultado válido.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> registrarPagamentoColaborador({
    required String colaboradorId,
    required String contaId,
    required double valor,
    required DateTime dataPagamento,
    required String formaPagamento,
    String observacoes = '',
  }) async {
    final colaborador = colaboradorId.trim();
    final conta = contaId.trim();
    if (colaborador.isEmpty) {
      throw ArgumentError('Selecione o funcionário.');
    }
    if (conta.isEmpty) {
      throw ArgumentError('Selecione a conta de pagamento.');
    }
    if (valor <= 0) {
      throw ArgumentError('O valor do pagamento deve ser maior que zero.');
    }

    final empresaId = await _empresaId();
    final pagamento = await _origem.proxima();
    final movimento = await _origem.proxima();

    final raw = await _client.rpc(
      'imperium_financeiro_pagar_colaborador_web',
      params: <String, Object?>{
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaborador,
        'p_conta_id': conta,
        'p_valor': valor,
        'p_data_pagamento': dataPagamento.toIso8601String(),
        'p_forma_pagamento': formaPagamento.trim(),
        'p_observacoes': observacoes.trim(),
        'p_origem_dispositivo': pagamento.dispositivoId,
        'p_pagamento_local_id': pagamento.localId,
        'p_movimento_local_id': movimento.localId,
      },
    );

    if (raw is! Map) {
      throw StateError('O pagamento não retornou um resultado válido.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<String> transferir({
    required String contaOrigemId,
    required String contaDestinoId,
    required double valor,
    required DateTime data,
    String descricao = 'Transferência entre contas',
    String observacoes = '',
  }) async {
    if (contaOrigemId == contaDestinoId) {
      throw ArgumentError('Selecione contas diferentes para a transferência.');
    }
    if (valor <= 0) {
      throw ArgumentError('O valor da transferência deve ser maior que zero.');
    }

    final empresaId = await _empresaId();
    final transferencia = await _origem.proxima();
    final saida = await _origem.proxima();
    final entrada = await _origem.proxima();

    final resposta = await _client.rpc(
      'imperium_financeiro_transferir_web',
      params: <String, Object?>{
        'p_empresa_id': empresaId,
        'p_conta_origem_id': contaOrigemId,
        'p_conta_destino_id': contaDestinoId,
        'p_valor': valor,
        'p_data': data.toIso8601String(),
        'p_descricao': descricao.trim(),
        'p_observacoes': observacoes.trim(),
        'p_origem_dispositivo': transferencia.dispositivoId,
        'p_origem_local_id': transferencia.localId,
        'p_saida_local_id': saida.localId,
        'p_entrada_local_id': entrada.localId,
      },
    );

    final id = resposta?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw StateError('A transferência não retornou um identificador.');
    }
    return id;
  }

  String? _nulo(String? value) {
    final texto = value?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
