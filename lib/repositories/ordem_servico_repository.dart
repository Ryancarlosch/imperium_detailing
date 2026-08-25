import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/ordem_servico.dart';
import '../models/ordem_servico_item.dart';
import '../repositories/agendamento_repository.dart';
import '../repositories/custos_repository.dart';
import '../repositories/pagamento_repository.dart';

class OrdemServicoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  final AgendamentoRepository _agendamentoRepository = AgendamentoRepository();
  final PagamentoRepository _pagamentoRepository = PagamentoRepository();
  final CustosRepository _custosRepository = CustosRepository();

  int? _converterInt(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString().trim());
  }

  Future<int> inserirOrdemServico(
    OrdemServico ordemServico, {
    List<OrdemServicoItem> itens = const [],
  }) async {
    final database = await _appDatabase.database;

    return database.transaction((transaction) async {
      final dadosOrdem = ordemServico.toMap();
      dadosOrdem.remove('id');

      final ordemServicoId = await transaction.insert(
        'ordens_servico',
        dadosOrdem,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (var indice = 0; indice < itens.length; indice++) {
        final item = itens[indice];

        final dadosItem = item
            .copyWith(ordemServicoId: ordemServicoId, ordem: indice)
            .toMap();

        dadosItem.remove('id');

        await transaction.insert('ordem_servico_itens', dadosItem);
      }

      final agendamentoId = _converterInt(ordemServico.agendamentoId);

      if (agendamentoId != null) {
        await _agendamentoRepository.atualizarStatusComTransacao(
          transaction,
          agendamentoId,
          'Agendado',
        );
      }

      return ordemServicoId;
    });
  }

  Future<int?> buscarIdOrdemPorAgendamento(int agendamentoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordens_servico',
      columns: ['id'],
      where: 'agendamento_id = ?',
      whereArgs: [agendamentoId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    final valor = resultado.first['id'];

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '');
  }

  Future<bool> existeOrdemParaAgendamento(int agendamentoId) async {
    final ordemId = await buscarIdOrdemPorAgendamento(agendamentoId);

    return ordemId != null;
  }

  Future<void> atualizarOrdemServico(
    OrdemServico ordemServico, {
    List<OrdemServicoItem>? itens,
  }) async {
    final id = ordemServico.id;

    if (id == null) {
      throw ArgumentError(
        'Não é possível atualizar uma Ordem de Serviço sem ID.',
      );
    }

    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final dadosOrdem = ordemServico.toMap();
      dadosOrdem.remove('id');

      await transaction.update(
        'ordens_servico',
        dadosOrdem,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (itens != null) {
        await transaction.delete(
          'ordem_servico_itens',
          where: 'ordem_servico_id = ?',
          whereArgs: [id],
        );

        for (var indice = 0; indice < itens.length; indice++) {
          final item = itens[indice];

          final dadosItem = item
              .copyWith(ordemServicoId: id, ordem: indice)
              .toMap();

          dadosItem.remove('id');

          await transaction.insert('ordem_servico_itens', dadosItem);
        }
      }
    });
  }

  Future<List<OrdemServico>> listarOrdensServico({
    String? status,
    String? pesquisa,
  }) async {
    final database = await _appDatabase.database;

    final filtros = <String>[];
    final argumentos = <Object?>[];

    final statusLimpo = status?.trim() ?? '';

    if (statusLimpo.isNotEmpty && statusLimpo.toLowerCase() != 'todos') {
      filtros.add('os.status = ?');
      argumentos.add(statusLimpo);
    }

    final pesquisaLimpa = pesquisa?.trim() ?? '';

    if (pesquisaLimpa.isNotEmpty) {
      filtros.add('''
        (
          os.numero LIKE ?
          OR clientes.nome LIKE ?
          OR veiculos.marca LIKE ?
          OR veiculos.modelo LIKE ?
          OR veiculos.placa LIKE ?
          OR os.funcionario_responsavel LIKE ?
        )
      ''');

      final termo = '%$pesquisaLimpa%';

      argumentos.addAll([termo, termo, termo, termo, termo, termo]);
    }

    final resultado = await database.rawQuery('''
      SELECT
        os.*,
        clientes.nome AS cliente_nome,
        clientes.telefone AS cliente_telefone,
        veiculos.marca AS veiculo_marca,
        veiculos.modelo AS veiculo_modelo,
        veiculos.placa AS veiculo_placa,
        veiculos.cor AS veiculo_cor,
        veiculos.ano AS veiculo_ano
      FROM ordens_servico os
      INNER JOIN clientes
        ON clientes.id = os.cliente_id
      LEFT JOIN veiculos
        ON veiculos.id = os.veiculo_id
      ${filtros.isEmpty ? '' : 'WHERE ${filtros.join(' AND ')}'}
      ORDER BY
        os.data_abertura DESC,
        os.id DESC
      ''', argumentos);

    return resultado
        .map((mapa) => OrdemServico.fromMap(Map<String, dynamic>.from(mapa)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listarOrdensServicoComDetalhes({
    String? status,
    String? pesquisa,
  }) async {
    final database = await _appDatabase.database;

    final filtros = <String>[];
    final argumentos = <Object?>[];

    final statusLimpo = status?.trim() ?? '';

    if (statusLimpo.isNotEmpty && statusLimpo.toLowerCase() != 'todos') {
      filtros.add('os.status = ?');
      argumentos.add(statusLimpo);
    }

    final pesquisaLimpa = pesquisa?.trim() ?? '';

    if (pesquisaLimpa.isNotEmpty) {
      filtros.add('''
        (
          os.numero LIKE ?
          OR clientes.nome LIKE ?
          OR clientes.telefone LIKE ?
          OR veiculos.marca LIKE ?
          OR veiculos.modelo LIKE ?
          OR veiculos.placa LIKE ?
          OR os.funcionario_responsavel LIKE ?
        )
      ''');

      final termo = '%$pesquisaLimpa%';

      argumentos.addAll([termo, termo, termo, termo, termo, termo, termo]);
    }

    final resultado = await database.rawQuery('''
      SELECT
        os.*,
        clientes.nome AS cliente_nome,
        clientes.telefone AS cliente_telefone,
        clientes.email AS cliente_email,
        veiculos.marca AS veiculo_marca,
        veiculos.modelo AS veiculo_modelo,
        veiculos.placa AS veiculo_placa,
        veiculos.cor AS veiculo_cor,
        veiculos.ano AS veiculo_ano,
        (
          SELECT COUNT(*)
          FROM ordem_servico_itens itens
          WHERE itens.ordem_servico_id = os.id
        ) AS quantidade_itens,
        (
          SELECT COUNT(*)
          FROM ordem_servico_itens itens
          WHERE itens.ordem_servico_id = os.id
            AND itens.concluido = 1
        ) AS itens_concluidos
      FROM ordens_servico os
      INNER JOIN clientes
        ON clientes.id = os.cliente_id
      LEFT JOIN veiculos
        ON veiculos.id = os.veiculo_id
      ${filtros.isEmpty ? '' : 'WHERE ${filtros.join(' AND ')}'}
      ORDER BY
        CASE os.status
          WHEN 'Em andamento' THEN 1
          WHEN 'Aberta' THEN 2
          WHEN 'Finalizada' THEN 3
          WHEN 'Cancelada' THEN 4
          ELSE 5
        END,
        os.data_abertura DESC,
        os.id DESC
      ''', argumentos);

    return resultado.map((mapa) => Map<String, dynamic>.from(mapa)).toList();
  }

  Future<OrdemServico?> buscarOrdemServicoPorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordens_servico',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return OrdemServico.fromMap(Map<String, dynamic>.from(resultado.first));
  }

  Future<Map<String, dynamic>?> buscarOrdemServicoCompletaPorId(int id) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        os.*,
        clientes.nome AS cliente_nome,
        clientes.telefone AS cliente_telefone,
        clientes.email AS cliente_email,
        clientes.endereco AS cliente_endereco,
        veiculos.marca AS veiculo_marca,
        veiculos.modelo AS veiculo_modelo,
        veiculos.placa AS veiculo_placa,
        veiculos.cor AS veiculo_cor,
        veiculos.ano AS veiculo_ano
      FROM ordens_servico os
      INNER JOIN clientes
        ON clientes.id = os.cliente_id
      LEFT JOIN veiculos
        ON veiculos.id = os.veiculo_id
      WHERE os.id = ?
      LIMIT 1
      ''',
      [id],
    );

    if (resultado.isEmpty) {
      return null;
    }

    final ordem = Map<String, dynamic>.from(resultado.first);

    final itens = await listarItens(id);

    ordem['itens'] = itens.map((item) => item.toMap()).toList();

    return ordem;
  }

  Future<List<OrdemServicoItem>> listarItens(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_itens',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: 'ordem ASC, id ASC',
    );

    return resultado
        .map(
          (mapa) => OrdemServicoItem.fromMap(Map<String, dynamic>.from(mapa)),
        )
        .toList();
  }

  /// Adiciona um serviço do catálogo a uma OS ainda editável.
  ///
  /// A operação é transacional:
  /// - valida que a OS está Aberta ou Em andamento;
  /// - adiciona o item da OS;
  /// - inclui os produtos obrigatórios/marcados por padrão do serviço;
  /// - valida o estoque previsto da própria OS;
  /// - recalcula o subtotal da OS.
  ///
  /// Nenhum estoque é baixado aqui. A baixa FIFO continua acontecendo
  /// somente na finalização da Ordem de Serviço.
  Future<Map<String, dynamic>> adicionarServicoCatalogoNaOrdem({
    required int ordemServicoId,
    required int servicoCatalogoId,
    required double quantidade,
    double? valorUnitario,
    String? descricao,
  }) async {
    if (ordemServicoId <= 0) {
      throw ArgumentError('Ordem de Serviço inválida.');
    }

    if (servicoCatalogoId <= 0) {
      throw ArgumentError('Serviço do catálogo inválido.');
    }

    if (quantidade <= 0) {
      throw ArgumentError('A quantidade do serviço deve ser maior que zero.');
    }

    if (valorUnitario != null && valorUnitario < 0) {
      throw ArgumentError('O valor do serviço não pode ser negativo.');
    }

    final database = await _appDatabase.database;

    return database.transaction<Map<String, dynamic>>((transaction) async {
      final ordemResultado = await transaction.query(
        'ordens_servico',
        columns: ['id', 'numero', 'status'],
        where: 'id = ?',
        whereArgs: [ordemServicoId],
        limit: 1,
      );

      if (ordemResultado.isEmpty) {
        throw StateError('Ordem de Serviço não encontrada.');
      }

      final ordem = ordemResultado.first;
      final status = (ordem['status'] ?? '').toString().trim();

      if (status != 'Aberta' && status != 'Em andamento') {
        throw StateError(
          'Só é possível adicionar serviços em uma OS Aberta ou Em andamento.',
        );
      }

      final servicoResultado = await transaction.query(
        'servicos_catalogo',
        columns: ['id', 'nome', 'descricao', 'preco_padrao', 'ativo'],
        where: 'id = ?',
        whereArgs: [servicoCatalogoId],
        limit: 1,
      );

      if (servicoResultado.isEmpty) {
        throw StateError('Serviço não encontrado no catálogo.');
      }

      final servico = servicoResultado.first;
      final ativo = _converterInt(servico['ativo']) ?? 0;

      if (ativo != 1) {
        throw StateError(
          'O serviço selecionado está inativo e não pode ser adicionado.',
        );
      }

      final nomeServico = (servico['nome'] ?? '').toString().trim();
      if (nomeServico.isEmpty) {
        throw StateError('O serviço selecionado não possui nome.');
      }

      final precoCatalogo =
          (servico['preco_padrao'] as num?)?.toDouble() ?? 0.0;
      final precoUsado = valorUnitario ?? precoCatalogo;

      if (precoUsado < 0) {
        throw ArgumentError('O valor do serviço não pode ser negativo.');
      }

      final descricaoCatalogo = (servico['descricao'] ?? '').toString().trim();
      final descricaoUsada = descricao == null
          ? descricaoCatalogo
          : descricao.trim();

      final ordemItemResultado = await transaction.rawQuery(
        '''
        SELECT COALESCE(MAX(ordem), -1) AS ultima_ordem
        FROM ordem_servico_itens
        WHERE ordem_servico_id = ?
        ''',
        [ordemServicoId],
      );
      final ultimaOrdem =
          _converterInt(ordemItemResultado.first['ultima_ordem']) ?? -1;

      final produtosCatalogo = await transaction.rawQuery(
        '''
        SELECT
          sp.item_estoque_id,
          sp.quantidade_padrao,
          sp.unidade AS unidade_configurada,
          sp.obrigatorio,
          sp.marcado_por_padrao,
          ie.nome AS produto_nome,
          ie.unidade AS unidade_estoque,
          ie.quantidade AS estoque_atual,
          ie.custo_unitario,
          ie.custo_unitario_calculado,
          ie.ativo AS produto_ativo
        FROM servico_produtos sp
        INNER JOIN itens_estoque ie
          ON ie.id = sp.item_estoque_id
        WHERE sp.servico_id = ?
          AND (sp.obrigatorio = 1 OR sp.marcado_por_padrao = 1)
        ORDER BY sp.ordem ASC, sp.id ASC
        ''',
        [servicoCatalogoId],
      );

      final produtosPreparados = <Map<String, dynamic>>[];

      for (final produto in produtosCatalogo) {
        final produtoId = _converterInt(produto['item_estoque_id']);
        final quantidadePadrao =
            (produto['quantidade_padrao'] as num?)?.toDouble() ?? 0.0;
        final quantidadeProduto = quantidadePadrao * quantidade;

        if (produtoId == null || quantidadeProduto <= 0) {
          continue;
        }

        final produtoAtivo = _converterInt(produto['produto_ativo']) ?? 0;
        final produtoNome = (produto['produto_nome'] ?? 'Produto')
            .toString()
            .trim();

        if (produtoAtivo != 1) {
          throw StateError(
            'O produto "$produtoNome", vinculado a este serviço, está inativo.',
          );
        }

        final estoqueAtual =
            (produto['estoque_atual'] as num?)?.toDouble() ?? 0.0;

        final previstoResultado = await transaction.rawQuery(
          '''
          SELECT COALESCE(SUM(quantidade), 0) AS quantidade
          FROM ordem_servico_produtos
          WHERE ordem_servico_id = ?
            AND produto_id = ?
            AND baixado_estoque = 0
          ''',
          [ordemServicoId, produtoId],
        );

        final jaPrevisto =
            (previstoResultado.first['quantidade'] as num?)?.toDouble() ?? 0.0;
        final totalPrevisto = jaPrevisto + quantidadeProduto;

        if (totalPrevisto - estoqueAtual > 0.000001) {
          throw StateError(
            'Estoque insuficiente para adicionar este serviço. '
            '"$produtoNome": disponível '
            '${_formatarQuantidadeMensagem(estoqueAtual)}, '
            'necessário na OS '
            '${_formatarQuantidadeMensagem(totalPrevisto)}.',
          );
        }

        final custoCalculado =
            (produto['custo_unitario_calculado'] as num?)?.toDouble() ?? 0.0;
        final custoCadastrado =
            (produto['custo_unitario'] as num?)?.toDouble() ?? 0.0;
        final custoUnitario = custoCalculado > 0
            ? custoCalculado
            : custoCadastrado;

        final unidade = (produto['unidade_estoque'] ?? '').toString().trim();

        produtosPreparados.add({
          'produto_id': produtoId,
          'produto_nome': produtoNome,
          'quantidade': quantidadeProduto,
          'unidade': unidade,
          'custo_unitario': custoUnitario,
        });
      }

      final dadosItem = OrdemServicoItem(
        ordemServicoId: ordemServicoId,
        servico: nomeServico,
        descricao: descricaoUsada,
        quantidade: quantidade,
        valorUnitario: precoUsado,
        ordem: ultimaOrdem + 1,
        concluido: false,
      ).toMap();
      dadosItem.remove('id');

      final itemId = await transaction.insert(
        'ordem_servico_itens',
        dadosItem,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (final produto in produtosPreparados) {
        final custoUnitario =
            (produto['custo_unitario'] as num?)?.toDouble() ?? 0.0;
        final quantidadeProduto =
            (produto['quantidade'] as num?)?.toDouble() ?? 0.0;

        await transaction.insert('ordem_servico_produtos', {
          'ordem_servico_id': ordemServicoId,
          'produto_id': produto['produto_id'],
          'produto_nome': produto['produto_nome'],
          'quantidade': quantidadeProduto,
          'unidade': produto['unidade'],
          'custo_unitario': custoUnitario,
          'custo_unitario_no_momento': custoUnitario,
          'custo_total_no_momento': quantidadeProduto * custoUnitario,
          'composicao_lotes_json': '',
          'baixado_estoque': 0,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      final subtotalResultado = await transaction.rawQuery(
        '''
        SELECT COALESCE(SUM(quantidade * valor_unitario), 0) AS subtotal
        FROM ordem_servico_itens
        WHERE ordem_servico_id = ?
        ''',
        [ordemServicoId],
      );

      final novoSubtotal =
          (subtotalResultado.first['subtotal'] as num?)?.toDouble() ?? 0.0;

      await transaction.update(
        'ordens_servico',
        {'valor_total': novoSubtotal},
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      return {
        'item_id': itemId,
        'servico': nomeServico,
        'quantidade': quantidade,
        'valor_unitario': precoUsado,
        'subtotal_item': quantidade * precoUsado,
        'novo_subtotal_os': novoSubtotal,
        'produtos_adicionados': produtosPreparados.length,
      };
    });
  }

  Future<int> inserirItem(OrdemServicoItem item) async {
    final database = await _appDatabase.database;

    final dados = item.toMap();
    dados.remove('id');

    return database.insert('ordem_servico_itens', dados);
  }

  Future<void> atualizarItem(OrdemServicoItem item) async {
    final id = item.id;

    if (id == null) {
      throw ArgumentError('Não é possível atualizar um item sem ID.');
    }

    final database = await _appDatabase.database;

    final dados = item.toMap();
    dados.remove('id');

    await database.update(
      'ordem_servico_itens',
      dados,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarItemConcluido({
    required int itemId,
    required bool concluido,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      'ordem_servico_itens',
      {'concluido': concluido ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> excluirItem(int itemId) async {
    final database = await _appDatabase.database;

    await database.delete(
      'ordem_servico_itens',
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> alterarStatus({
    required int ordemServicoId,
    required String status,
    String? dataInicio,
    String? dataFinalizacao,
    String? horaEntrada,
    String? horaSaida,
  }) async {
    final database = await _appDatabase.database;

    final dados = <String, dynamic>{'status': status};

    if (dataInicio != null) {
      dados['data_inicio'] = dataInicio;
    }

    if (dataFinalizacao != null) {
      dados['data_finalizacao'] = dataFinalizacao;
    }

    if (horaEntrada != null) {
      dados['hora_entrada'] = horaEntrada;
    }

    if (horaSaida != null) {
      dados['hora_saida'] = horaSaida;
    }

    await database.update(
      'ordens_servico',
      dados,
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );
  }

  Future<void> iniciarOrdemServico(
    int ordemServicoId, {
    DateTime? dataHoraEntrada,
  }) async {
    final agora = DateTime.now();
    final entradaEfetiva = dataHoraEntrada ?? agora;
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordens_servico',
        columns: ['id', 'status', 'agendamento_id'],
        where: 'id = ?',
        whereArgs: [ordemServicoId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Ordem de Serviço não encontrada.');
      }

      final ordem = resultado.first;
      final statusAtual = (ordem['status'] ?? '').toString().trim();

      if (statusAtual == 'Em andamento') {
        return;
      }

      if (statusAtual == 'Finalizada') {
        throw StateError(
          'Uma Ordem de Serviço finalizada não pode ser iniciada.',
        );
      }

      await transaction.update(
        'ordens_servico',
        {
          'status': 'Em andamento',
          'data_inicio': _formatarData(entradaEfetiva),
          'hora_entrada': _formatarHora(entradaEfetiva),
        },
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      final agendamentoId = _converterInt(ordem['agendamento_id']);

      if (agendamentoId != null) {
        await _agendamentoRepository.atualizarStatusComTransacao(
          transaction,
          agendamentoId,
          'Em andamento',
        );
      }
    });
  }

  Future<void> finalizarOrdemServico({
    required int ordemServicoId,
    String? formaPagamento,
    double? valorPagamento,
    String? vencimentoPagamento,
    int? contaFinanceiraId,
    int parcelasTaxa = 1,
    DateTime? dataHoraEntrada,
    DateTime? dataHoraSaida,
    DateTime? dataHoraPagamento,
  }) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now();
    final formaPagamentoLimpa = formaPagamento?.trim() ?? '';
    final vencimentoPagamentoLimpo = vencimentoPagamento?.trim() ?? '';

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordens_servico',
        columns: [
          'id',
          'numero',
          'status',
          'cliente_id',
          'valor_total',
          'desconto',
          'desconto_negociacao',
          'acrescimo_negociacao',
          'juros_parcelamento',
          'lancado_financeiro',
          'agendamento_id',
          'data_inicio',
          'hora_entrada',
          'funcionario_responsavel',
        ],
        where: 'id = ?',
        whereArgs: [ordemServicoId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Ordem de Serviço não encontrada.');
      }

      final ordem = resultado.first;

      final statusAtual = (ordem['status'] ?? '').toString().trim();

      if (statusAtual == 'Finalizada') {
        return;
      }

      if (statusAtual == 'Aberta') {
        throw StateError(
          'A Ordem de Serviço precisa estar "Em andamento" para finalizar.',
        );
      }

      if (statusAtual == 'Cancelada') {
        throw StateError(
          'Uma Ordem de Serviço cancelada não pode ser finalizada.',
        );
      }

      final entradaRegistrada = _combinarDataHoraArmazenada(
        ordem['data_inicio'],
        ordem['hora_entrada'],
      );
      final entradaEfetiva = dataHoraEntrada ?? entradaRegistrada ?? agora;
      final saidaEfetiva = dataHoraSaida ?? agora;

      if (saidaEfetiva.isBefore(entradaEfetiva)) {
        throw ArgumentError(
          'A data/hora de saída não pode ser anterior à data/hora de entrada.',
        );
      }

      final pagamentoEfetivo = dataHoraPagamento ?? saidaEfetiva;

      final valorTotal = (ordem['valor_total'] as num?)?.toDouble() ?? 0;

      final desconto = (ordem['desconto'] as num?)?.toDouble() ?? 0;
      final descontoNegociacao =
          (ordem['desconto_negociacao'] as num?)?.toDouble() ?? 0;
      final acrescimoNegociacao =
          (ordem['acrescimo_negociacao'] as num?)?.toDouble() ?? 0;
      final jurosParcelamento =
          (ordem['juros_parcelamento'] as num?)?.toDouble() ?? 0;

      // Deve ser a mesma fórmula exibida na tela, usada pelos pagamentos
      // e pelo DRE. Antes a finalização considerava apenas valor_total -
      // desconto e podia divergir após negociação/acréscimos/juros.
      final valorFinal =
          (valorTotal -
                  desconto -
                  descontoNegociacao +
                  acrescimoNegociacao +
                  jurosParcelamento)
              .clamp(0, double.infinity)
              .toDouble();

      final pagamentoSolicitado =
          valorPagamento ?? (formaPagamentoLimpa.isNotEmpty ? valorFinal : 0.0);

      if (pagamentoSolicitado < 0 ||
          pagamentoSolicitado - valorFinal > 0.000001) {
        throw ArgumentError(
          'O valor recebido na finalização é inválido para esta OS.',
        );
      }

      if (pagamentoSolicitado > 0.000001 && formaPagamentoLimpa.isEmpty) {
        throw ArgumentError(
          'Informe a forma de pagamento para registrar o recebimento.',
        );
      }

      final numero = (ordem['numero'] ?? ordemServicoId).toString().trim();

      final produtosPendentes = await transaction.query(
        'ordem_servico_produtos',
        where: 'ordem_servico_id = ? AND baixado_estoque = 0',
        whereArgs: [ordemServicoId],
        orderBy: 'id ASC',
      );
      final consumoPorProduto = <int, double>{};
      final nomesPorProduto = <int, String>{};

      for (final produtoOs in produtosPendentes) {
        final produtoId = (produtoOs['produto_id'] as num?)?.toInt();
        final quantidadeUtilizada =
            (produtoOs['quantidade'] as num?)?.toDouble() ?? 0;

        if (produtoId == null || quantidadeUtilizada <= 0) {
          continue;
        }

        consumoPorProduto[produtoId] =
            (consumoPorProduto[produtoId] ?? 0) + quantidadeUtilizada;
        nomesPorProduto[produtoId] = (produtoOs['produto_nome'] ?? 'Produto')
            .toString()
            .trim();
      }

      final estoquePorProduto = <int, Map<String, dynamic>>{};
      final lotesPorProduto = <int, List<Map<String, dynamic>>>{};

      if (consumoPorProduto.isNotEmpty) {
        final ids = consumoPorProduto.keys.toList();
        final placeholders = List.filled(ids.length, '?').join(', ');

        final itensEstoque = await transaction.rawQuery('''
          SELECT id, nome, quantidade, custo_unitario, custo_unitario_calculado
          FROM itens_estoque
          WHERE id IN ($placeholders)
          ''', ids);

        for (final linha in itensEstoque) {
          final id = (linha['id'] as num?)?.toInt();
          if (id != null) {
            estoquePorProduto[id] = Map<String, dynamic>.from(linha);
          }
        }

        final lotes = await transaction.rawQuery('''
          SELECT
            id,
            item_estoque_id,
            data_compra,
            quantidade_disponivel,
            custo_unitario
          FROM estoque_lotes
          WHERE item_estoque_id IN ($placeholders)
            AND ativo = 1
            AND quantidade_disponivel > 0
          ORDER BY data_compra ASC, id ASC
          ''', ids);

        for (final lote in lotes) {
          final itemId = (lote['item_estoque_id'] as num?)?.toInt();
          if (itemId == null) {
            continue;
          }

          lotesPorProduto.putIfAbsent(itemId, () => <Map<String, dynamic>>[]);
          lotesPorProduto[itemId]!.add(Map<String, dynamic>.from(lote));
        }
      }

      final planoFilaPorProduto = <int, List<Map<String, dynamic>>>{};

      // Valida todo o estoque antes de qualquer baixa.
      for (final entry in consumoPorProduto.entries) {
        final produtoId = entry.key;
        final quantidadeNecessaria = entry.value;
        final itemEstoque = estoquePorProduto[produtoId];
        final produtoNome = nomesPorProduto[produtoId] ?? 'Produto';

        if (itemEstoque == null) {
          throw StateError(
            'O produto "$produtoNome" não foi encontrado no estoque.',
          );
        }

        final lotes = lotesPorProduto[produtoId] ?? <Map<String, dynamic>>[];
        final disponivel = lotes.fold<double>(
          0,
          (total, lote) =>
              total +
              ((lote['quantidade_disponivel'] as num?)?.toDouble() ?? 0),
        );

        if (disponivel + 0.000001 < quantidadeNecessaria) {
          throw StateError(
            'Estoque insuficiente para "$produtoNome". '
            'Disponível: ${_formatarQuantidadeMensagem(disponivel)}. '
            'Necessário: ${_formatarQuantidadeMensagem(quantidadeNecessaria)}.',
          );
        }

        final fila = <Map<String, dynamic>>[];
        var restante = quantidadeNecessaria;

        for (final lote in lotes) {
          if (restante <= 0) {
            break;
          }

          final loteId = (lote['id'] as num?)?.toInt();
          final saldo =
              (lote['quantidade_disponivel'] as num?)?.toDouble() ?? 0;
          final custoUnitario =
              (lote['custo_unitario'] as num?)?.toDouble() ?? 0;

          if (loteId == null || saldo <= 0) {
            continue;
          }

          final usar = restante < saldo ? restante : saldo;

          fila.add({
            'lote_id': loteId,
            'quantidade': usar,
            'custo_unitario': custoUnitario,
          });

          restante -= usar;
        }

        if (restante > 0.000001) {
          throw StateError(
            'Não foi possível planejar a baixa FIFO para "$produtoNome".',
          );
        }

        planoFilaPorProduto[produtoId] = fila;
      }

      final saldoAtualPorProduto = <int, double>{
        for (final entry in estoquePorProduto.entries)
          entry.key: (entry.value['quantidade'] as num?)?.toDouble() ?? 0,
      };

      for (final produtoOs in produtosPendentes) {
        final produtoOsId = (produtoOs['id'] as num?)?.toInt();
        final produtoId = (produtoOs['produto_id'] as num?)?.toInt();
        final quantidadeUtilizada =
            (produtoOs['quantidade'] as num?)?.toDouble() ?? 0;

        if (produtoOsId == null) {
          continue;
        }

        if (produtoId == null || quantidadeUtilizada <= 0) {
          await transaction.update(
            'ordem_servico_produtos',
            {'baixado_estoque': 1},
            where: 'id = ?',
            whereArgs: [produtoOsId],
          );
          continue;
        }

        final fila = planoFilaPorProduto[produtoId] ?? <Map<String, dynamic>>[];
        var restanteProdutoOs = quantidadeUtilizada;
        final composicao = <Map<String, dynamic>>[];
        var custoTotalProdutoOs = 0.0;

        while (restanteProdutoOs > 0.000001) {
          if (fila.isEmpty) {
            final nomeProduto = (produtoOs['produto_nome'] ?? 'Produto')
                .toString();
            throw StateError('Falha na baixa FIFO para "$nomeProduto".');
          }

          final atual = fila.first;
          final disponivelNaFila =
              (atual['quantidade'] as num?)?.toDouble() ?? 0;
          final custoUnitario =
              (atual['custo_unitario'] as num?)?.toDouble() ?? 0;
          final loteId = (atual['lote_id'] as num?)?.toInt() ?? 0;

          if (disponivelNaFila <= 0) {
            fila.removeAt(0);
            continue;
          }

          final consumo = restanteProdutoOs < disponivelNaFila
              ? restanteProdutoOs
              : disponivelNaFila;

          final novoSaldoFila = disponivelNaFila - consumo;
          atual['quantidade'] = novoSaldoFila;

          if (novoSaldoFila <= 0.000001) {
            fila.removeAt(0);
          }

          restanteProdutoOs -= consumo;
          final custoTotalConsumo = consumo * custoUnitario;
          custoTotalProdutoOs += custoTotalConsumo;

          composicao.add({
            'lote_id': loteId,
            'quantidade': consumo,
            'custo_unitario': custoUnitario,
            'custo_total': custoTotalConsumo,
          });
        }

        final custoUnitarioSnapshot = quantidadeUtilizada > 0
            ? (custoTotalProdutoOs / quantidadeUtilizada)
            : 0.0;

        await transaction.update(
          'ordem_servico_produtos',
          {
            'custo_unitario_no_momento': custoUnitarioSnapshot,
            'custo_total_no_momento': custoTotalProdutoOs,
            'composicao_lotes_json': jsonEncode(composicao),
            'baixado_estoque': 1,
          },
          where: 'id = ?',
          whereArgs: [produtoOsId],
        );

        for (final componente in composicao) {
          final loteId = (componente['lote_id'] as num?)?.toInt() ?? 0;
          final consumo = (componente['quantidade'] as num?)?.toDouble() ?? 0;
          final custoUnitario =
              (componente['custo_unitario'] as num?)?.toDouble() ?? 0;
          final custoTotal =
              (componente['custo_total'] as num?)?.toDouble() ?? 0;

          final loteAtual = await transaction.query(
            'estoque_lotes',
            columns: ['quantidade_disponivel'],
            where: 'id = ?',
            whereArgs: [loteId],
            limit: 1,
          );

          if (loteAtual.isEmpty) {
            throw StateError('Lote de estoque não encontrado para baixa FIFO.');
          }

          final saldoLoteAnterior =
              (loteAtual.first['quantidade_disponivel'] as num?)?.toDouble() ??
              0;
          final saldoLotePosterior = saldoLoteAnterior - consumo;

          if (saldoLotePosterior < -0.000001) {
            throw StateError('Tentativa de saldo negativo em lote de estoque.');
          }

          await transaction.update(
            'estoque_lotes',
            {
              'quantidade_disponivel': saldoLotePosterior < 0
                  ? 0
                  : saldoLotePosterior,
            },
            where: 'id = ?',
            whereArgs: [loteId],
          );

          await transaction.insert(
            'ordem_servico_produto_lotes',
            {
              'ordem_servico_produto_id': produtoOsId,
              'lote_id': loteId,
              'quantidade': consumo,
              'custo_unitario': custoUnitario,
              'custo_total': custoTotal,
              'criado_em': agora.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );

          final saldoItemAnterior = saldoAtualPorProduto[produtoId] ?? 0;
          final saldoItemPosterior = saldoItemAnterior - consumo;

          if (saldoItemPosterior < -0.000001) {
            throw StateError(
              'Tentativa de saldo negativo no estoque do produto.',
            );
          }

          await transaction.insert('movimentacoes_estoque', {
            'item_estoque_id': produtoId,
            'tipo': 'SAIDA',
            'quantidade': consumo,
            'quantidade_anterior': saldoItemAnterior,
            'quantidade_posterior': saldoItemPosterior,
            'custo_unitario': custoUnitario,
            'observacoes': 'Baixa automática FIFO da Ordem de Serviço $numero',
            'origem': 'Ordem de Serviço',
            'ordem_servico_id': ordemServicoId,
            'lote_id': loteId,
            'data': saidaEfetiva.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.abort);

          saldoAtualPorProduto[produtoId] = saldoItemPosterior;
        }
      }

      for (final entry in saldoAtualPorProduto.entries) {
        await transaction.update(
          'itens_estoque',
          {
            'quantidade': entry.value < 0 ? 0 : entry.value,
            'atualizado_em': agora.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }

      final dados = <String, dynamic>{
        'status': 'Finalizada',
        'data_inicio': _formatarData(entradaEfetiva),
        'hora_entrada': _formatarHora(entradaEfetiva),
        'data_finalizacao': _formatarData(saidaEfetiva),
        'hora_saida': _formatarHora(saidaEfetiva),
        'lancado_financeiro': 0,
        'status_pagamento': valorFinal <= 0.000001 ? 'Pago' : 'Pendente',
        'valor_recebido': 0,
        'vencimento_pagamento': vencimentoPagamentoLimpo.isEmpty
            ? null
            : vencimentoPagamentoLimpo,
        'pagamento_atualizado_em': agora.toIso8601String(),
        'forma_pagamento': formaPagamentoLimpa.isEmpty
            ? null
            : formaPagamentoLimpa,
      };

      await transaction.update(
        'ordens_servico',
        dados,
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      // O responsável foi selecionado no cadastro da OS. Ao finalizar,
      // transforma o tempo real de entrada/saída em custo de mão de obra,
      // usando o custo/hora atual como snapshot histórico da OS.
      await _custosRepository.registrarMaoObraAutomaticaComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        colaboradorNome: (ordem['funcionario_responsavel'] ?? '').toString(),
        entrada: entradaEfetiva,
        saida: saidaEfetiva,
      );

      final agendamentoId = _converterInt(ordem['agendamento_id']);

      if (agendamentoId != null) {
        await _agendamentoRepository.atualizarStatusComTransacao(
          transaction,
          agendamentoId,
          'Finalizado',
        );
      }

      if (pagamentoSolicitado > 0.000001) {
        await _pagamentoRepository.registrarPagamentoComTransacao(
          transaction,
          ordemServicoId: ordemServicoId,
          valor: pagamentoSolicitado,
          formaPagamento: formaPagamentoLimpa,
          dataPagamento: pagamentoEfetivo,
          contaFinanceiraId: contaFinanceiraId,
          parcelasTaxa: parcelasTaxa.clamp(1, 12).toInt(),
        );
      }
    });
  }

  Future<int> corrigirOrdemFinalizada({
    required int ordemServicoId,
    required String motivo,
    required String funcionarioResponsavel,
    required String observacoes,
    required String quilometragemEntrada,
    required String combustivelEntrada,
    String? dataInicio,
    String? dataFinalizacao,
    String? horaEntrada,
    String? horaSaida,
  }) async {
    final motivoLimpo = motivo.trim();

    if (motivoLimpo.length < 5) {
      throw ArgumentError(
        'Informe um motivo de correção com pelo menos 5 caracteres.',
      );
    }

    final database = await _appDatabase.database;
    final agora = DateTime.now();

    return database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordens_servico',
        columns: [
          'id',
          'status',
          'funcionario_responsavel',
          'observacoes',
          'quilometragem_entrada',
          'combustivel_entrada',
          'data_inicio',
          'data_finalizacao',
          'hora_entrada',
          'hora_saida',
          'assinatura_cliente',
          'quantidade_revisoes',
          'assinatura_desatualizada',
        ],
        where: 'id = ?',
        whereArgs: [ordemServicoId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Ordem de Serviço não encontrada.');
      }

      final ordemAtual = resultado.first;
      final statusAtual = (ordemAtual['status'] ?? '').toString().trim();

      if (statusAtual != 'Finalizada') {
        throw StateError(
          'Somente Ordens de Serviço finalizadas podem ser corrigidas '
          'por este fluxo.',
        );
      }

      String texto(dynamic valor) {
        return (valor ?? '').toString().trim();
      }

      String? horario(dynamic valor) {
        final textoLimpo = texto(valor);
        return textoLimpo.isEmpty ? null : textoLimpo;
      }

      final dataInicioAtual = texto(ordemAtual['data_inicio']);
      final dataFinalizacaoAtual = texto(ordemAtual['data_finalizacao']);
      final dataInicioNova = dataInicio == null
          ? (dataInicioAtual.isEmpty ? null : dataInicioAtual)
          : _normalizarDataBanco(dataInicio, campo: 'data de entrada');
      final dataFinalizacaoNova = dataFinalizacao == null
          ? (dataFinalizacaoAtual.isEmpty ? null : dataFinalizacaoAtual)
          : _normalizarDataBanco(dataFinalizacao, campo: 'data de saída');
      final horaEntradaNova = horaEntrada == null
          ? horario(ordemAtual['hora_entrada'])
          : horario(horaEntrada);
      final horaSaidaNova = horaSaida == null
          ? horario(ordemAtual['hora_saida'])
          : horario(horaSaida);

      _validarPeriodoOperacional(
        dataInicio: dataInicioNova,
        horaEntrada: horaEntradaNova,
        dataFinalizacao: dataFinalizacaoNova,
        horaSaida: horaSaidaNova,
      );

      final dadosAnteriores = <String, dynamic>{
        'funcionario_responsavel': texto(ordemAtual['funcionario_responsavel']),
        'observacoes': texto(ordemAtual['observacoes']),
        'quilometragem_entrada': texto(ordemAtual['quilometragem_entrada']),
        'combustivel_entrada': texto(ordemAtual['combustivel_entrada']),
        'data_inicio': dataInicioAtual.isEmpty ? null : dataInicioAtual,
        'data_finalizacao': dataFinalizacaoAtual.isEmpty
            ? null
            : dataFinalizacaoAtual,
        'hora_entrada': horario(ordemAtual['hora_entrada']),
        'hora_saida': horario(ordemAtual['hora_saida']),
      };

      final dadosNovos = <String, dynamic>{
        'funcionario_responsavel': funcionarioResponsavel.trim(),
        'observacoes': observacoes.trim(),
        'quilometragem_entrada': quilometragemEntrada.trim(),
        'combustivel_entrada': combustivelEntrada.trim(),
        'data_inicio': dataInicioNova,
        'data_finalizacao': dataFinalizacaoNova,
        'hora_entrada': horaEntradaNova,
        'hora_saida': horaSaidaNova,
      };

      final houveAlteracao = dadosAnteriores.entries.any(
        (entrada) => entrada.value != dadosNovos[entrada.key],
      );

      if (!houveAlteracao) {
        throw StateError(
          'Nenhuma alteração foi identificada na Ordem de Serviço.',
        );
      }

      final quantidadeAtual =
          (ordemAtual['quantidade_revisoes'] as num?)?.toInt() ?? 0;
      final numeroRevisao = quantidadeAtual + 1;

      final possuiAssinatura = texto(
        ordemAtual['assinatura_cliente'],
      ).isNotEmpty;
      final assinaturaJaDesatualizada =
          (ordemAtual['assinatura_desatualizada'] as num?)?.toInt() == 1;

      final assinaturaDesatualizada =
          possuiAssinatura || assinaturaJaDesatualizada;

      await transaction.update(
        'ordens_servico',
        {
          ...dadosNovos,
          'revisada_em': agora.toIso8601String(),
          'motivo_ultima_revisao': motivoLimpo,
          'quantidade_revisoes': numeroRevisao,
          'assinatura_desatualizada': assinaturaDesatualizada ? 1 : 0,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [ordemServicoId, 'Finalizada'],
      );

      final entradaCorrigida = _combinarDataHoraArmazenada(
        dataInicioNova,
        horaEntradaNova,
      );
      final saidaCorrigida = _combinarDataHoraArmazenada(
        dataFinalizacaoNova,
        horaSaidaNova,
      );

      if (entradaCorrigida != null && saidaCorrigida != null) {
        await _custosRepository.recalcularMaoObraAutomaticaComTransacao(
          transaction,
          ordemServicoId: ordemServicoId,
          colaboradorNome: funcionarioResponsavel.trim(),
          entrada: entradaCorrigida,
          saida: saidaCorrigida,
        );

        // A baixa FIFO aconteceu na saída real do veículo. Se a data/hora
        // operacional for corrigida depois, mantém o histórico de estoque
        // coerente com o novo período da OS. Quantidades e custos não mudam.
        await transaction.update(
          'movimentacoes_estoque',
          {'data': saidaCorrigida.toIso8601String()},
          where: "ordem_servico_id = ? AND UPPER(tipo) = 'SAIDA'",
          whereArgs: [ordemServicoId],
        );
      }

      await transaction.insert('ordem_servico_revisoes', {
        'ordem_servico_id': ordemServicoId,
        'numero_revisao': numeroRevisao,
        'tipo': 'Correcao administrativa',
        'motivo': motivoLimpo,
        'dados_anteriores_json': jsonEncode(dadosAnteriores),
        'dados_novos_json': jsonEncode(dadosNovos),
        'criado_em': agora.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      return numeroRevisao;
    });
  }

  Future<List<Map<String, dynamic>>> listarRevisoesOrdemServico(
    int ordemServicoId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordem_servico_revisoes',
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: 'numero_revisao DESC',
    );

    return resultado.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<Map<String, dynamic>> obterResumoDoCliente(int clienteId) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        COUNT(*) AS quantidade_ordens,
        COALESCE(
          SUM(
            CASE
              WHEN status = 'Finalizada'
              THEN MAX(
                COALESCE(valor_total, 0)
                - COALESCE(desconto, 0)
                - COALESCE(desconto_negociacao, 0)
                + COALESCE(acrescimo_negociacao, 0)
                + COALESCE(juros_parcelamento, 0),
                0
              )
              ELSE 0
            END
          ),
          0
        ) AS total_gasto,
        MAX(
          CASE
            WHEN status = 'Finalizada'
            THEN COALESCE(
              data_finalizacao,
              data_abertura
            )
            ELSE NULL
          END
        ) AS ultimo_atendimento
      FROM ordens_servico
      WHERE cliente_id = ?
        AND status != 'Cancelada'
      ''',
      [clienteId],
    );

    if (resultado.isEmpty) {
      return {
        'quantidade_ordens': 0,
        'total_gasto': 0.0,
        'ticket_medio': 0.0,
        'ultimo_atendimento': '',
      };
    }

    final linha = resultado.first;

    final quantidade = (linha['quantidade_ordens'] as num?)?.toInt() ?? 0;

    final total = (linha['total_gasto'] as num?)?.toDouble() ?? 0.0;

    return {
      'quantidade_ordens': quantidade,
      'total_gasto': total,
      'ticket_medio': quantidade > 0 ? total / quantidade : 0.0,
      'ultimo_atendimento': (linha['ultimo_atendimento'] ?? '').toString(),
    };
  }

  Future<List<Map<String, dynamic>>> listarHistoricoDoCliente(
    int clienteId,
  ) async {
    final database = await _appDatabase.database;

    return database.rawQuery(
      '''
      SELECT
        os.id,
        os.numero,
        os.status,
        os.data_abertura,
        os.data_inicio,
        os.data_finalizacao,
        os.hora_entrada,
        os.hora_saida,
        os.valor_total,
        os.desconto,
        os.forma_pagamento,
        os.observacoes,
        os.veiculo_id,
        veiculos.marca AS veiculo_marca,
        veiculos.modelo AS veiculo_modelo,
        veiculos.placa AS veiculo_placa,
        (
          SELECT GROUP_CONCAT(
            itens.servico,
            ' • '
          )
          FROM ordem_servico_itens itens
          WHERE itens.ordem_servico_id = os.id
        ) AS servicos
      FROM ordens_servico os
      LEFT JOIN veiculos
        ON veiculos.id = os.veiculo_id
      WHERE os.cliente_id = ?
      ORDER BY
        COALESCE(
          os.data_finalizacao,
          os.data_inicio,
          os.data_abertura
        ) DESC,
        os.id DESC
      ''',
      [clienteId],
    );
  }

  Future<Map<String, dynamic>> obterResumoDoVeiculo(int veiculoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        COUNT(
          CASE
            WHEN status != 'Cancelada' THEN 1
          END
        ) AS quantidade_ordens,
        COALESCE(
          SUM(
            CASE
              WHEN status = 'Finalizada'
              THEN CASE
                WHEN (
                  COALESCE(valor_total, 0)
                  - COALESCE(desconto, 0)
                  - COALESCE(desconto_negociacao, 0)
                  + COALESCE(acrescimo_negociacao, 0)
                  + COALESCE(juros_parcelamento, 0)
                ) > 0
                THEN (
                  COALESCE(valor_total, 0)
                  - COALESCE(desconto, 0)
                  - COALESCE(desconto_negociacao, 0)
                  + COALESCE(acrescimo_negociacao, 0)
                  + COALESCE(juros_parcelamento, 0)
                )
                ELSE 0
              END
              ELSE 0
            END
          ),
          0
        ) AS total_investido,
        MAX(
          CASE
            WHEN status = 'Finalizada'
            THEN COALESCE(
              data_finalizacao,
              data_inicio,
              data_abertura
            )
            ELSE NULL
          END
        ) AS ultimo_atendimento
      FROM ordens_servico
      WHERE veiculo_id = ?
      ''',
      [veiculoId],
    );

    if (resultado.isEmpty) {
      return {
        'quantidade_ordens': 0,
        'total_investido': 0.0,
        'ultimo_atendimento': '',
      };
    }

    final linha = resultado.first;

    return {
      'quantidade_ordens': (linha['quantidade_ordens'] as num?)?.toInt() ?? 0,
      'total_investido': (linha['total_investido'] as num?)?.toDouble() ?? 0.0,
      'ultimo_atendimento': (linha['ultimo_atendimento'] ?? '').toString(),
    };
  }

  Future<List<Map<String, dynamic>>> listarHistoricoDoVeiculo(
    int veiculoId,
  ) async {
    final database = await _appDatabase.database;

    return database.rawQuery(
      '''
      SELECT
        os.id,
        os.numero,
        os.status,
        os.data_abertura,
        os.data_inicio,
        os.data_finalizacao,
        os.hora_entrada,
        os.hora_saida,
        os.valor_total,
        os.desconto,
        os.forma_pagamento,
        os.observacoes,
        os.funcionario_responsavel,
        (
          SELECT GROUP_CONCAT(
            itens.servico,
            ' • '
          )
          FROM ordem_servico_itens itens
          WHERE itens.ordem_servico_id = os.id
        ) AS servicos,
        (
          SELECT GROUP_CONCAT(
            produtos.produto_nome ||
            CASE
              WHEN produtos.quantidade > 0
              THEN ' (' ||
                REPLACE(
                  printf('%.2f', produtos.quantidade),
                  '.00',
                  ''
                ) ||
                CASE
                  WHEN TRIM(
                    COALESCE(produtos.unidade, '')
                  ) != ''
                  THEN ' ' || produtos.unidade
                  ELSE ''
                END ||
                ')'
              ELSE ''
            END,
            ' • '
          )
          FROM ordem_servico_produtos produtos
          WHERE produtos.ordem_servico_id = os.id
        ) AS produtos_utilizados,
        (
          SELECT COALESCE(
            SUM(
              COALESCE(
                NULLIF(produtos.custo_total_no_momento, 0),
                produtos.quantidade * COALESCE(
                  produtos.custo_unitario_no_momento,
                  produtos.custo_unitario,
                  0
                )
              )
            ),
            0
          )
          FROM ordem_servico_produtos produtos
          WHERE produtos.ordem_servico_id = os.id
        ) AS custo_produtos
      FROM ordens_servico os
      WHERE os.veiculo_id = ?
      ORDER BY
        COALESCE(
          os.data_finalizacao,
          os.data_inicio,
          os.data_abertura
        ) DESC,
        os.id DESC
      ''',
      [veiculoId],
    );
  }

  Future<Map<String, dynamic>?> buscarUltimoServicoDoVeiculo(
    int veiculoId,
  ) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT
        os.id,
        os.numero,
        os.data_finalizacao,
        os.data_inicio,
        os.data_abertura,
        (
          SELECT GROUP_CONCAT(
            itens.servico,
            ' • '
          )
          FROM ordem_servico_itens itens
          WHERE itens.ordem_servico_id = os.id
        ) AS servicos
      FROM ordens_servico os
      WHERE os.veiculo_id = ?
        AND os.status = 'Finalizada'
      ORDER BY
        COALESCE(
          os.data_finalizacao,
          os.data_inicio,
          os.data_abertura
        ) DESC,
        os.id DESC
      LIMIT 1
      ''',
      [veiculoId],
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(resultado.first);
  }

  Future<void> cancelarOrdemServico(int ordemServicoId) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordens_servico',
        columns: ['id', 'status', 'agendamento_id', 'valor_recebido'],
        where: 'id = ?',
        whereArgs: [ordemServicoId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Ordem de Serviço não encontrada.');
      }

      final ordem = resultado.first;
      final statusAtual = (ordem['status'] ?? '').toString().trim();

      if (statusAtual == 'Cancelada') {
        return;
      }

      final valorRecebido = (ordem['valor_recebido'] as num?)?.toDouble() ?? 0;

      if (valorRecebido > 0.000001) {
        throw StateError(
          'Estorne os pagamentos recebidos antes de cancelar esta OS.',
        );
      }

      await transaction.update(
        'ordem_servico_pagamentos',
        {
          'status': 'Cancelado',
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: "ordem_servico_id = ? AND status = 'Pendente'",
        whereArgs: [ordemServicoId],
      );

      await transaction.update(
        'ordens_servico',
        {
          'status': 'Cancelada',
          'status_pagamento': 'Cancelado',
          'vencimento_pagamento': null,
          'pagamento_atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      final agendamentoId = _converterInt(ordem['agendamento_id']);

      if (agendamentoId != null) {
        await _agendamentoRepository.atualizarStatusComTransacao(
          transaction,
          agendamentoId,
          'Cancelado',
        );
      }
    });
  }

  Future<void> atualizarDadosEntrada({
    required int ordemServicoId,
    String quilometragem = '',
    String combustivel = '',
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      'ordens_servico',
      {
        'quilometragem_entrada': quilometragem.trim(),
        'combustivel_entrada': combustivel.trim(),
      },
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );
  }

  Future<Map<String, String>> buscarDadosEntrada(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordens_servico',
      columns: ['quilometragem_entrada', 'combustivel_entrada'],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return {'quilometragem': '', 'combustivel': ''};
    }

    final item = resultado.first;

    return {
      'quilometragem': (item['quilometragem_entrada'] ?? '').toString().trim(),
      'combustivel': (item['combustivel_entrada'] ?? '').toString().trim(),
    };
  }

  Future<void> marcarComoLancadaNoFinanceiro(int ordemServicoId) async {
    final database = await _appDatabase.database;

    await database.update(
      'ordens_servico',
      {'lancado_financeiro': 1},
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );
  }

  Future<bool> existeOrdemParaOrcamento(int orcamentoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ordens_servico
      WHERE orcamento_id = ?
      ''',
      [orcamentoId],
    );

    final total = Sqflite.firstIntValue(resultado) ?? 0;

    return total > 0;
  }

  Future<String> gerarProximoNumero() async {
    final database = await _appDatabase.database;

    final agora = DateTime.now();
    final ano = agora.year.toString();

    final resultado = await database.rawQuery('''
      SELECT MAX(id) AS ultimo_id
      FROM ordens_servico
      ''');

    final ultimoId = Sqflite.firstIntValue(resultado) ?? 0;

    final proximo = ultimoId + 1;

    return 'OS-$ano-${proximo.toString().padLeft(4, '0')}';
  }

  Future<void> excluirOrdemServico(int ordemServicoId) async {
    await _excluirOrdemServicoComReversao(
      ordemServicoId,
      restaurarAgendamento: false,
    );
  }

  /// Exclusão administrativa para limpar Ordens de Serviço criadas em testes.
  ///
  /// Antes de apagar a OS, desfaz os efeitos automáticos que ela causou no
  /// estoque e remove as movimentações financeiras vinculadas. Cliente,
  /// veículo, produtos do estoque, serviços do catálogo, orçamento e
  /// agendamento não são excluídos.
  Future<void> excluirOrdemServicoDeTeste(int ordemServicoId) async {
    await _excluirOrdemServicoComReversao(
      ordemServicoId,
      restaurarAgendamento: true,
    );
  }

  Future<void> _excluirOrdemServicoComReversao(
    int ordemServicoId, {
    required bool restaurarAgendamento,
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      final resultado = await transaction.query(
        'ordens_servico',
        columns: ['id', 'numero', 'status', 'agendamento_id'],
        where: 'id = ?',
        whereArgs: [ordemServicoId],
        limit: 1,
      );

      if (resultado.isEmpty) {
        throw StateError('Ordem de Serviço não encontrada.');
      }

      final ordem = resultado.first;
      final status = (ordem['status'] ?? '').toString().trim();
      final agendamentoId = _converterInt(ordem['agendamento_id']);

      if (restaurarAgendamento && status != 'Finalizada') {
        throw StateError(
          'A exclusão de OS de teste é destinada a Ordens de Serviço '
          'finalizadas.',
        );
      }

      // Desfaz a baixa de estoque antes de apagar os registros da OS.
      await _restaurarEstoqueDaOrdemDeTeste(transaction, ordemServicoId);

      // Os FKs de movimentos financeiros usam ON DELETE SET NULL. Por isso
      // removemos explicitamente todos os movimentos ligados à OS ou aos seus
      // pagamentos antes de apagar a OS, evitando saldo "fantasma".
      await transaction.rawDelete(
        '''
        DELETE FROM movimentos_financeiros
        WHERE ordem_servico_id = ?
           OR pagamento_id IN (
             SELECT id
             FROM ordem_servico_pagamentos
             WHERE ordem_servico_id = ?
           )
        ''',
        [ordemServicoId, ordemServicoId],
      );

      // Movimentações de estoque também usam ON DELETE SET NULL. Após devolver
      // as quantidades, elas precisam ser removidas explicitamente.
      await transaction.delete(
        'movimentacoes_estoque',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemServicoId],
      );

      // O perfil de preço da OS fica em uma tabela gerencial auxiliar sem
      // FK para não exigir mudança de schemaVersion. Remove o snapshot
      // explicitamente quando a OS é excluída, evitando metadado órfão.
      final tabelaPerfil = await transaction.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name = 'financeiro_preco_documentos'
        LIMIT 1
        ''');

      if (tabelaPerfil.isNotEmpty) {
        await transaction.delete(
          'financeiro_preco_documentos',
          where: 'documento_tipo = ? AND documento_id = ?',
          whereArgs: ['OS', ordemServicoId],
        );
      }

      final tabelaDesconto = await transaction.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name = 'financeiro_desconto_documentos'
        LIMIT 1
        ''');

      if (tabelaDesconto.isNotEmpty) {
        await transaction.delete(
          'financeiro_desconto_documentos',
          where: 'documento_tipo = ? AND documento_id = ?',
          whereArgs: ['OS', ordemServicoId],
        );
      }

      // Itens, produtos, composição de lotes, checklist, fotos, revisões,
      // pagamentos, ajustes financeiros e mão de obra vinculados possuem
      // cascata a partir da OS. Os arquivos físicos de fotos/assinaturas não
      // são apagados aqui para evitar remover um arquivo externo do usuário.
      final removidas = await transaction.delete(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      if (removidas == 0) {
        throw StateError('Não foi possível excluir a Ordem de Serviço.');
      }

      if (agendamentoId != null) {
        await _agendamentoRepository.atualizarStatusComTransacao(
          transaction,
          agendamentoId,
          restaurarAgendamento
              ? 'Agendado'
              : _statusAgendamentoAposExcluirOrdem(status),
        );
      }
    });
  }

  Future<void> _restaurarEstoqueDaOrdemDeTeste(
    Transaction transaction,
    int ordemServicoId,
  ) async {
    final movimentos = await transaction.query(
      'movimentacoes_estoque',
      columns: ['item_estoque_id', 'lote_id', 'tipo', 'quantidade'],
      where: 'ordem_servico_id = ?',
      whereArgs: [ordemServicoId],
      orderBy: 'id ASC',
    );

    final deltaPorItem = <int, double>{};
    final deltaPorLote = <int, double>{};

    for (final movimento in movimentos) {
      final itemId = _converterInt(movimento['item_estoque_id']);
      final loteId = _converterInt(movimento['lote_id']);
      final quantidade = (movimento['quantidade'] as num?)?.toDouble() ?? 0.0;
      final tipo = (movimento['tipo'] ?? '').toString().trim().toLowerCase();

      if (itemId == null || quantidade <= 0) {
        continue;
      }

      double delta;
      if (tipo == 'saida' || tipo == 'saída') {
        // A OS retirou do estoque: para apagá-la, devolvemos.
        delta = quantidade;
      } else if (tipo == 'entrada') {
        // Caso exista uma entrada vinculada à OS, também desfazemos seu efeito.
        delta = -quantidade;
      } else {
        continue;
      }

      deltaPorItem[itemId] = (deltaPorItem[itemId] ?? 0) + delta;
      if (loteId != null) {
        deltaPorLote[loteId] = (deltaPorLote[loteId] ?? 0) + delta;
      }
    }

    // Bancos legados podem ter a composição FIFO gravada sem a movimentação
    // de estoque correspondente. Nesse caso usamos a composição dos lotes como
    // fonte para a devolução.
    if (deltaPorItem.isEmpty) {
      final composicoes = await transaction.rawQuery(
        '''
        SELECT
          p.produto_id AS item_estoque_id,
          l.lote_id,
          COALESCE(SUM(l.quantidade), 0) AS quantidade
        FROM ordem_servico_produto_lotes l
        INNER JOIN ordem_servico_produtos p
          ON p.id = l.ordem_servico_produto_id
        WHERE p.ordem_servico_id = ?
          AND p.produto_id IS NOT NULL
        GROUP BY p.produto_id, l.lote_id
        ''',
        [ordemServicoId],
      );

      for (final item in composicoes) {
        final itemId = _converterInt(item['item_estoque_id']);
        final loteId = _converterInt(item['lote_id']);
        final quantidade = (item['quantidade'] as num?)?.toDouble() ?? 0.0;

        if (itemId == null || quantidade <= 0) {
          continue;
        }

        deltaPorItem[itemId] = (deltaPorItem[itemId] ?? 0) + quantidade;
        if (loteId != null) {
          deltaPorLote[loteId] = (deltaPorLote[loteId] ?? 0) + quantidade;
        }
      }
    }

    if (deltaPorItem.isEmpty && deltaPorLote.isEmpty) {
      return;
    }

    final agora = DateTime.now().toIso8601String();

    for (final entry in deltaPorLote.entries) {
      final lote = await transaction.query(
        'estoque_lotes',
        columns: ['id', 'quantidade_disponivel'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );

      if (lote.isEmpty) {
        // Se um lote histórico já foi removido, ainda restauramos o saldo do
        // item abaixo. Não inventamos um novo lote de compra.
        continue;
      }

      final atual =
          (lote.first['quantidade_disponivel'] as num?)?.toDouble() ?? 0.0;
      final novo = (atual + entry.value).clamp(0, double.infinity).toDouble();

      await transaction.update(
        'estoque_lotes',
        {'quantidade_disponivel': novo, if (entry.value > 0) 'ativo': 1},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }

    for (final entry in deltaPorItem.entries) {
      final item = await transaction.query(
        'itens_estoque',
        columns: ['id', 'quantidade'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );

      if (item.isEmpty) {
        continue;
      }

      final atual = (item.first['quantidade'] as num?)?.toDouble() ?? 0.0;
      final novo = (atual + entry.value).clamp(0, double.infinity).toDouble();

      await transaction.update(
        'itens_estoque',
        {'quantidade': novo, 'atualizado_em': agora},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
  }

  String _statusAgendamentoAposExcluirOrdem(String statusOrdem) {
    if (statusOrdem == 'Finalizada') {
      return 'Finalizado';
    }

    if (statusOrdem == 'Cancelada') {
      return 'Cancelado';
    }

    return 'Agendado';
  }

  Future<String?> buscarAssinaturaCliente(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'ordens_servico',
      columns: ['assinatura_cliente'],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    final assinatura = resultado.first['assinatura_cliente']?.toString().trim();

    if (assinatura == null || assinatura.isEmpty) {
      return null;
    }

    return assinatura;
  }

  Future<void> salvarAssinaturaCliente({
    required int ordemServicoId,
    required String caminhoAssinatura,
  }) async {
    final caminho = caminhoAssinatura.trim();

    if (caminho.isEmpty) {
      throw ArgumentError('O caminho da assinatura não pode estar vazio.');
    }

    final database = await _appDatabase.database;

    final linhasAlteradas = await database.update(
      'ordens_servico',
      {'assinatura_cliente': caminho},
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );

    if (linhasAlteradas == 0) {
      throw StateError('Ordem de Serviço não encontrada.');
    }
  }

  Future<void> removerAssinaturaCliente(int ordemServicoId) async {
    final database = await _appDatabase.database;

    final linhasAlteradas = await database.update(
      'ordens_servico',
      {'assinatura_cliente': null},
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );

    if (linhasAlteradas == 0) {
      throw StateError('Ordem de Serviço não encontrada.');
    }
  }

  DateTime? _combinarDataHoraArmazenada(dynamic data, dynamic hora) {
    final textoData = (data ?? '').toString().trim();
    if (textoData.isEmpty) {
      return null;
    }

    final dataBase = DateTime.tryParse(textoData);
    if (dataBase == null) {
      return null;
    }

    var horaValor = 0;
    var minutoValor = 0;
    final textoHora = (hora ?? '').toString().trim();
    if (textoHora.isNotEmpty) {
      final partes = textoHora.split(':');
      if (partes.length >= 2) {
        horaValor = int.tryParse(partes[0]) ?? 0;
        minutoValor = int.tryParse(partes[1]) ?? 0;
      }
    }

    return DateTime(
      dataBase.year,
      dataBase.month,
      dataBase.day,
      horaValor,
      minutoValor,
    );
  }

  String? _normalizarDataBanco(String? valor, {required String campo}) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return null;
    }

    DateTime? data = DateTime.tryParse(texto);
    if (data == null) {
      final partes = texto.split('/');
      if (partes.length == 3) {
        final dia = int.tryParse(partes[0]);
        final mes = int.tryParse(partes[1]);
        final ano = int.tryParse(partes[2]);
        if (dia != null && mes != null && ano != null) {
          final candidata = DateTime(ano, mes, dia);
          if (candidata.year == ano &&
              candidata.month == mes &&
              candidata.day == dia) {
            data = candidata;
          }
        }
      }
    }

    if (data == null) {
      throw ArgumentError('Informe uma $campo válida.');
    }

    return _formatarData(data);
  }

  void _validarPeriodoOperacional({
    required String? dataInicio,
    required String? horaEntrada,
    required String? dataFinalizacao,
    required String? horaSaida,
  }) {
    if (dataInicio == null || dataFinalizacao == null) {
      return;
    }

    final entradaData = DateTime.tryParse(dataInicio);
    final saidaData = DateTime.tryParse(dataFinalizacao);
    if (entradaData == null || saidaData == null) {
      return;
    }

    final entradaDia = DateTime(
      entradaData.year,
      entradaData.month,
      entradaData.day,
    );
    final saidaDia = DateTime(saidaData.year, saidaData.month, saidaData.day);

    if (saidaDia.isBefore(entradaDia)) {
      throw ArgumentError('A data de saída não pode ser anterior à entrada.');
    }

    if (saidaDia != entradaDia || horaEntrada == null || horaSaida == null) {
      return;
    }

    int minutos(String valor) {
      final partes = valor.split(':');
      if (partes.length < 2) {
        return 0;
      }
      final hora = int.tryParse(partes[0]) ?? 0;
      final minuto = int.tryParse(partes[1]) ?? 0;
      return hora * 60 + minuto;
    }

    if (minutos(horaSaida) < minutos(horaEntrada)) {
      throw ArgumentError(
        'A hora de saída não pode ser anterior à hora de entrada no mesmo dia.',
      );
    }
  }

  String _formatarData(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');

    return '$ano-$mes-$dia';
  }

  String _formatarHora(DateTime data) {
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$hora:$minuto';
  }

  String _formatarQuantidadeMensagem(double valor) {
    final texto = valor
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');

    return texto.isEmpty ? '0' : texto;
  }
}
