import '../database/app_database.dart';
import '../domain/ordem_servico_valor.dart';
import 'supabase_bootstrap.dart';
import 'web_estoque_cloud_service.dart';

class WebPendenciaOperacional {
  const WebPendenciaOperacional({
    required this.tipo,
    required this.nivel,
    required this.titulo,
    required this.descricao,
    required this.moduloIndice,
    this.valor = 0,
    this.data,
  });

  final String tipo;
  final String nivel;
  final String titulo;
  final String descricao;
  final int moduloIndice;
  final double valor;
  final DateTime? data;

  bool get critica => nivel == 'Crítica';
}

class WebPendenciasOperacionaisResumo {
  const WebPendenciasOperacionaisResumo(this.itens);

  final List<WebPendenciaOperacional> itens;

  int get criticas => itens.where((e) => e.critica).length;
  int get atencoes => itens.length - criticas;

  int quantidade(String tipo) => itens.where((e) => e.tipo == tipo).length;

  double valor(String tipo) => itens
      .where((e) => e.tipo == tipo)
      .fold<double>(0, (total, e) => total + e.valor);
}

class WebPendenciasOperacionaisService {
  WebPendenciasOperacionaisService._();

  static final WebPendenciasOperacionaisService instance =
      WebPendenciasOperacionaisService._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir Pendências.');
    }
    return empresa;
  }

  Future<WebPendenciasOperacionaisResumo> carregar() async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    final resultados = await Future.wait<dynamic>([
      client
          .from('imperium_ordens_servico')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null),
      client
          .from('imperium_financeiro_pagamentos_os')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null),
      client
          .from('imperium_financeiro_movimentos')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null),
      client
          .from('ponto_registros')
          .select()
          .eq('empresa_id', empresaId),
      client
          .from('ponto_colaboradores')
          .select()
          .eq('empresa_id', empresaId)
          .eq('ativo', true),
      client
          .from('ponto_solicitacoes_ajuste')
          .select()
          .eq('empresa_id', empresaId)
          .eq('status', 'Pendente'),
      WebEstoqueCloudService.instance.listarItens(),
      WebEstoqueCloudService.instance.listarAlertas(),
    ]);

    final ordens = _lista(resultados[0]);
    final pagamentos = _lista(resultados[1]);
    final movimentos = _lista(resultados[2]);
    final registrosPonto = _lista(resultados[3]);
    final colaboradores = _lista(resultados[4]);
    final solicitacoesPonto = _lista(resultados[5]);
    final estoque = resultados[6] as List<Map<String, dynamic>>;
    final alertasEstoque = resultados[7] as List<Map<String, dynamic>>;

    final itens = <WebPendenciaOperacional>[
      ..._recebimentosVencidos(ordens, pagamentos, hoje),
      ..._contasPagar(movimentos, hoje),
      ..._ordensParadas(ordens, hoje),
      ..._estoque(estoque, alertasEstoque),
      ..._ponto(
        colaboradores: colaboradores,
        registros: registrosPonto,
        solicitacoes: solicitacoesPonto,
        hoje: hoje,
      ),
    ];

    const prioridade = <String, int>{'Crítica': 0, 'Atenção': 1};
    itens.sort((a, b) {
      final nivel = (prioridade[a.nivel] ?? 9).compareTo(
        prioridade[b.nivel] ?? 9,
      );
      if (nivel != 0) return nivel;
      if (a.data != null && b.data != null) {
        return a.data!.compareTo(b.data!);
      }
      return a.titulo.compareTo(b.titulo);
    });

    return WebPendenciasOperacionaisResumo(itens);
  }

  List<WebPendenciaOperacional> _recebimentosVencidos(
    List<Map<String, dynamic>> ordens,
    List<Map<String, dynamic>> pagamentos,
    DateTime hoje,
  ) {
    final itens = <WebPendenciaOperacional>[];
    final ordensComParcelas = <String>{};

    for (final pagamento in pagamentos) {
      final osId = _texto(pagamento['ordem_servico_id']);
      if (osId.isNotEmpty) ordensComParcelas.add(osId);

      final status = _texto(pagamento['status']).toLowerCase();
      final vencimento = _data(pagamento['vencimento']);
      final estornado = _texto(pagamento['estornado_em']).isNotEmpty;
      if (estornado ||
          vencimento == null ||
          !vencimento.isBefore(hoje) ||
          _pago(status)) {
        continue;
      }

      final ordem = _porId(ordens, osId);
      final numero = _texto(ordem?['numero']);
      final parcela = _int(pagamento['parcela_numero']);
      final totalParcelas = _int(pagamento['total_parcelas']);
      final partes = <String>[
        if (numero.isNotEmpty) 'OS ' + numero,
        if (parcela > 0)
          totalParcelas > 0
              ? 'parcela ' + parcela.toString() + '/' + totalParcelas.toString()
              : 'parcela ' + parcela.toString(),
        'recebimento vencido',
      ];

      itens.add(
        WebPendenciaOperacional(
          tipo: 'Recebimentos',
          nivel: 'Crítica',
          titulo: partes.join(' · '),
          descricao: 'Venceu em ' + _dataBr(vencimento),
          moduloIndice: 9,
          valor: _double(pagamento['valor']),
          data: vencimento,
        ),
      );
    }

    for (final ordem in ordens) {
      final id = _texto(ordem['id']);
      if (ordensComParcelas.contains(id)) continue;

      final statusPagamento = _texto(ordem['status_pagamento']).toLowerCase();
      final vencimento = _data(ordem['vencimento_pagamento']);
      if (_pago(statusPagamento) ||
          vencimento == null ||
          !vencimento.isBefore(hoje)) {
        continue;
      }

      final negociado = OrdemServicoValor.valorNegociado(
        valorTotal: _double(ordem['valor_total']),
        desconto: _double(ordem['desconto']),
        descontoNegociacao: _double(ordem['desconto_negociacao']),
        acrescimoNegociacao: _double(ordem['acrescimo_negociacao']),
        jurosParcelamento: _double(ordem['juros_parcelamento']),
      );
      final pendente =
          (negociado - _double(ordem['valor_recebido'])).clamp(
            0,
            double.infinity,
          );
      if (pendente <= 0.001) continue;

      final numero = _texto(ordem['numero']).isEmpty
          ? id
          : _texto(ordem['numero']);

      itens.add(
        WebPendenciaOperacional(
          tipo: 'Recebimentos',
          nivel: 'Crítica',
          titulo: 'OS ' + numero + ' · recebimento vencido',
          descricao: 'Venceu em ' + _dataBr(vencimento),
          moduloIndice: 9,
          valor: pendente,
          data: vencimento,
        ),
      );
    }

    return itens;
  }

  List<WebPendenciaOperacional> _contasPagar(
    List<Map<String, dynamic>> movimentos,
    DateTime hoje,
  ) {
    final limite = hoje.add(const Duration(days: 7));
    final itens = <WebPendenciaOperacional>[];

    for (final movimento in movimentos) {
      final tipo = _texto(movimento['tipo']).toLowerCase();
      final natureza = _texto(movimento['natureza']).toLowerCase();
      final status = _texto(movimento['status']).toLowerCase();
      final vencimento = _data(movimento['data_vencimento']);

      final saida =
          tipo.contains('saída') ||
          tipo.contains('saida') ||
          natureza.contains('despesa') ||
          natureza.contains('custo');

      if (!saida || vencimento == null || _realizado(status)) continue;
      if (vencimento.isAfter(limite)) continue;

      final vencida = vencimento.isBefore(hoje);
      itens.add(
        WebPendenciaOperacional(
          tipo: 'Contas a pagar',
          nivel: vencida ? 'Crítica' : 'Atenção',
          titulo: _texto(movimento['descricao']).isEmpty
              ? vencida
                    ? 'Conta a pagar vencida'
                    : 'Conta a pagar próxima'
              : _texto(movimento['descricao']),
          descricao: vencida
              ? 'Venceu em ' + _dataBr(vencimento)
              : _mesmoDia(vencimento, hoje)
              ? 'Vence hoje'
              : 'Vence em ' + _dataBr(vencimento),
          moduloIndice: 9,
          valor: _double(movimento['valor']),
          data: vencimento,
        ),
      );
    }

    return itens;
  }

  List<WebPendenciaOperacional> _ordensParadas(
    List<Map<String, dynamic>> ordens,
    DateTime hoje,
  ) {
    final itens = <WebPendenciaOperacional>[];

    for (final ordem in ordens) {
      final status = _texto(ordem['status']);
      final normalizado = status.toLowerCase();
      if (normalizado != 'aberta' && normalizado != 'em andamento') continue;

      final base = _data(
        normalizado == 'em andamento'
            ? ordem['data_inicio'] ?? ordem['data_abertura']
            : ordem['data_abertura'],
      );
      if (base == null) continue;

      final dias =
          hoje.difference(DateTime(base.year, base.month, base.day)).inDays;
      if (dias <= 7) continue;

      final numero = _texto(ordem['numero']).isEmpty
          ? _texto(ordem['id'])
          : _texto(ordem['numero']);

      itens.add(
        WebPendenciaOperacional(
          tipo: 'Ordens de serviço',
          nivel: dias > 14 ? 'Crítica' : 'Atenção',
          titulo: 'OS ' + numero + ' · ' + status,
          descricao: 'Sem avanço há ' + dias.toString() + ' dias',
          moduloIndice: 4,
          data: base,
        ),
      );
    }

    return itens;
  }

  List<WebPendenciaOperacional> _estoque(
    List<Map<String, dynamic>> estoque,
    List<Map<String, dynamic>> alertas,
  ) {
    final itens = <WebPendenciaOperacional>[];
    final alertados = <String>{};

    for (final alerta in alertas) {
      final status = _texto(alerta['status']).toLowerCase();
      if (status == 'resolvido' || status == 'fechado') continue;

      final itemId = _texto(alerta['item_estoque_id']);
      if (itemId.isNotEmpty) alertados.add(itemId);

      final saldo = _double(alerta['saldo_atual']);
      final limite = _double(alerta['limite']);
      final zerado = saldo <= 0.000001;

      itens.add(
        WebPendenciaOperacional(
          tipo: 'Estoque',
          nivel: zerado ? 'Crítica' : 'Atenção',
          titulo: _texto(alerta['mensagem']).isEmpty
              ? zerado
                    ? 'Estoque zerado'
                    : 'Estoque baixo'
              : _texto(alerta['mensagem']),
          descricao: zerado
              ? 'Saldo atual: 0'
              : 'Saldo ' + _numero(saldo) + ' · mínimo ' + _numero(limite),
          moduloIndice: 8,
        ),
      );
    }

    for (final item in estoque) {
      final id = _texto(item['id']);
      if (alertados.contains(id) || item['ativo'] == false) continue;

      final saldo = _double(item['quantidade']);
      final minimo = _double(item['quantidade_minima']);
      final zerado = saldo <= 0.000001;
      final baixo = minimo > 0 && saldo <= minimo;
      if (!zerado && !baixo) continue;

      final unidade = _texto(item['unidade']);
      final nome = _texto(item['nome']).isEmpty
          ? 'Produto'
          : _texto(item['nome']);

      itens.add(
        WebPendenciaOperacional(
          tipo: 'Estoque',
          nivel: zerado ? 'Crítica' : 'Atenção',
          titulo: zerado
              ? 'Estoque zerado: ' + nome
              : 'Estoque baixo: ' + nome,
          descricao: zerado
              ? 'Saldo atual: 0' + (unidade.isEmpty ? '' : ' ' + unidade)
              : 'Saldo ' +
                    _numero(saldo) +
                    (unidade.isEmpty ? '' : ' ' + unidade) +
                    ' · mínimo ' +
                    _numero(minimo),
          moduloIndice: 8,
        ),
      );
    }

    return itens;
  }

  List<WebPendenciaOperacional> _ponto({
    required List<Map<String, dynamic>> colaboradores,
    required List<Map<String, dynamic>> registros,
    required List<Map<String, dynamic>> solicitacoes,
    required DateTime hoje,
  }) {
    final itens = <WebPendenciaOperacional>[];
    final inicioMes = DateTime(hoje.year, hoje.month, 1);

    for (final colaborador in colaboradores) {
      final id = _texto(colaborador['id']);
      if (id.isEmpty) continue;

      var incompletos = 0;
      var pendentes = 0;

      for (final registro in registros) {
        if (_texto(registro['colaborador_id']) != id) continue;
        final data = _data(registro['data']);
        if (data == null || data.isBefore(inicioMes) || data.isAfter(hoje)) {
          continue;
        }

        final situacao = _texto(registro['situacao']).toLowerCase();
        if (situacao.contains('pendente')) pendentes++;
        if (_texto(registro['entrada']).isNotEmpty &&
            _texto(registro['saida']).isEmpty &&
            data.isBefore(hoje)) {
          incompletos++;
        }
      }

      final ajustes = solicitacoes
          .where((e) => _texto(e['colaborador_id']) == id)
          .length;
      pendentes += ajustes;

      if (incompletos == 0 && pendentes == 0) continue;

      final partes = <String>[
        if (pendentes > 0) pendentes.toString() + ' pendência(s)',
        if (incompletos > 0) incompletos.toString() + ' ponto(s) incompleto(s)',
      ];

      final nome = _texto(colaborador['nome']).isEmpty
          ? 'Funcionário'
          : _texto(colaborador['nome']);

      itens.add(
        WebPendenciaOperacional(
          tipo: 'Ponto',
          nivel: incompletos > 0 ? 'Crítica' : 'Atenção',
          titulo: 'Ponto · ' + nome,
          descricao: partes.join(' · '),
          moduloIndice: 16,
        ),
      );
    }

    return itens;
  }

  static bool _pago(String status) {
    return status.contains('pago') ||
        status.contains('recebido') ||
        status.contains('quitado') ||
        status.contains('estornado') ||
        status.contains('cancelado');
  }

  static bool _realizado(String status) {
    return status.contains('realizado') ||
        status.contains('pago') ||
        status.contains('quitado') ||
        status.contains('cancelado');
  }

  static Map<String, dynamic>? _porId(
    List<Map<String, dynamic>> itens,
    String id,
  ) {
    for (final item in itens) {
      if (_texto(item['id']) == id) return item;
    }
    return null;
  }

  static List<Map<String, dynamic>> _lista(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static DateTime? _data(dynamic value) {
    final texto = _texto(value);
    if (texto.isEmpty) return null;
    final iso = DateTime.tryParse(texto);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final partes = texto.split('/');
    if (partes.length == 3) {
      final d = int.tryParse(partes[0]);
      final m = int.tryParse(partes[1]);
      final a = int.tryParse(partes[2]);
      if (d != null && m != null && a != null) return DateTime(a, m, d);
    }
    return null;
  }

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dataBr(DateTime data) {
    final d = data.day.toString().padLeft(2, '0');
    final m = data.month.toString().padLeft(2, '0');
    return d + '/' + m + '/' + data.year.toString();
  }

  static String _texto(dynamic value) => (value ?? '').toString().trim();

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  static String _numero(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }
}
