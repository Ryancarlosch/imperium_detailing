import 'package:sqflite/sqflite.dart';

import '../config/imperium_regras_negocio.dart';
import '../database/app_database.dart';
import '../domain/ordem_servico_valor.dart';
import '../models/colaborador_custo.dart';
import '../models/custo_fixo.dart';

class CustosRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<List<CustoFixo>> listarCustosFixos({
    bool incluirInativos = false,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'financeiro_custos_fixos',
      where: incluirInativos ? null : 'ativo = 1',
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC, id ASC',
    );
    return resultado
        .map((item) => CustoFixo.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<int> salvarCustoFixo(CustoFixo custo) async {
    final nome = custo.nome.trim();
    if (nome.length < 2) {
      throw ArgumentError('Informe o nome do custo fixo.');
    }
    if (custo.valorMensal < 0) {
      throw ArgumentError('O valor mensal não pode ser negativo.');
    }
    if (custo.diaVencimento != null &&
        (custo.diaVencimento! < 1 || custo.diaVencimento! > 31)) {
      throw ArgumentError('O dia de vencimento deve ficar entre 1 e 31.');
    }

    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();
    final mapa = custo.toMap(incluirId: false)
      ..['nome'] = nome
      ..['atualizado_em'] = agora;

    if (custo.id == null) {
      mapa['criado_em'] = agora;
      return database.insert(
        'financeiro_custos_fixos',
        mapa,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    await database.update(
      'financeiro_custos_fixos',
      mapa,
      where: 'id = ?',
      whereArgs: [custo.id],
    );
    return custo.id!;
  }

  Future<void> arquivarCustoFixo(int id) async {
    final database = await _appDatabase.database;
    await database.update(
      'financeiro_custos_fixos',
      {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ColaboradorCusto>> listarColaboradores({
    bool incluirInativos = false,
  }) async {
    final database = await _appDatabase.database;
    final resultado = await database.query(
      'financeiro_colaboradores_custo',
      where: incluirInativos ? null : 'ativo = 1',
      orderBy: 'ativo DESC, nome COLLATE NOCASE ASC, id ASC',
    );
    return resultado
        .map(
          (item) => ColaboradorCusto.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<int> salvarColaborador(
    ColaboradorCusto colaborador, {
    String motivo = '',
  }) async {
    final nome = colaborador.nome.trim();
    if (nome.length < 2) {
      throw ArgumentError('Informe o nome do colaborador.');
    }
    if (colaborador.remuneracaoMensal < 0 ||
        colaborador.encargosMensais < 0 ||
        colaborador.outrosCustosMensais < 0) {
      throw ArgumentError('Os valores de custo não podem ser negativos.');
    }
    if (colaborador.horasProdutivasMes <= 0) {
      throw ArgumentError('Informe as horas produtivas mensais.');
    }

    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();

    return database.transaction<int>((transaction) async {
      await _garantirTabelaHistoricoColaboradores(transaction);

      final mapa = colaborador.toMap(incluirId: false)
        ..['nome'] = nome
        ..['funcao'] = colaborador.funcao.trim()
        ..['atualizado_em'] = agora;

      if (colaborador.id == null) {
        mapa['criado_em'] = agora;
        final id = await transaction.insert(
          'financeiro_colaboradores_custo',
          mapa,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        await _registrarHistoricoColaborador(
          transaction,
          colaboradorId: id,
          tipo: 'Cadastro',
          remuneracaoAnterior: 0,
          remuneracaoNova: colaborador.remuneracaoMensal,
          encargosAnteriores: 0,
          encargosNovos: colaborador.encargosMensais,
          outrosCustosAnteriores: 0,
          outrosCustosNovos: colaborador.outrosCustosMensais,
          ativoAnterior: null,
          ativoNovo: colaborador.ativo,
          motivo: motivo.trim().isEmpty ? 'Cadastro do funcionário' : motivo,
          vigencia: DateTime.now(),
        );

        return id;
      }

      final anterior = await transaction.query(
        'financeiro_colaboradores_custo',
        where: 'id = ?',
        whereArgs: [colaborador.id],
        limit: 1,
      );
      if (anterior.isEmpty) {
        throw StateError('Funcionário não encontrado.');
      }

      final remuneracaoAnterior = _double(anterior.first['remuneracao_mensal']);
      final encargosAnteriores = _double(anterior.first['encargos_mensais']);
      final outrosAnteriores = _double(anterior.first['outros_custos_mensais']);
      final ativoAnterior = _int(anterior.first['ativo']) == 1;

      await transaction.update(
        'financeiro_colaboradores_custo',
        mapa,
        where: 'id = ?',
        whereArgs: [colaborador.id],
      );

      final alterouRemuneracao =
          (remuneracaoAnterior - colaborador.remuneracaoMensal).abs() >
          0.000001;
      final alterouCustos =
          (encargosAnteriores - colaborador.encargosMensais).abs() > 0.000001 ||
          (outrosAnteriores - colaborador.outrosCustosMensais).abs() > 0.000001;
      final alterouAtivo = ativoAnterior != colaborador.ativo;

      if (alterouRemuneracao || alterouCustos || alterouAtivo) {
        final tipo = alterouAtivo
            ? (colaborador.ativo ? 'Ativação' : 'Inativação')
            : alterouRemuneracao
            ? 'Reajuste salarial'
            : 'Atualização de custos';

        await _registrarHistoricoColaborador(
          transaction,
          colaboradorId: colaborador.id!,
          tipo: tipo,
          remuneracaoAnterior: remuneracaoAnterior,
          remuneracaoNova: colaborador.remuneracaoMensal,
          encargosAnteriores: encargosAnteriores,
          encargosNovos: colaborador.encargosMensais,
          outrosCustosAnteriores: outrosAnteriores,
          outrosCustosNovos: colaborador.outrosCustosMensais,
          ativoAnterior: ativoAnterior,
          ativoNovo: colaborador.ativo,
          motivo: motivo.trim(),
          vigencia: DateTime.now(),
        );
      }

      return colaborador.id!;
    });
  }

  Future<void> arquivarColaborador(int id, {String motivo = ''}) async {
    await definirAtivoColaborador(id, false, motivo: motivo);
  }

  Future<void> definirAtivoColaborador(
    int id,
    bool ativo, {
    String motivo = '',
  }) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _garantirTabelaHistoricoColaboradores(transaction);

      final resultado = await transaction.query(
        'financeiro_colaboradores_custo',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (resultado.isEmpty) {
        throw StateError('Funcionário não encontrado.');
      }

      final atual = resultado.first;
      final ativoAnterior = _int(atual['ativo']) == 1;
      if (ativoAnterior == ativo) {
        return;
      }

      final agora = DateTime.now();
      await transaction.update(
        'financeiro_colaboradores_custo',
        {'ativo': ativo ? 1 : 0, 'atualizado_em': agora.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

      await _registrarHistoricoColaborador(
        transaction,
        colaboradorId: id,
        tipo: ativo ? 'Ativação' : 'Inativação',
        remuneracaoAnterior: _double(atual['remuneracao_mensal']),
        remuneracaoNova: _double(atual['remuneracao_mensal']),
        encargosAnteriores: _double(atual['encargos_mensais']),
        encargosNovos: _double(atual['encargos_mensais']),
        outrosCustosAnteriores: _double(atual['outros_custos_mensais']),
        outrosCustosNovos: _double(atual['outros_custos_mensais']),
        ativoAnterior: ativoAnterior,
        ativoNovo: ativo,
        motivo: motivo.trim().isEmpty
            ? (ativo ? 'Funcionário reativado' : 'Funcionário inativado')
            : motivo.trim(),
        vigencia: agora,
      );
    });
  }

  Future<void> registrarReajusteRemuneracao({
    required int colaboradorId,
    required double novaRemuneracao,
    required DateTime vigencia,
    String motivo = '',
  }) async {
    if (novaRemuneracao < 0) {
      throw ArgumentError('A remuneração não pode ser negativa.');
    }

    final hoje = DateTime.now();
    final hojeDia = DateTime(hoje.year, hoje.month, hoje.day);
    final vigenciaDia = DateTime(vigencia.year, vigencia.month, vigencia.day);
    if (vigenciaDia.isAfter(hojeDia)) {
      throw ArgumentError(
        'A vigência futura ainda não é suportada. Use a data em que o reajuste entrou em vigor.',
      );
    }

    final database = await _appDatabase.database;
    await database.transaction((transaction) async {
      await _garantirTabelaHistoricoColaboradores(transaction);

      final resultado = await transaction.query(
        'financeiro_colaboradores_custo',
        where: 'id = ?',
        whereArgs: [colaboradorId],
        limit: 1,
      );
      if (resultado.isEmpty) {
        throw StateError('Funcionário não encontrado.');
      }

      final atual = resultado.first;
      final anterior = _double(atual['remuneracao_mensal']);
      if ((anterior - novaRemuneracao).abs() <= 0.000001) {
        throw StateError('A nova remuneração é igual à atual.');
      }

      await transaction.update(
        'financeiro_colaboradores_custo',
        {
          'remuneracao_mensal': novaRemuneracao,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [colaboradorId],
      );

      await _registrarHistoricoColaborador(
        transaction,
        colaboradorId: colaboradorId,
        tipo: 'Reajuste salarial',
        remuneracaoAnterior: anterior,
        remuneracaoNova: novaRemuneracao,
        encargosAnteriores: _double(atual['encargos_mensais']),
        encargosNovos: _double(atual['encargos_mensais']),
        outrosCustosAnteriores: _double(atual['outros_custos_mensais']),
        outrosCustosNovos: _double(atual['outros_custos_mensais']),
        ativoAnterior: _int(atual['ativo']) == 1,
        ativoNovo: _int(atual['ativo']) == 1,
        motivo: motivo.trim().isEmpty ? 'Reajuste salarial' : motivo.trim(),
        vigencia: vigenciaDia,
      );
    });
  }

  Future<bool> colaboradorAtivoNoPeriodo({
    required int colaboradorId,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _appDatabase.database;
    await _garantirTabelaHistoricoColaboradores(database);

    final antesDoPeriodo = await database.rawQuery(
      '''
      SELECT ativo_novo
      FROM financeiro_colaboradores_historico
      WHERE colaborador_id = ?
        AND ativo_novo IS NOT NULL
        AND datetime(vigencia_em) < datetime(?)
      ORDER BY datetime(vigencia_em) DESC, id DESC
      LIMIT 1
      ''',
      [colaboradorId, inicio.toIso8601String()],
    );

    if (antesDoPeriodo.isNotEmpty &&
        _int(antesDoPeriodo.first['ativo_novo']) == 1) {
      return true;
    }

    final ativacoesNoPeriodo = await database.rawQuery(
      '''
      SELECT id
      FROM financeiro_colaboradores_historico
      WHERE colaborador_id = ?
        AND ativo_novo = 1
        AND datetime(vigencia_em) BETWEEN datetime(?) AND datetime(?)
      LIMIT 1
      ''',
      [colaboradorId, inicio.toIso8601String(), fim.toIso8601String()],
    );
    if (ativacoesNoPeriodo.isNotEmpty) {
      return true;
    }

    final temHistorico = await database.rawQuery(
      '''
      SELECT id
      FROM financeiro_colaboradores_historico
      WHERE colaborador_id = ?
      LIMIT 1
      ''',
      [colaboradorId],
    );
    if (temHistorico.isNotEmpty) {
      return false;
    }

    final atual = await database.query(
      'financeiro_colaboradores_custo',
      columns: ['ativo'],
      where: 'id = ?',
      whereArgs: [colaboradorId],
      limit: 1,
    );
    return atual.isNotEmpty && _int(atual.first['ativo']) == 1;
  }

  Future<List<Map<String, dynamic>>> listarHistoricoColaborador(
    int colaboradorId,
  ) async {
    final database = await _appDatabase.database;
    await _garantirTabelaHistoricoColaboradores(database);

    return database.rawQuery(
      '''
      SELECT *
      FROM financeiro_colaboradores_historico
      WHERE colaborador_id = ?
      ORDER BY datetime(vigencia_em) DESC, id DESC
      ''',
      [colaboradorId],
    );
  }

  Future<void> _garantirTabelaHistoricoColaboradores(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_colaboradores_historico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        remuneracao_anterior REAL NOT NULL DEFAULT 0,
        remuneracao_nova REAL NOT NULL DEFAULT 0,
        encargos_anteriores REAL NOT NULL DEFAULT 0,
        encargos_novos REAL NOT NULL DEFAULT 0,
        outros_custos_anteriores REAL NOT NULL DEFAULT 0,
        outros_custos_novos REAL NOT NULL DEFAULT 0,
        ativo_anterior INTEGER,
        ativo_novo INTEGER,
        motivo TEXT NOT NULL DEFAULT '',
        vigencia_em TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE CASCADE
      )
    ''');

    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_fin_colab_hist_colab_vigencia
      ON financeiro_colaboradores_historico (
        colaborador_id,
        vigencia_em DESC,
        id DESC
      )
    ''');
  }

  Future<void> _registrarHistoricoColaborador(
    DatabaseExecutor executor, {
    required int colaboradorId,
    required String tipo,
    required double remuneracaoAnterior,
    required double remuneracaoNova,
    required double encargosAnteriores,
    required double encargosNovos,
    required double outrosCustosAnteriores,
    required double outrosCustosNovos,
    required bool? ativoAnterior,
    required bool? ativoNovo,
    required String motivo,
    required DateTime vigencia,
  }) async {
    await executor.insert(
      'financeiro_colaboradores_historico',
      {
        'colaborador_id': colaboradorId,
        'tipo': tipo,
        'remuneracao_anterior': remuneracaoAnterior,
        'remuneracao_nova': remuneracaoNova,
        'encargos_anteriores': encargosAnteriores,
        'encargos_novos': encargosNovos,
        'outros_custos_anteriores': outrosCustosAnteriores,
        'outros_custos_novos': outrosCustosNovos,
        'ativo_anterior': ativoAnterior == null
            ? null
            : (ativoAnterior ? 1 : 0),
        'ativo_novo': ativoNovo == null ? null : (ativoNovo ? 1 : 0),
        'motivo': motivo,
        'vigencia_em': vigencia.toIso8601String(),
        'criado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> sincronizarHorasProdutivasEquipe(double horas) async {
    if (horas <= 0) {
      throw ArgumentError('Informe uma carga horária mensal maior que zero.');
    }

    final database = await _appDatabase.database;

    await database.update('financeiro_colaboradores_custo', {
      'horas_produtivas_mes': horas,
      'atualizado_em': DateTime.now().toIso8601String(),
    }, where: 'ativo = 1');
  }

  Future<Map<String, double>> obterResumoEstruturaCustos() async {
    final database = await _appDatabase.database;

    final fixos = await database.rawQuery('''
      SELECT COALESCE(SUM(valor_mensal), 0) AS total
      FROM financeiro_custos_fixos
      WHERE ativo = 1
    ''');

    final maoObra = await database.rawQuery('''
      SELECT
        COALESCE(SUM(
          remuneracao_mensal + encargos_mensais + outros_custos_mensais
        ), 0) AS custo_mensal,
        COALESCE(MAX(horas_produtivas_mes), 0) AS horas_equipe_fallback
      FROM financeiro_colaboradores_custo
      WHERE ativo = 1
    ''');

    final custoFixoMensal = _double(fixos.first['total']);
    final custoMaoObraMensal = _double(maoObra.first['custo_mensal']);

    // custos-base-220-v2
    // 220h representam a capacidade mensal atual da empresa.
    // Nao multiplicar 220 pela quantidade de colaboradores.
    const horasProdutivas = ImperiumRegrasNegocio.horasMensaisPadrao;

    final custoMaoObraHora = horasProdutivas > 0
        ? custoMaoObraMensal / horasProdutivas
        : 0.0;

    final custoFixoHora = horasProdutivas > 0
        ? custoFixoMensal / horasProdutivas
        : 0.0;

    return {
      'custo_fixo_mensal': custoFixoMensal,
      'custo_mao_obra_mensal': custoMaoObraMensal,
      'horas_produtivas': horasProdutivas,
      'horas_equipe_mes': horasProdutivas,
      'custo_mao_obra_hora': custoMaoObraHora,
      'custo_fixo_hora': custoFixoHora,
      'custo_estrutura_hora': custoMaoObraHora + custoFixoHora,
    };
  }

  Future<List<Map<String, dynamic>>> listarCustosEstimadosServicos() async {
    final database = await _appDatabase.database;
    final resumo = await obterResumoEstruturaCustos();
    final custoMaoObraHora = resumo['custo_mao_obra_hora'] ?? 0;
    final custoFixoHora = resumo['custo_fixo_hora'] ?? 0;

    final resultado = await database.rawQuery('''
      SELECT
        s.id,
        s.nome,
        s.categoria,
        s.preco_padrao,
        s.preco_minimo,
        s.preco_maximo,
        s.duracao_minutos,
        COALESCE(SUM(
          sp.quantidade_padrao *
          CASE
            WHEN COALESCE(e.custo_unitario_calculado, 0) > 0
              THEN e.custo_unitario_calculado
            ELSE COALESCE(e.custo_unitario, 0)
          END
        ), 0) AS custo_produtos_estimado
      FROM servicos_catalogo s
      LEFT JOIN servico_produtos sp ON sp.servico_id = s.id
      LEFT JOIN itens_estoque e ON e.id = sp.item_estoque_id
      WHERE s.ativo = 1
      GROUP BY s.id
      ORDER BY s.nome COLLATE NOCASE ASC
    ''');

    return resultado.map((item) {
      final mapa = Map<String, dynamic>.from(item);
      final minutos = _double(mapa['duracao_minutos']);
      final horas = minutos / 60;
      final produtos = _double(mapa['custo_produtos_estimado']);
      final maoObra = horas * custoMaoObraHora;
      final fixo = horas * custoFixoHora;
      final custoTotal = produtos + maoObra + fixo;
      final preco = _double(mapa['preco_padrao']);
      final resultadoEstimado = preco - custoTotal;
      final margem = preco > 0 ? (resultadoEstimado / preco) * 100 : 0.0;

      mapa['horas_estimadas'] = horas;
      mapa['custo_mao_obra_estimado'] = maoObra;
      mapa['custo_fixo_rateado_estimado'] = fixo;
      mapa['custo_total_estimado'] = custoTotal;
      mapa['resultado_estimado'] = resultadoEstimado;
      mapa['margem_estimada'] = margem;
      return mapa;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listarResultadoOrdens() async {
    final database = await _appDatabase.database;
    final resumo = await obterResumoEstruturaCustos();
    final custoFixoHora = resumo['custo_fixo_hora'] ?? 0;

    final resultado = await database.rawQuery('''
      SELECT
        os.id,
        os.numero,
        os.data_finalizacao,
        os.valor_total,
        os.desconto,
        os.desconto_negociacao,
        os.acrescimo_negociacao,
        os.juros_parcelamento,
        os.valor_recebido,
        os.status_pagamento,
        c.nome AS cliente_nome,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa,
        COALESCE((
          SELECT SUM(p.custo_total_no_momento)
          FROM ordem_servico_produtos p
          WHERE p.ordem_servico_id = os.id
        ), 0) AS custo_produtos,
        COALESCE((
          SELECT SUM(pag.taxa_operacao)
          FROM ordem_servico_pagamentos pag
          WHERE pag.ordem_servico_id = os.id
            AND pag.status IN ('Pago', 'Estornado')
        ), 0) AS taxas_pagamento,
        COALESCE((
          SELECT SUM(mo.custo_total)
          FROM financeiro_os_mao_obra mo
          WHERE mo.ordem_servico_id = os.id
            AND mo.ativo = 1
        ), 0) AS custo_mao_obra,
        COALESCE((
          SELECT SUM(mo.horas)
          FROM financeiro_os_mao_obra mo
          WHERE mo.ordem_servico_id = os.id
            AND mo.ativo = 1
        ), 0) AS horas_mao_obra
      FROM ordens_servico os
      INNER JOIN clientes c ON c.id = os.cliente_id
      LEFT JOIN veiculos v ON v.id = os.veiculo_id
      WHERE os.status = 'Finalizada'
      ORDER BY COALESCE(os.data_finalizacao, os.data_abertura) DESC, os.id DESC
    ''');

    return resultado.map((item) {
      final mapa = Map<String, dynamic>.from(item);
      final valorNegociado = _valorNegociado(mapa);
      final produtos = _double(mapa['custo_produtos']);
      final taxas = _double(mapa['taxas_pagamento']);
      final maoObra = _double(mapa['custo_mao_obra']);
      final horas = _double(mapa['horas_mao_obra']);
      final rateioFixo = horas * custoFixoHora;
      final custoTotal = produtos + taxas + maoObra + rateioFixo;
      final resultadoOs = valorNegociado - custoTotal;
      final margem = valorNegociado > 0
          ? (resultadoOs / valorNegociado) * 100
          : 0.0;

      mapa['valor_negociado'] = valorNegociado;
      mapa['rateio_custo_fixo'] = rateioFixo;
      mapa['custo_total'] = custoTotal;
      mapa['resultado_os'] = resultadoOs;
      mapa['margem_os'] = margem;
      return mapa;
    }).toList();
  }

  Future<Map<String, dynamic>?> obterResultadoOrdem(int ordemServicoId) async {
    final ordens = await listarResultadoOrdens();
    for (final ordem in ordens) {
      if (_int(ordem['id']) == ordemServicoId) {
        final mapa = Map<String, dynamic>.from(ordem);
        mapa['mao_obra_lancamentos'] = await listarMaoObraOrdem(ordemServicoId);
        return mapa;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listarMaoObraOrdem(
    int ordemServicoId,
  ) async {
    final database = await _appDatabase.database;
    return database.rawQuery(
      '''
      SELECT
        mo.*,
        c.nome AS colaborador_nome,
        c.funcao AS colaborador_funcao
      FROM financeiro_os_mao_obra mo
      LEFT JOIN financeiro_colaboradores_custo c
        ON c.id = mo.colaborador_custo_id
      WHERE mo.ordem_servico_id = ?
        AND mo.ativo = 1
      ORDER BY mo.data ASC, mo.id ASC
      ''',
      [ordemServicoId],
    );
  }

  Future<int> registrarMaoObraOrdem({
    required int ordemServicoId,
    int? colaboradorId,
    required double horas,
    double? custoHoraManual,
    String descricao = '',
    String observacoes = '',
    DateTime? data,
  }) async {
    if (horas <= 0) {
      throw ArgumentError('Informe uma quantidade de horas maior que zero.');
    }

    final database = await _appDatabase.database;
    double custoHora = custoHoraManual ?? 0;
    String descricaoFinal = descricao.trim();

    if (colaboradorId != null) {
      final resultado = await database.query(
        'financeiro_colaboradores_custo',
        where: 'id = ? AND ativo = 1',
        whereArgs: [colaboradorId],
        limit: 1,
      );
      if (resultado.isEmpty) {
        throw StateError('Colaborador de custo não encontrado.');
      }
      final colaborador = ColaboradorCusto.fromMap(
        Map<String, dynamic>.from(resultado.first),
      );
      custoHora = colaborador.custoHoraProdutiva;
      if (descricaoFinal.isEmpty) {
        descricaoFinal = colaborador.nome;
      }
    }

    if (custoHora < 0) {
      throw ArgumentError('O custo por hora não pode ser negativo.');
    }

    final ordem = await database.query(
      'ordens_servico',
      columns: ['id', 'status'],
      where: 'id = ?',
      whereArgs: [ordemServicoId],
      limit: 1,
    );
    if (ordem.isEmpty) {
      throw StateError('Ordem de Serviço não encontrada.');
    }
    if ((ordem.first['status'] ?? '').toString() != 'Finalizada') {
      throw StateError(
        'A mão de obra de resultado deve ser vinculada a uma OS finalizada.',
      );
    }

    final agora = DateTime.now().toIso8601String();
    return database.insert('financeiro_os_mao_obra', {
      'ordem_servico_id': ordemServicoId,
      'colaborador_custo_id': colaboradorId,
      'descricao': descricaoFinal,
      'horas': horas,
      'custo_hora_snapshot': custoHora,
      'custo_total': horas * custoHora,
      'data': (data ?? DateTime.now()).toIso8601String(),
      'observacoes': observacoes.trim(),
      'ativo': 1,
      'cancelado_em': null,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> cancelarMaoObraOrdem(int id) async {
    final database = await _appDatabase.database;
    final agora = DateTime.now().toIso8601String();
    await database.update(
      'financeiro_os_mao_obra',
      {'ativo': 0, 'cancelado_em': agora, 'atualizado_em': agora},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static const String _origemPagamentoColaborador = 'Pagamento de funcionário';
  static const String _marcadorMaoObraAutomatica = 'AUTO_OS_FINALIZACAO';

  Future<void> _garantirTabelaPagamentosColaboradores(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_pagamentos_colaboradores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        colaborador_id INTEGER NOT NULL,
        movimento_financeiro_id INTEGER,
        valor REAL NOT NULL,
        conta_id INTEGER NOT NULL,
        data_pagamento TEXT NOT NULL,
        forma_pagamento TEXT NOT NULL DEFAULT '',
        observacoes TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE RESTRICT,
        FOREIGN KEY (movimento_financeiro_id)
          REFERENCES movimentos_financeiros (id)
          ON DELETE SET NULL,
        FOREIGN KEY (conta_id)
          REFERENCES financeiro_contas (id)
          ON DELETE RESTRICT
      )
    ''');

    await executor.execute('''
      CREATE INDEX IF NOT EXISTS
      idx_fin_pag_colaborador_data
      ON financeiro_pagamentos_colaboradores (
        colaborador_id,
        data_pagamento
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> listarPagamentosColaboradores({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _appDatabase.database;
    await _garantirTabelaPagamentosColaboradores(database);

    final inicioDia = _dataDia(inicio);
    final fimDia = _dataDia(fim);

    return database.rawQuery(
      '''
      SELECT
        p.*,
        c.nome AS colaborador_nome,
        fc.nome AS conta_nome,
        m.status AS movimento_status
      FROM financeiro_pagamentos_colaboradores p
      INNER JOIN financeiro_colaboradores_custo c
        ON c.id = p.colaborador_id
      LEFT JOIN financeiro_contas fc
        ON fc.id = p.conta_id
      LEFT JOIN movimentos_financeiros m
        ON m.id = p.movimento_financeiro_id
      WHERE date(p.data_pagamento) BETWEEN date(?) AND date(?)
      ORDER BY p.data_pagamento DESC, p.id DESC
      ''',
      [inicioDia, fimDia],
    );
  }

  Future<int> registrarPagamentoColaborador({
    required int colaboradorId,
    required double valor,
    required int contaId,
    required DateTime dataPagamento,
    required String formaPagamento,
    String observacoes = '',
  }) async {
    if (valor <= 0) {
      throw ArgumentError('O valor do pagamento deve ser maior que zero.');
    }

    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
      await _garantirTabelaPagamentosColaboradores(transaction);

      final colaborador = await transaction.query(
        'financeiro_colaboradores_custo',
        columns: ['id', 'nome', 'ativo'],
        where: 'id = ?',
        whereArgs: [colaboradorId],
        limit: 1,
      );

      if (colaborador.isEmpty) {
        throw StateError('Funcionário não encontrado.');
      }

      final conta = await transaction.query(
        'financeiro_contas',
        columns: ['id', 'ativo'],
        where: 'id = ?',
        whereArgs: [contaId],
        limit: 1,
      );

      if (conta.isEmpty) {
        throw StateError('Conta financeira não encontrada.');
      }

      if (_int(conta.first['ativo']) != 1) {
        throw StateError('A conta financeira selecionada está inativa.');
      }

      final plano = await transaction.query(
        'financeiro_plano_contas',
        columns: ['id'],
        where: 'codigo = ?',
        whereArgs: ['2.01.01'],
        limit: 1,
      );
      final planoContaId = plano.isEmpty ? null : _int(plano.first['id']);

      final nome = (colaborador.first['nome'] ?? 'Funcionário')
          .toString()
          .trim();
      final dataIso = dataPagamento.toIso8601String();
      final agora = DateTime.now().toIso8601String();
      final forma = formaPagamento.trim().isEmpty
          ? 'Não informado'
          : formaPagamento.trim();

      final movimentoId = await transaction.insert('movimentos_financeiros', {
        'tipo': 'saída',
        'descricao': 'Pagamento de funcionário - $nome',
        'valor': valor,
        'forma_pagamento': forma,
        'data': dataIso,
        'cliente_id': null,
        'agendamento_id': null,
        'ordem_servico_id': null,
        'pagamento_id': null,
        'plano_conta_id': planoContaId,
        'conta_id': contaId,
        'fornecedor_id': null,
        'transferencia_id': null,
        'natureza': 'Mão de obra',
        'origem': _origemPagamentoColaborador,
        'status': 'Realizado',
        'data_competencia': dataIso,
        'data_vencimento': null,
        'data_pagamento': dataIso,
        'numero_documento': '',
        'observacoes': observacoes.trim(),
        'impacta_dre': 1,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      return transaction.insert(
        'financeiro_pagamentos_colaboradores',
        {
          'colaborador_id': colaboradorId,
          'movimento_financeiro_id': movimentoId,
          'valor': valor,
          'conta_id': contaId,
          'data_pagamento': dataIso,
          'forma_pagamento': forma,
          'observacoes': observacoes.trim(),
          'criado_em': agora,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  Future<void> excluirPagamentoColaborador(int id) async {
    final database = await _appDatabase.database;

    await database.transaction((transaction) async {
      await _garantirTabelaPagamentosColaboradores(transaction);

      final pagamento = await transaction.query(
        'financeiro_pagamentos_colaboradores',
        columns: ['id', 'movimento_financeiro_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (pagamento.isEmpty) {
        throw StateError('Pagamento de funcionário não encontrado.');
      }

      final movimentoId = _int(pagamento.first['movimento_financeiro_id']);

      await transaction.delete(
        'financeiro_pagamentos_colaboradores',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (movimentoId != null) {
        await transaction.delete(
          'movimentos_financeiros',
          where: 'id = ? AND origem = ?',
          whereArgs: [movimentoId, _origemPagamentoColaborador],
        );
      }
    });
  }

  Future<int?> _buscarColaboradorPorNome(
    DatabaseExecutor executor,
    String nome,
  ) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.isEmpty) {
      return null;
    }

    final resultado = await executor.rawQuery(
      '''
      SELECT id
      FROM financeiro_colaboradores_custo
      WHERE ativo = 1
        AND LOWER(TRIM(nome)) = LOWER(TRIM(?))
      ORDER BY id ASC
      LIMIT 1
      ''',
      [nomeLimpo],
    );

    if (resultado.isEmpty) {
      return null;
    }

    return _int(resultado.first['id']);
  }

  Future<double> _custoMaoObraEquipeHora(DatabaseExecutor executor) async {
    final maoObra = await executor.rawQuery('''
      SELECT
        COALESCE(SUM(
          remuneracao_mensal + encargos_mensais + outros_custos_mensais
        ), 0) AS custo_mensal,
        COALESCE(MAX(horas_produtivas_mes), 0) AS horas_equipe_fallback
      FROM financeiro_colaboradores_custo
      WHERE ativo = 1
      ''');

    var horasEquipe = 0.0;

    final tabelaConfig = await executor.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = 'financeiro_precificacao_config'
      LIMIT 1
      ''');

    if (tabelaConfig.isNotEmpty) {
      final config = await executor.rawQuery('''
        SELECT COALESCE(horas_produtivas_mes, 0) AS horas
        FROM financeiro_precificacao_config
        WHERE id = 1
        LIMIT 1
        ''');

      if (config.isNotEmpty) {
        horasEquipe = _double(config.first['horas']);
      }
    }

    if (horasEquipe <= 0) {
      horasEquipe = _double(maoObra.first['horas_equipe_fallback']);
    }

    final custoMensal = _double(maoObra.first['custo_mensal']);
    return horasEquipe > 0 ? custoMensal / horasEquipe : 0.0;
  }

  double _horasEntre(DateTime entrada, DateTime saida) {
    if (saida.isBefore(entrada)) {
      throw ArgumentError(
        'A saída não pode ser anterior à entrada para calcular mão de obra.',
      );
    }

    return saida.difference(entrada).inMinutes / 60.0;
  }

  Future<void> registrarMaoObraAutomaticaComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String colaboradorNome,
    required DateTime entrada,
    required DateTime saida,
  }) async {
    final horas = _horasEntre(entrada, saida);
    if (horas <= 0) {
      return;
    }

    final custoHora = await _custoMaoObraEquipeHora(transaction);
    final colaboradorId = await _buscarColaboradorPorNome(
      transaction,
      colaboradorNome,
    );
    final agora = DateTime.now().toIso8601String();
    final nome = colaboradorNome.trim().isEmpty
        ? 'Responsável não informado'
        : colaboradorNome.trim();

    await transaction.insert('financeiro_os_mao_obra', {
      'ordem_servico_id': ordemServicoId,
      'colaborador_custo_id': colaboradorId,
      'descricao': nome,
      'horas': horas,
      'custo_hora_snapshot': custoHora,
      'custo_total': horas * custoHora,
      'data': saida.toIso8601String(),
      'observacoes': _marcadorMaoObraAutomatica,
      'ativo': 1,
      'cancelado_em': null,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> recalcularMaoObraAutomaticaComTransacao(
    Transaction transaction, {
    required int ordemServicoId,
    required String colaboradorNome,
    required DateTime entrada,
    required DateTime saida,
  }) async {
    final horas = _horasEntre(entrada, saida);
    final custoHora = await _custoMaoObraEquipeHora(transaction);
    final colaboradorId = await _buscarColaboradorPorNome(
      transaction,
      colaboradorNome,
    );
    final agora = DateTime.now().toIso8601String();
    final nome = colaboradorNome.trim().isEmpty
        ? 'Responsável não informado'
        : colaboradorNome.trim();

    final existentes = await transaction.query(
      'financeiro_os_mao_obra',
      columns: ['id'],
      where: 'ordem_servico_id = ? AND ativo = 1 AND observacoes = ?',
      whereArgs: [ordemServicoId, _marcadorMaoObraAutomatica],
      orderBy: 'id ASC',
    );

    if (horas <= 0) {
      if (existentes.isNotEmpty) {
        await transaction.update(
          'financeiro_os_mao_obra',
          {'ativo': 0, 'cancelado_em': agora, 'atualizado_em': agora},
          where: 'ordem_servico_id = ? AND ativo = 1 AND observacoes = ?',
          whereArgs: [ordemServicoId, _marcadorMaoObraAutomatica],
        );
      }
      return;
    }

    if (existentes.isEmpty) {
      await registrarMaoObraAutomaticaComTransacao(
        transaction,
        ordemServicoId: ordemServicoId,
        colaboradorNome: colaboradorNome,
        entrada: entrada,
        saida: saida,
      );
      return;
    }

    final idPrincipal = _int(existentes.first['id']);
    if (idPrincipal == null) {
      return;
    }

    await transaction.update(
      'financeiro_os_mao_obra',
      {
        'colaborador_custo_id': colaboradorId,
        'descricao': nome,
        'horas': horas,
        'custo_hora_snapshot': custoHora,
        'custo_total': horas * custoHora,
        'data': saida.toIso8601String(),
        'atualizado_em': agora,
      },
      where: 'id = ?',
      whereArgs: [idPrincipal],
    );

    if (existentes.length > 1) {
      final idsExtras = existentes
          .skip(1)
          .map((item) => _int(item['id']))
          .whereType<int>()
          .toList();

      for (final id in idsExtras) {
        await transaction.update(
          'financeiro_os_mao_obra',
          {'ativo': 0, 'cancelado_em': agora, 'atualizado_em': agora},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  static String _dataDia(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  double _valorNegociado(Map<String, dynamic> ordem) {
    return OrdemServicoValor.valorNegociadoDeMapa(ordem);
  }

  static int? _int(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double _double(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
