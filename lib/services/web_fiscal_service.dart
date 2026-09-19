// ignore_for_file: prefer_interpolation_to_compose_strings

import '../database/app_database.dart';
import '../services/nota_fiscal_entrada_xml_service.dart';
import 'supabase_bootstrap.dart';
import 'web_estoque_cloud_service.dart';
import 'web_origem_service.dart';

class WebFiscalPacote {
  const WebFiscalPacote({
    required this.notas,
    required this.itens,
    required this.estoque,
    required this.contas,
    required this.planoContas,
  });

  final List<Map<String, dynamic>> notas;
  final List<Map<String, dynamic>> itens;
  final List<Map<String, dynamic>> estoque;
  final List<Map<String, dynamic>> contas;
  final List<Map<String, dynamic>> planoContas;
}

class WebFiscalService {
  WebFiscalService._();

  static final WebFiscalService instance = WebFiscalService._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir o Fiscal.');
    }
    return empresa;
  }

  dynamic get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');
    return client;
  }

  Future<WebFiscalPacote> carregar() async {
    final empresaId = await _empresaId();

    final resultados = await Future.wait<dynamic>([
      _client
          .from('imperium_fiscal_notas_entrada')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null)
          .order('criado_em', ascending: false),
      _client
          .from('imperium_fiscal_notas_itens')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null)
          .order('numero_item'),
      WebEstoqueCloudService.instance.listarItens(),
      _client
          .from('imperium_financeiro_contas')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null)
          .eq('ativo', true)
          .order('nome'),
      _client
          .from('imperium_financeiro_plano_contas')
          .select()
          .eq('empresa_id', empresaId)
          .isFilter('excluido_em', null)
          .eq('ativo', true)
          .order('codigo'),
    ]);

    return WebFiscalPacote(
      notas: _lista(resultados[0]),
      itens: _lista(resultados[1]),
      estoque: resultados[2] as List<Map<String, dynamic>>,
      contas: _lista(resultados[3]),
      planoContas: _lista(resultados[4]),
    );
  }

  Future<Map<String, dynamic>> importarXml(String xml) async {
    final empresaId = await _empresaId();
    final parser = NotaFiscalEntradaXmlService();
    final parsed = parser.parsear(xml);
    final nota = parsed.nota;
    final itens = parsed.itens;
    final chave = nota.chaveAcesso.trim();

    Map<String, dynamic>? existente;
    final existenteRaw = await _client
        .from('imperium_fiscal_notas_entrada')
        .select()
        .eq('empresa_id', empresaId)
        .eq('chave_acesso', chave)
        .maybeSingle();
    if (existenteRaw != null) {
      existente = Map<String, dynamic>.from(existenteRaw as Map);
    }

    final origem = existente == null
        ? await WebOrigemService.instance.proxima()
        : null;

    final payload = <String, dynamic>{
      'empresa_id': empresaId,
      if (existente == null) 'origem_dispositivo': origem!.dispositivoId,
      if (existente == null) 'origem_local_id': origem!.localId,
      'chave_acesso': chave,
      'modelo': nota.modelo,
      'numero': nota.numero,
      'serie': nota.serie,
      'data_emissao': nota.dataEmissao,
      'fornecedor_id': existente?['fornecedor_id'],
      'emitente_cnpj_cpf': nota.emitenteCnpjCpf,
      'emitente_nome': nota.emitenteNome,
      'valor_produtos': nota.valorProdutos,
      'valor_frete': nota.valorFrete,
      'valor_seguro': nota.valorSeguro,
      'valor_desconto': nota.valorDesconto,
      'valor_outras_despesas': nota.valorOutrasDespesas,
      'valor_ipi': nota.valorIpi,
      'valor_icms_st': nota.valorIcmsSt,
      'valor_total': nota.valorTotal,
      'situacao_fiscal': nota.situacaoFiscal,
      'status_importacao': 'processada',
      'origem_importacao': nota.origemImportacao,
      'xml_original': nota.xmlOriginal,
      'xml_hash': nota.xmlHash,
      'consulta_url': nota.consultaUrl,
      'tentativas_importacao': existente?['tentativas_importacao'] ?? 0,
      'ultima_tentativa_em': DateTime.now().toUtc().toIso8601String(),
      'ultimo_erro_codigo': '',
      'ultimo_erro_mensagem': '',
      'importada_em': existente?['importada_em'] ?? nota.importadaEm,
      'observacoes': existente?['observacoes'] ?? nota.observacoes,
      'excluido_em': null,
    };

    final Map<String, dynamic> salva;
    if (existente == null) {
      final raw = await _client
          .from('imperium_fiscal_notas_entrada')
          .insert(payload)
          .select()
          .single();
      salva = Map<String, dynamic>.from(raw as Map);
    } else {
      final rows = await _client
          .from('imperium_fiscal_notas_entrada')
          .update(payload)
          .eq('empresa_id', empresaId)
          .eq('id', existente['id'])
          .eq('atualizado_em', existente['atualizado_em'])
          .select();
      if ((rows as List).isEmpty) {
        throw StateError(
          'A nota foi alterada em outro dispositivo. Atualize e tente novamente.',
        );
      }
      salva = Map<String, dynamic>.from(rows.first as Map);
    }

    final notaId = salva['id'].toString();
    final atuaisRaw = await _client
        .from('imperium_fiscal_notas_itens')
        .select()
        .eq('empresa_id', empresaId)
        .eq('nota_fiscal_id', notaId);
    final atuais = _lista(atuaisRaw);
    final numerosNovos = itens.map((e) => e.numeroItem).toSet();

    for (final atual in atuais) {
      final numero = _int(atual['numero_item']);
      if (!numerosNovos.contains(numero) &&
          (atual['estoque_item_id'] ?? '').toString().trim().isEmpty) {
        await _client
            .from('imperium_fiscal_notas_itens')
            .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
            .eq('empresa_id', empresaId)
            .eq('id', atual['id']);
      }
    }

    for (final item in itens) {
      Map<String, dynamic>? atual;
      for (final candidato in atuais) {
        if (_int(candidato['numero_item']) == item.numeroItem) {
          atual = candidato;
          break;
        }
      }

      final itemPayload = <String, dynamic>{
        'empresa_id': empresaId,
        'nota_fiscal_id': notaId,
        'numero_item': item.numeroItem,
        'codigo_produto': item.codigoProduto,
        'ean': item.ean,
        'descricao': item.descricao,
        'ncm': item.ncm,
        'cfop': item.cfop,
        'unidade': item.unidade,
        'quantidade': item.quantidade,
        'valor_unitario': item.valorUnitario,
        'valor_total': item.valorTotal,
        'valor_desconto': item.valorDesconto,
        'estoque_item_id': atual?['estoque_item_id'],
        'observacoes': atual?['observacoes'] ?? item.observacoes,
        'origem_local_item_id': atual?['origem_local_item_id'],
        'excluido_em': null,
      };

      await _client
          .from('imperium_fiscal_notas_itens')
          .upsert(itemPayload, onConflict: 'nota_fiscal_id,numero_item');
    }

    await _registrarTentativa(
      empresaId: empresaId,
      notaId: notaId,
      chave: chave,
      modelo: nota.modelo,
      resultado: 'sucesso',
      codigo: 'xml_imported',
      mensagem: 'XML fiscal validado e importado no Cloud.',
    );

    return salva;
  }

  Future<void> vincularItemEstoque({
    required String itemFiscalId,
    required String? estoqueItemId,
  }) async {
    final empresaId = await _empresaId();
    await _client
        .from('imperium_fiscal_notas_itens')
        .update({
          'estoque_item_id': (estoqueItemId ?? '').trim().isEmpty
              ? null
              : estoqueItemId,
        })
        .eq('empresa_id', empresaId)
        .eq('id', itemFiscalId);
  }

  Future<void> confirmarEntradaEstoque(String notaId) async {
    final empresaId = await _empresaId();

    final notaRaw = await _client
        .from('imperium_fiscal_notas_entrada')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', notaId)
        .single();
    final nota = Map<String, dynamic>.from(notaRaw as Map);

    if ((nota['situacao_fiscal'] ?? '').toString() != 'autorizada') {
      throw StateError(
        'Somente documento fiscal autorizado pode gerar entrada de estoque.',
      );
    }
    if ((nota['status_importacao'] ?? '').toString() != 'processada') {
      throw StateError('A nota precisa estar processada.');
    }

    final itensRaw = await _client
        .from('imperium_fiscal_notas_itens')
        .select()
        .eq('empresa_id', empresaId)
        .eq('nota_fiscal_id', notaId)
        .isFilter('excluido_em', null)
        .order('numero_item');
    final itens = _lista(itensRaw);
    if (itens.isEmpty) throw StateError('A nota não possui itens.');

    final estoque = await WebEstoqueCloudService.instance.listarItens();
    for (final item in itens) {
      final estoqueId = (item['estoque_item_id'] ?? '').toString().trim();
      if (estoqueId.isEmpty) {
        throw StateError(
          'Todos os itens fiscais precisam estar vinculados ao estoque.',
        );
      }

      final existente = await _client
          .from('imperium_estoque_movimentacoes')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('fiscal_item_id', item['id'])
          .maybeSingle();
      if (existente != null) continue;

      Map<String, dynamic>? estoqueItem;
      for (final candidato in estoque) {
        if (candidato['id'].toString() == estoqueId) {
          estoqueItem = candidato;
          break;
        }
      }
      if (estoqueItem == null) {
        throw StateError('Produto de estoque vinculado não está ativo.');
      }

      final valorPago =
          (_double(item['valor_total']) - _double(item['valor_desconto']))
              .clamp(0.01, double.infinity)
              .toDouble();

      final resultado = await WebEstoqueCloudService.instance.movimentar(
        item: estoqueItem,
        tipo: 'ENTRADA',
        quantidade: _double(item['quantidade']),
        unidadeOriginal: (item['unidade'] ?? 'unidade').toString(),
        valorTotalPago: valorPago,
        fornecedor: (nota['emitente_nome'] ?? '').toString(),
        observacoes: 'Entrada fiscal NF ' + (nota['numero'] ?? '').toString(),
      );

      final movimentoId = (resultado['movimento_id'] ?? '').toString();
      if (movimentoId.isNotEmpty) {
        await _client
            .from('imperium_estoque_movimentacoes')
            .update({
              'fiscal_nota_id': notaId,
              'fiscal_item_id': item['id'],
              'origem': 'Nota fiscal',
            })
            .eq('empresa_id', empresaId)
            .eq('id', movimentoId);
      }
    }
  }

  Future<void> registrarFinanceiro({
    required String notaId,
    required String status,
    required DateTime competencia,
    DateTime? vencimento,
    String? contaId,
    String? planoContaId,
    String formaPagamento = '',
  }) async {
    final empresaId = await _empresaId();

    final existente = await _client
        .from('imperium_financeiro_movimentos')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('fiscal_nota_id', notaId)
        .isFilter('excluido_em', null)
        .maybeSingle();
    if (existente != null) {
      throw StateError('Esta nota já possui lançamento financeiro.');
    }

    final notaRaw = await _client
        .from('imperium_fiscal_notas_entrada')
        .select()
        .eq('empresa_id', empresaId)
        .eq('id', notaId)
        .single();
    final nota = Map<String, dynamic>.from(notaRaw as Map);
    final valor = _double(nota['valor_total']);
    if (valor <= 0) throw StateError('A nota não possui valor total válido.');

    final statusNormalizado = status.toLowerCase() == 'realizado'
        ? 'Realizado'
        : 'Previsto';

    if (statusNormalizado == 'Realizado' && (contaId ?? '').trim().isEmpty) {
      throw StateError('Selecione a conta para o pagamento realizado.');
    }

    Map<String, dynamic>? plano;
    if ((planoContaId ?? '').trim().isNotEmpty) {
      final raw = await _client
          .from('imperium_financeiro_plano_contas')
          .select()
          .eq('empresa_id', empresaId)
          .eq('id', planoContaId)
          .eq('ativo', true)
          .maybeSingle();
      if (raw != null) plano = Map<String, dynamic>.from(raw as Map);
    }

    final origem = await WebOrigemService.instance.proxima();
    final competenciaIso = competencia.toIso8601String();
    final vencimentoIso = (vencimento ?? competencia).toIso8601String();

    await _client.from('imperium_financeiro_movimentos').insert({
      'empresa_id': empresaId,
      'origem_dispositivo': origem.dispositivoId,
      'origem_local_id': origem.localId,
      'tipo': 'Saída',
      'descricao':
          'Nota fiscal ' + (nota['numero'] ?? nota['chave_acesso']).toString(),
      'valor': valor,
      'forma_pagamento': formaPagamento.trim().isEmpty
          ? null
          : formaPagamento.trim(),
      'data': statusNormalizado == 'Realizado' ? competenciaIso : vencimentoIso,
      'plano_conta_id': plano?['id'],
      'conta_id': (contaId ?? '').trim().isEmpty ? null : contaId!.trim(),
      'natureza': (plano?['natureza'] ?? 'Despesa').toString(),
      'origem': 'Nota fiscal',
      'status': statusNormalizado,
      'data_competencia': competenciaIso,
      'data_vencimento': vencimentoIso,
      'data_pagamento': statusNormalizado == 'Realizado'
          ? competenciaIso
          : null,
      'numero_documento': (nota['numero'] ?? '').toString(),
      'observacoes': 'Emitente: ' + (nota['emitente_nome'] ?? '').toString(),
      'impacta_dre': (plano?['grupo_dre'] ?? '').toString() != 'Não DRE',
      'fiscal_nota_id': notaId,
      'excluido_em': null,
    });
  }

  Future<void> excluirNota(String notaId) async {
    final empresaId = await _empresaId();

    final estoque = await _client
        .from('imperium_estoque_movimentacoes')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('fiscal_nota_id', notaId)
        .limit(1);
    final financeiro = await _client
        .from('imperium_financeiro_movimentos')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('fiscal_nota_id', notaId)
        .isFilter('excluido_em', null)
        .limit(1);

    if ((estoque as List).isNotEmpty || (financeiro as List).isNotEmpty) {
      throw StateError(
        'A nota possui integração com estoque ou financeiro e não pode ser excluída diretamente.',
      );
    }

    await _client
        .from('imperium_fiscal_notas_entrada')
        .update({'excluido_em': DateTime.now().toUtc().toIso8601String()})
        .eq('empresa_id', empresaId)
        .eq('id', notaId);
  }

  Future<void> _registrarTentativa({
    required String empresaId,
    required String notaId,
    required String chave,
    required int? modelo,
    required String resultado,
    required String codigo,
    required String mensagem,
  }) {
    return _client.from('imperium_fiscal_importacao_tentativas').insert({
      'empresa_id': empresaId,
      'nota_fiscal_id': notaId,
      'chave_acesso': chave,
      'modelo': modelo,
      'canal': 'xml',
      'resultado': resultado,
      'codigo': codigo,
      'mensagem': mensagem,
    });
  }

  static List<Map<String, dynamic>> _lista(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
