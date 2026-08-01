import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/ordem_servico.dart';
import '../models/ordem_servico_item.dart';
import '../models/movimentacao_estoque.dart';
import '../models/produto_ordem_servico.dart';
import '../repositories/agendamento_repository.dart';
import '../repositories/estoque_repository.dart';
import '../repositories/produto_ordem_servico_repository.dart';

class OrdemServicoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final EstoqueRepository _estoqueRepository = EstoqueRepository();

  final ProdutoOrdemServicoRepository _produtoRepository =
      ProdutoOrdemServicoRepository();

  final AgendamentoRepository _agendamentoRepository = AgendamentoRepository();

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
          'Em andamento',
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

  Future<void> iniciarOrdemServico(int ordemServicoId) async {
    final agora = DateTime.now();
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
          'data_inicio': _formatarData(agora),
          'hora_entrada': _formatarHora(agora),
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
  }) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now();
    final formaPagamentoLimpa = formaPagamento?.trim() ?? '';

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
          'lancado_financeiro',
          'agendamento_id',
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

      if (statusAtual == 'Cancelada') {
        throw StateError(
          'Uma Ordem de Serviço cancelada não pode ser finalizada.',
        );
      }

      final valorTotal = (ordem['valor_total'] as num?)?.toDouble() ?? 0;

      final desconto = (ordem['desconto'] as num?)?.toDouble() ?? 0;

      final valorFinal = (valorTotal - desconto)
          .clamp(0, double.infinity)
          .toDouble();

      final lancadoFinanceiro =
          (ordem['lancado_financeiro'] as num?)?.toInt() == 1;

      final numero = (ordem['numero'] ?? ordemServicoId).toString().trim();

      final clienteId = (ordem['cliente_id'] as num?)?.toInt();

      final produtos = await transaction.query(
        'ordem_servico_produtos',
        where: 'ordem_servico_id = ? AND baixado_estoque = 0',
        whereArgs: [ordemServicoId],
        orderBy: 'id ASC',
      );

      // Primeiro valida o estoque de todos os produtos.
      for (final produtoOs in produtos) {
        final produtoId = (produtoOs['produto_id'] as num?)?.toInt();

        final produtoNome = (produtoOs['produto_nome'] ?? 'Produto')
            .toString()
            .trim();

        final quantidadeUtilizada =
            (produtoOs['quantidade'] as num?)?.toDouble() ?? 0;

        if (produtoId == null || quantidadeUtilizada <= 0) {
          continue;
        }

        final resultadoItem = await transaction.query(
          'itens_estoque',
          columns: ['id', 'nome', 'quantidade', 'custo_unitario'],
          where: 'id = ?',
          whereArgs: [produtoId],
          limit: 1,
        );

        if (resultadoItem.isEmpty) {
          throw StateError(
            'O produto "$produtoNome" não foi encontrado no estoque.',
          );
        }

        final quantidadeDisponivel =
            (resultadoItem.first['quantidade'] as num?)?.toDouble() ?? 0;

        if (quantidadeUtilizada > quantidadeDisponivel) {
          throw StateError(
            'Estoque insuficiente para "$produtoNome". '
            'Disponível: $quantidadeDisponivel. '
            'Necessário: $quantidadeUtilizada.',
          );
        }
      }

      // Depois realiza todas as baixas.
      for (final produtoOs in produtos) {
        final produtoOsId = (produtoOs['id'] as num?)?.toInt();

        final produtoId = (produtoOs['produto_id'] as num?)?.toInt();

        final quantidadeUtilizada =
            (produtoOs['quantidade'] as num?)?.toDouble() ?? 0;

        if (produtoId == null || quantidadeUtilizada <= 0) {
          if (produtoOsId != null) {
            await transaction.update(
              'ordem_servico_produtos',
              {'baixado_estoque': 1},
              where: 'id = ?',
              whereArgs: [produtoOsId],
            );
          }

          continue;
        }

        final resultadoItem = await transaction.query(
          'itens_estoque',
          columns: ['quantidade', 'custo_unitario'],
          where: 'id = ?',
          whereArgs: [produtoId],
          limit: 1,
        );

        if (resultadoItem.isEmpty) {
          throw StateError('Produto não encontrado no estoque.');
        }

        final quantidadeAnterior =
            (resultadoItem.first['quantidade'] as num?)?.toDouble() ?? 0;

        final custoUnitarioEstoque =
            (resultadoItem.first['custo_unitario'] as num?)?.toDouble() ?? 0;

        final custoUnitarioOs =
            (produtoOs['custo_unitario'] as num?)?.toDouble() ?? 0;

        final custoUnitario = custoUnitarioOs > 0
            ? custoUnitarioOs
            : custoUnitarioEstoque;

        final quantidadePosterior = quantidadeAnterior - quantidadeUtilizada;

        await transaction.update(
          'itens_estoque',
          {
            'quantidade': quantidadePosterior,
            'atualizado_em': agora.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [produtoId],
        );

        await transaction.insert('movimentacoes_estoque', {
          'item_estoque_id': produtoId,
          'tipo': 'SAIDA',
          'quantidade': quantidadeUtilizada,
          'quantidade_anterior': quantidadeAnterior,
          'quantidade_posterior': quantidadePosterior,
          'custo_unitario': custoUnitario,
          'observacoes': 'Baixa automática da Ordem de Serviço $numero',
          'origem': 'Ordem de Serviço',
          'ordem_servico_id': ordemServicoId,
          'data': agora.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        if (produtoOsId != null) {
          await transaction.update(
            'ordem_servico_produtos',
            {'baixado_estoque': 1},
            where: 'id = ?',
            whereArgs: [produtoOsId],
          );
        }
      }

      if (!lancadoFinanceiro && valorFinal > 0) {
        await transaction.insert('movimentos_financeiros', {
          'tipo': 'entrada',
          'descricao': 'Ordem de Serviço finalizada: $numero',
          'valor': valorFinal,
          'forma_pagamento': formaPagamentoLimpa.isEmpty
              ? 'Não informado'
              : formaPagamentoLimpa,
          'data': agora.toIso8601String(),
          'cliente_id': clienteId,
          'agendamento_id': null,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }

      final dados = <String, dynamic>{
        'status': 'Finalizada',
        'data_finalizacao': _formatarData(agora),
        'hora_saida': _formatarHora(agora),
        'lancado_financeiro': lancadoFinanceiro || valorFinal > 0 ? 1 : 0,
      };

      final agendamentoId = _converterInt(ordem['agendamento_id']);

      if (agendamentoId != null) {
        await _agendamentoRepository.atualizarStatusComTransacao(
          transaction,
          agendamentoId,
          'Finalizado',
        );
      }

      if (formaPagamentoLimpa.isNotEmpty) {
        dados['forma_pagamento'] = formaPagamentoLimpa;
      }

      await transaction.update(
        'ordens_servico',
        dados,
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );
    });
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
              THEN MAX(valor_total - desconto, 0)
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
                WHEN (valor_total - desconto) > 0
                THEN (valor_total - desconto)
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
              produtos.quantidade *
              produtos.custo_unitario
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

      if (statusAtual == 'Cancelada') {
        return;
      }

      await transaction.update(
        'ordens_servico',
        {'status': 'Cancelada'},
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );
    });
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
    final database = await _appDatabase.database;

    await database.delete(
      'ordens_servico',
      where: 'id = ?',
      whereArgs: [ordemServicoId],
    );
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
}
