import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class PrecificacaoConfig {
  const PrecificacaoConfig({
    required this.horasProdutivasMes,
    required this.mesesMedia,
    required this.margemCliente,
    required this.margemRevenda,
    required this.margemMinima,
    this.margemRevenda1a4 = 25,
    this.margemRevenda5a9 = 20,
    this.margemRevenda10Mais = 16,
  });

  final double horasProdutivasMes;
  final int mesesMedia;
  final double margemCliente;

  /// Mantido por compatibilidade com as telas/rotinas anteriores.
  /// Representa a faixa intermediária de revenda (5 a 9 serviços/mês).
  final double margemRevenda;

  final double margemMinima;
  final double margemRevenda1a4;
  final double margemRevenda5a9;
  final double margemRevenda10Mais;
}

class PrecificacaoResumo {
  const PrecificacaoResumo({
    required this.inicioHistorico,
    required this.fimHistorico,
    required this.mesesConsiderados,
    required this.mediaMensalReal,
    required this.estruturaCadastrada,
    required this.baseMensalUsada,
    required this.custoHora,
    required this.taxaCartaoMediaPercentual,
    required this.usouHistoricoFinanceiro,
  });

  final DateTime inicioHistorico;
  final DateTime fimHistorico;
  final int mesesConsiderados;
  final double mediaMensalReal;
  final double estruturaCadastrada;
  final double baseMensalUsada;
  final double custoHora;
  final double taxaCartaoMediaPercentual;
  final bool usouHistoricoFinanceiro;
}

class PrecificacaoServico {
  const PrecificacaoServico({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.precoAtual,
    required this.tempoPrecificacaoMinutos,
    required this.tempoMedioRealMinutos,
    required this.amostrasTempoReal,
    required this.custoProdutos,
    required this.custoEstrutura,
    required this.custoBase,
    required this.precoEquilibrio,
    required this.precoMinimoSeguro,
    required this.precoSugerido,
    required this.precoRevendaSugerido,
    this.precoRevenda1a4 = 0,
    this.precoRevenda5a9 = 0,
    this.precoRevenda10Mais = 0,
    required this.margemAtual,
    required this.aceitaRevenda,
  });

  final int id;
  final String nome;
  final String categoria;
  final double precoAtual;
  final double tempoPrecificacaoMinutos;
  final double? tempoMedioRealMinutos;
  final int amostrasTempoReal;
  final double custoProdutos;
  final double custoEstrutura;
  final double custoBase;
  final double precoEquilibrio;
  final double precoMinimoSeguro;
  final double precoSugerido;

  /// Compatibilidade: continua representando a faixa intermediária 5–9.
  final double precoRevendaSugerido;

  final double precoRevenda1a4;
  final double precoRevenda5a9;
  final double precoRevenda10Mais;
  final double margemAtual;
  final bool aceitaRevenda;

  double get diferencaSugerida => precoSugerido - precoAtual;

  double get variacaoPercentual {
    if (precoAtual <= 0) return 0;
    return diferencaSugerida / precoAtual * 100;
  }
}

class PrecificacaoPainel {
  const PrecificacaoPainel({
    required this.config,
    required this.resumo,
    required this.servicos,
  });

  final PrecificacaoConfig config;
  final PrecificacaoResumo resumo;
  final List<PrecificacaoServico> servicos;
}

class PrecificacaoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<void> _garantirEstrutura(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_precificacao_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        horas_produtivas_mes REAL NOT NULL DEFAULT 160,
        meses_media INTEGER NOT NULL DEFAULT 3,
        margem_cliente REAL NOT NULL DEFAULT 35,
        margem_revenda REAL NOT NULL DEFAULT 20,
        margem_minima REAL NOT NULL DEFAULT 10,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await database.rawInsert(
      '''
      INSERT OR IGNORE INTO financeiro_precificacao_config (
        id,
        horas_produtivas_mes,
        meses_media,
        margem_cliente,
        margem_revenda,
        margem_minima,
        atualizado_em
      ) VALUES (1, 160, 3, 35, 20, 10, ?)
      ''',
      [DateTime.now().toIso8601String()],
    );

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_precificacao_servicos (
        servico_id INTEGER PRIMARY KEY,
        tempo_precificacao_minutos REAL,
        aceita_revenda INTEGER NOT NULL DEFAULT 0,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (servico_id)
          REFERENCES servicos_catalogo (id)
          ON DELETE CASCADE,
        CHECK (aceita_revenda IN (0, 1))
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_preco_documentos (
        documento_tipo TEXT NOT NULL,
        documento_id INTEGER NOT NULL,
        perfil TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (documento_tipo, documento_id)
      )
    ''');

    final adicionou1a4 = await _garantirColuna(
      database,
      tabela: 'financeiro_precificacao_config',
      coluna: 'margem_revenda_1_4',
      definicao: 'REAL NOT NULL DEFAULT 25',
    );
    final adicionou5a9 = await _garantirColuna(
      database,
      tabela: 'financeiro_precificacao_config',
      coluna: 'margem_revenda_5_9',
      definicao: 'REAL NOT NULL DEFAULT 20',
    );
    final adicionou10Mais = await _garantirColuna(
      database,
      tabela: 'financeiro_precificacao_config',
      coluna: 'margem_revenda_10_mais',
      definicao: 'REAL NOT NULL DEFAULT 16',
    );

    // Ao abrir um banco que já usava a margem única de revenda, transforma
    // essa margem antiga na faixa intermediária e cria faixas coerentes ao
    // redor dela. Isso preserva a configuração que o usuário já possuía.
    if (adicionou1a4 || adicionou5a9 || adicionou10Mais) {
      await database.rawUpdate('''
        UPDATE financeiro_precificacao_config
        SET
          margem_revenda_5_9 = MIN(
            margem_cliente,
            MAX(margem_minima, margem_revenda)
          ),
          margem_revenda_1_4 = MIN(
            margem_cliente,
            MAX(margem_minima, margem_revenda + 5)
          ),
          margem_revenda_10_mais = MAX(
            margem_minima,
            MIN(margem_cliente, margem_revenda - 4)
          )
        WHERE id = 1
        ''');
    }
  }

  Future<bool> _garantirColuna(
    Database database, {
    required String tabela,
    required String coluna,
    required String definicao,
  }) async {
    final colunas = await database.rawQuery('PRAGMA table_info($tabela)');
    final existe = colunas.any(
      (item) => (item['name'] ?? '').toString() == coluna,
    );

    if (existe) {
      return false;
    }

    await database.execute('ALTER TABLE $tabela ADD COLUMN $coluna $definicao');
    return true;
  }

  Future<PrecificacaoConfig> carregarConfig() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_precificacao_config',
      where: 'id = 1',
      limit: 1,
    );

    final item = resultado.first;
    final margem5a9 = _double(
      item['margem_revenda_5_9'],
      _double(item['margem_revenda'], 20),
    );

    return PrecificacaoConfig(
      horasProdutivasMes: _double(item['horas_produtivas_mes'], 160),
      mesesMedia: _int(item['meses_media'], 3).clamp(1, 12).toInt(),
      margemCliente: _double(item['margem_cliente'], 35),
      margemRevenda: margem5a9,
      margemMinima: _double(item['margem_minima'], 10),
      margemRevenda1a4: _double(item['margem_revenda_1_4'], 25),
      margemRevenda5a9: margem5a9,
      margemRevenda10Mais: _double(item['margem_revenda_10_mais'], 16),
    );
  }

  Future<void> salvarConfig(PrecificacaoConfig config) async {
    if (config.horasProdutivasMes <= 0) {
      throw ArgumentError(
        'Informe uma quantidade de horas produtivas maior que zero.',
      );
    }
    if (config.mesesMedia < 1 || config.mesesMedia > 12) {
      throw ArgumentError('A média deve considerar entre 1 e 12 meses.');
    }

    for (final margem in <double>[
      config.margemCliente,
      config.margemRevenda1a4,
      config.margemRevenda5a9,
      config.margemRevenda10Mais,
      config.margemMinima,
    ]) {
      if (margem < 0 || margem >= 95) {
        throw ArgumentError('As margens devem ficar entre 0% e 94,9%.');
      }
    }

    if (config.margemRevenda1a4 > config.margemCliente + 0.000001) {
      throw ArgumentError(
        'A margem de revenda de 1 a 4 serviços não pode superar '
        'a margem do cliente final.',
      );
    }

    if (config.margemRevenda1a4 + 0.000001 < config.margemRevenda5a9 ||
        config.margemRevenda5a9 + 0.000001 < config.margemRevenda10Mais) {
      throw ArgumentError(
        'As margens de revenda devem diminuir conforme o volume aumenta.',
      );
    }

    if (config.margemRevenda10Mais + 0.000001 < config.margemMinima) {
      throw ArgumentError(
        'A margem da faixa 10+ não pode ficar abaixo da margem mínima segura.',
      );
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    await database.update('financeiro_precificacao_config', {
      'horas_produtivas_mes': config.horasProdutivasMes,
      'meses_media': config.mesesMedia,
      'margem_cliente': config.margemCliente,
      // A coluna antiga continua sincronizada com a faixa 5–9 para
      // manter compatibilidade com qualquer tela ainda não atualizada.
      'margem_revenda': config.margemRevenda5a9,
      'margem_revenda_1_4': config.margemRevenda1a4,
      'margem_revenda_5_9': config.margemRevenda5a9,
      'margem_revenda_10_mais': config.margemRevenda10Mais,
      'margem_minima': config.margemMinima,
      'atualizado_em': DateTime.now().toIso8601String(),
    }, where: 'id = 1');
  }

  Future<void> registrarPerfilDocumento({
    required String documentoTipo,
    required int documentoId,
    required String perfil,
  }) async {
    final tipo = documentoTipo.trim().toUpperCase();
    final perfilLimpo = perfil.trim();

    if (tipo.isEmpty || documentoId <= 0 || perfilLimpo.isEmpty) {
      throw ArgumentError('Contexto de preço do documento inválido.');
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);
    final agora = DateTime.now().toIso8601String();

    await database.insert('financeiro_preco_documentos', {
      'documento_tipo': tipo,
      'documento_id': documentoId,
      'perfil': perfilLimpo,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> buscarPerfilDocumento({
    required String documentoTipo,
    required int documentoId,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_preco_documentos',
      columns: ['perfil'],
      where: 'documento_tipo = ? AND documento_id = ?',
      whereArgs: [documentoTipo.trim().toUpperCase(), documentoId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    final valor = (resultado.first['perfil'] ?? '').toString().trim();
    return valor.isEmpty ? null : valor;
  }

  Future<void> salvarPreferenciasServico({
    required int servicoId,
    required double tempoPrecificacaoMinutos,
    required bool aceitaRevenda,
  }) async {
    if (tempoPrecificacaoMinutos <= 0) {
      throw ArgumentError('Informe um tempo de execução maior que zero.');
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    await database.insert(
      'financeiro_precificacao_servicos',
      {
        'servico_id': servicoId,
        'tempo_precificacao_minutos': tempoPrecificacaoMinutos,
        'aceita_revenda': aceitaRevenda ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> aplicarPrecoPadrao({
    required int servicoId,
    required double preco,
  }) async {
    if (preco <= 0) {
      throw ArgumentError('O preço sugerido precisa ser maior que zero.');
    }

    final database = await _appDatabase.database;
    await database.update(
      'servicos_catalogo',
      {
        'preco_padrao': preco,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [servicoId],
    );
  }

  Future<PrecificacaoPainel> carregar() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final config = await carregarConfig();
    final periodo = _periodoMesesCompletos(config.mesesMedia);

    final resumo = await _carregarResumo(
      database: database,
      config: config,
      inicio: periodo.$1,
      fim: periodo.$2,
    );

    final servicos = await _carregarServicos(
      database: database,
      config: config,
      resumo: resumo,
      inicio: periodo.$1,
      fim: periodo.$2,
    );

    return PrecificacaoPainel(
      config: config,
      resumo: resumo,
      servicos: servicos,
    );
  }

  Future<PrecificacaoResumo> _carregarResumo({
    required Database database,
    required PrecificacaoConfig config,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final historico = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(m.valor), 0) AS total
      FROM movimentos_financeiros m
      LEFT JOIN financeiro_plano_contas pc ON pc.id = m.plano_conta_id
      WHERE m.status = 'Realizado'
        AND m.transferencia_id IS NULL
        AND COALESCE(m.impacta_dre, 1) = 1
        AND LOWER(m.tipo) IN ('saída', 'saida')
        AND date(COALESCE(m.data_pagamento, m.data))
          BETWEEN date(?) AND date(?)
        AND COALESCE(pc.grupo_dre, 'Não DRE') != 'Não DRE'
        AND COALESCE(pc.codigo, '') NOT IN ('2.02.01', '2.03.01')
        AND NOT (
          LOWER(COALESCE(m.origem, '')) = 'taxa de pagamento'
          OR LOWER(COALESCE(m.descricao, '')) LIKE 'taxa da maquininha%'
        )
        AND NOT EXISTS (
          SELECT 1
          FROM ordem_servico_pagamentos pcor
          WHERE pcor.id = m.pagamento_id
            AND pcor.status = 'Estornado'
            AND NOT EXISTS (
              SELECT 1
              FROM movimentos_financeiros devolucao
              WHERE devolucao.pagamento_id = pcor.id
                AND devolucao.status = 'Realizado'
                AND LOWER(COALESCE(devolucao.origem, '')) =
                    'devolução ao cliente'
            )
        )
      ''',
      [_data(inicio), _data(fim)],
    );

    final estrutura = await database.rawQuery('''
      SELECT
        (
          SELECT COALESCE(SUM(valor_mensal), 0)
          FROM financeiro_custos_fixos
          WHERE ativo = 1
        ) +
        (
          SELECT COALESCE(SUM(
            remuneracao_mensal +
            encargos_mensais +
            outros_custos_mensais
          ), 0)
          FROM financeiro_colaboradores_custo
          WHERE ativo = 1
        ) AS total
      ''');

    final taxa = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(taxa_operacao), 0) AS taxas,
        COALESCE(SUM(valor), 0) AS vendas
      FROM ordem_servico_pagamentos
      WHERE status = 'Pago'
        AND COALESCE(valor, 0) > 0
        AND date(COALESCE(data_pagamento, criado_em))
          BETWEEN date(?) AND date(?)
      ''',
      [_data(inicio), _data(fim)],
    );

    final totalHistorico = _double(historico.first['total']);
    final mediaMensalReal = totalHistorico / config.mesesMedia;
    final estruturaCadastrada = _double(estrutura.first['total']);

    final possuiHistorico = mediaMensalReal > 0.000001;
    final usouHistorico =
        possuiHistorico && mediaMensalReal >= estruturaCadastrada;
    final baseMensal = mediaMensalReal > estruturaCadastrada
        ? mediaMensalReal
        : estruturaCadastrada;
    final custoHora = config.horasProdutivasMes > 0
        ? baseMensal / config.horasProdutivasMes
        : 0.0;

    final totalTaxas = _double(taxa.first['taxas']);
    final totalVendas = _double(taxa.first['vendas']);
    final taxaPercentual = totalVendas > 0
        ? (totalTaxas / totalVendas) * 100
        : 0.0;

    return PrecificacaoResumo(
      inicioHistorico: inicio,
      fimHistorico: fim,
      mesesConsiderados: config.mesesMedia,
      mediaMensalReal: mediaMensalReal,
      estruturaCadastrada: estruturaCadastrada,
      baseMensalUsada: baseMensal,
      custoHora: custoHora,
      taxaCartaoMediaPercentual: taxaPercentual,
      usouHistoricoFinanceiro: usouHistorico,
    );
  }

  Future<List<PrecificacaoServico>> _carregarServicos({
    required Database database,
    required PrecificacaoConfig config,
    required PrecificacaoResumo resumo,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final resultado = await database.rawQuery(
      '''
      WITH itens_unicos AS (
        SELECT DISTINCT
          ordem_servico_id,
          LOWER(TRIM(servico)) AS servico_chave
        FROM ordem_servico_itens
        WHERE TRIM(COALESCE(servico, '')) != ''
      ),
      quantidade_servicos AS (
        SELECT
          ordem_servico_id,
          COUNT(*) AS quantidade
        FROM itens_unicos
        GROUP BY ordem_servico_id
      ),
      tempos AS (
        SELECT
          i.servico_chave AS servico_chave,
          AVG(
            (
              julianday(
                date(os.data_finalizacao) || ' ' || os.hora_saida
              ) -
              julianday(
                date(COALESCE(os.data_inicio, os.data_abertura)) ||
                ' ' || os.hora_entrada
              )
            ) * 24.0 * 60.0
          ) AS tempo_medio_real_minutos,
          COUNT(*) AS amostras
        FROM itens_unicos i
        INNER JOIN quantidade_servicos q
          ON q.ordem_servico_id = i.ordem_servico_id
        INNER JOIN ordens_servico os
          ON os.id = i.ordem_servico_id
        WHERE q.quantidade = 1
          AND os.status = 'Finalizada'
          AND TRIM(COALESCE(os.hora_entrada, '')) != ''
          AND TRIM(COALESCE(os.hora_saida, '')) != ''
          AND date(COALESCE(os.data_finalizacao, os.data_abertura))
            BETWEEN date(?) AND date(?)
          AND (
            (
              julianday(
                date(os.data_finalizacao) || ' ' || os.hora_saida
              ) -
              julianday(
                date(COALESCE(os.data_inicio, os.data_abertura)) ||
                ' ' || os.hora_entrada
              )
            ) * 24.0 * 60.0
          ) BETWEEN 5 AND 1440
        GROUP BY i.servico_chave
      )
      SELECT
        s.id,
        s.nome,
        s.categoria,
        s.preco_padrao,
        s.duracao_minutos,
        cfg.tempo_precificacao_minutos,
        COALESCE(cfg.aceita_revenda, 0) AS aceita_revenda,
        t.tempo_medio_real_minutos,
        COALESCE(t.amostras, 0) AS amostras_tempo_real,
        COALESCE(SUM(
          sp.quantidade_padrao *
          CASE
            WHEN COALESCE(e.custo_unitario_calculado, 0) > 0
              THEN e.custo_unitario_calculado
            ELSE COALESCE(e.custo_unitario, 0)
          END
        ), 0) AS custo_produtos
      FROM servicos_catalogo s
      LEFT JOIN financeiro_precificacao_servicos cfg
        ON cfg.servico_id = s.id
      LEFT JOIN tempos t
        ON t.servico_chave = LOWER(TRIM(s.nome))
      LEFT JOIN servico_produtos sp
        ON sp.servico_id = s.id
      LEFT JOIN itens_estoque e
        ON e.id = sp.item_estoque_id
      WHERE s.ativo = 1
      GROUP BY s.id
      ORDER BY s.nome COLLATE NOCASE ASC
      ''',
      [_data(inicio), _data(fim)],
    );

    return resultado.map((item) {
      final id = _int(item['id']);
      final precoAtual = _double(item['preco_padrao']);
      final catalogoMinutos = _double(item['duracao_minutos']);
      final configurado = _doubleNullable(item['tempo_precificacao_minutos']);
      final real = _doubleNullable(item['tempo_medio_real_minutos']);
      final amostras = _int(item['amostras_tempo_real']);

      var tempoUsado = configurado;
      if (tempoUsado == null || tempoUsado <= 0) {
        if (real != null && real > 0) {
          tempoUsado = real;
        } else if (catalogoMinutos > 0) {
          tempoUsado = catalogoMinutos;
        } else {
          tempoUsado = 60;
        }
      }

      final produtos = _double(item['custo_produtos']);
      final estrutura = (tempoUsado / 60) * resumo.custoHora;
      final custoBase = produtos + estrutura;

      final taxa = resumo.taxaCartaoMediaPercentual.clamp(0.0, 30.0).toDouble();

      final precoEquilibrio = _precoComMargem(
        custoBase: custoBase,
        margemPercentual: 0,
        taxaPercentual: taxa,
      );
      final precoMinimoSeguro = _precoComMargem(
        custoBase: custoBase,
        margemPercentual: config.margemMinima,
        taxaPercentual: taxa,
      );
      final precoSugerido = _precoComMargem(
        custoBase: custoBase,
        margemPercentual: config.margemCliente,
        taxaPercentual: taxa,
      );
      final precoRevenda1a4 = _precoComMargem(
        custoBase: custoBase,
        margemPercentual: config.margemRevenda1a4,
        taxaPercentual: taxa,
      );
      final precoRevenda5a9 = _precoComMargem(
        custoBase: custoBase,
        margemPercentual: config.margemRevenda5a9,
        taxaPercentual: taxa,
      );
      final precoRevenda10Mais = _precoComMargem(
        custoBase: custoBase,
        margemPercentual: config.margemRevenda10Mais,
        taxaPercentual: taxa,
      );

      final taxaDecimal = taxa / 100;
      final custoTaxaAtual = precoAtual * taxaDecimal;
      final resultadoAtual = precoAtual - custoBase - custoTaxaAtual;
      final margemAtual = precoAtual > 0
          ? resultadoAtual / precoAtual * 100
          : 0.0;

      return PrecificacaoServico(
        id: id,
        nome: (item['nome'] ?? 'Serviço').toString().trim(),
        categoria: (item['categoria'] ?? '').toString().trim(),
        precoAtual: precoAtual,
        tempoPrecificacaoMinutos: tempoUsado,
        tempoMedioRealMinutos: real,
        amostrasTempoReal: amostras,
        custoProdutos: produtos,
        custoEstrutura: estrutura,
        custoBase: custoBase,
        precoEquilibrio: precoEquilibrio,
        precoMinimoSeguro: precoMinimoSeguro,
        precoSugerido: _arredondarPreco(precoSugerido),
        // Compatibilidade: a sugestão antiga passa a representar 5–9.
        precoRevendaSugerido: _arredondarPreco(precoRevenda5a9),
        precoRevenda1a4: _arredondarPreco(precoRevenda1a4),
        precoRevenda5a9: _arredondarPreco(precoRevenda5a9),
        precoRevenda10Mais: _arredondarPreco(precoRevenda10Mais),
        margemAtual: margemAtual,
        aceitaRevenda: _int(item['aceita_revenda']) == 1,
      );
    }).toList();
  }

  static double _precoComMargem({
    required double custoBase,
    required double margemPercentual,
    required double taxaPercentual,
  }) {
    if (custoBase <= 0) return 0;

    final margem = (margemPercentual / 100).clamp(0.0, 0.949).toDouble();
    final taxa = (taxaPercentual / 100).clamp(0.0, 0.30).toDouble();
    final divisor = 1 - margem - taxa;

    if (divisor <= 0.05) {
      return custoBase / 0.05;
    }

    return custoBase / divisor;
  }

  static double _arredondarPreco(double valor) {
    if (valor <= 0) return 0;
    if (valor < 100) {
      return (valor / 5).ceil() * 5.0;
    }
    return (valor / 10).ceil() * 10.0;
  }

  static (DateTime, DateTime) _periodoMesesCompletos(int meses) {
    final agora = DateTime.now();
    final primeiroMesAtual = DateTime(agora.year, agora.month, 1);
    final inicio = DateTime(
      primeiroMesAtual.year,
      primeiroMesAtual.month - meses,
      1,
    );
    final fim = primeiroMesAtual.subtract(const Duration(days: 1));
    return (inicio, fim);
  }

  static String _data(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  static double _double(dynamic valor, [double padrao = 0]) {
    if (valor is num) return valor.toDouble();
    return double.tryParse((valor ?? '').toString().replaceAll(',', '.')) ??
        padrao;
  }

  static double? _doubleNullable(dynamic valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor.toString().replaceAll(',', '.'));
  }

  static int _int(dynamic valor, [int padrao = 0]) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse((valor ?? '').toString()) ?? padrao;
  }
}
