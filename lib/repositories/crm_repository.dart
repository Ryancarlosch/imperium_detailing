import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/crm_campanha.dart';
import '../models/crm_lead.dart';

class CrmResumo {
  const CrmResumo({
    required this.totalAbertos,
    required this.valorPipeline,
    required this.followUpsAtrasados,
    required this.ganhosMes,
    required this.perdidosMes,
    required this.valorGanhosMes,
    required this.porEtapa,
  });

  final int totalAbertos;
  final double valorPipeline;
  final int followUpsAtrasados;
  final int ganhosMes;
  final int perdidosMes;
  final double valorGanhosMes;
  final Map<String, int> porEtapa;

  double get taxaConversaoMes {
    final encerrados = ganhosMes + perdidosMes;
    if (encerrados == 0) {
      return 0;
    }
    return ganhosMes / encerrados * 100;
  }
}

class CrmRepository {
  CrmRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => AppDatabase.instance.database);

  final Future<Database> Function() _databaseProvider;

  Future<List<CrmLead>> listarLeads({
    String? etapa,
    String pesquisa = '',
    bool somenteAbertos = false,
  }) async {
    final database = await _databaseProvider();
    final filtros = <String>[];
    final argumentos = <Object?>[];

    final etapaLimpa = etapa?.trim() ?? '';
    if (etapaLimpa.isNotEmpty && etapaLimpa != 'Todos') {
      filtros.add('etapa = ?');
      argumentos.add(etapaLimpa);
    }
    if (somenteAbertos) {
      filtros.add("etapa NOT IN ('Ganho', 'Perdido')");
    }

    final busca = pesquisa.trim();
    if (busca.isNotEmpty) {
      filtros.add('''(
        nome LIKE ? COLLATE NOCASE
        OR telefone LIKE ? COLLATE NOCASE
        OR email LIKE ? COLLATE NOCASE
        OR servico_interesse LIKE ? COLLATE NOCASE
        OR veiculo_interesse LIKE ? COLLATE NOCASE
      )''');
      final termo = '%$busca%';
      argumentos.addAll([termo, termo, termo, termo, termo]);
    }

    final resultado = await database.query(
      'crm_leads',
      where: filtros.isEmpty ? null : filtros.join(' AND '),
      whereArgs: argumentos.isEmpty ? null : argumentos,
      orderBy:
          "CASE WHEN proximo_contato IS NULL THEN 1 ELSE 0 END, proximo_contato ASC, atualizado_em DESC, id DESC",
    );

    return resultado
        .map((item) => CrmLead.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<CrmLead?> buscarLead(int id) async {
    final database = await _databaseProvider();
    final resultado = await database.query(
      'crm_leads',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (resultado.isEmpty) {
      return null;
    }
    return CrmLead.fromMap(Map<String, dynamic>.from(resultado.first));
  }

  Future<int> salvarLead(CrmLead lead) async {
    final nome = lead.nome.trim();
    if (nome.length < 2) {
      throw ArgumentError('Informe o nome do contato.');
    }
    if (!CrmLead.etapas.contains(lead.etapa)) {
      throw ArgumentError('Etapa do CRM inválida.');
    }
    if (lead.valorPotencial < 0) {
      throw ArgumentError('O valor potencial não pode ser negativo.');
    }
    if (lead.etapa == 'Perdido' && lead.motivoPerda.trim().length < 3) {
      throw ArgumentError('Informe o motivo da perda.');
    }

    final database = await _databaseProvider();
    final agora = DateTime.now().toIso8601String();
    final dados = lead.toMap(incluirId: false)
      ..['nome'] = nome
      ..['telefone'] = lead.telefone.trim()
      ..['email'] = lead.email.trim()
      ..['origem'] = lead.origem.trim().isEmpty ? 'Outro' : lead.origem.trim()
      ..['servico_interesse'] = lead.servicoInteresse.trim()
      ..['veiculo_interesse'] = lead.veiculoInteresse.trim()
      ..['responsavel'] = lead.responsavel.trim()
      ..['observacoes'] = lead.observacoes.trim()
      ..['motivo_perda'] = lead.motivoPerda.trim()
      ..['atualizado_em'] = agora;

    if (lead.id == null) {
      dados['criado_em'] = agora;
      return database.insert(
        'crm_leads',
        dados,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    await database.update(
      'crm_leads',
      dados..remove('criado_em'),
      where: 'id = ?',
      whereArgs: [lead.id],
    );
    return lead.id!;
  }

  Future<void> atualizarEtapa(
    int leadId,
    String etapa, {
    String motivoPerda = '',
  }) async {
    if (!CrmLead.etapas.contains(etapa)) {
      throw ArgumentError('Etapa do CRM inválida.');
    }
    if (etapa == 'Perdido' && motivoPerda.trim().length < 3) {
      throw ArgumentError('Informe o motivo da perda.');
    }

    final database = await _databaseProvider();
    final agora = DateTime.now().toIso8601String();
    await database.transaction<void>((transaction) async {
      final lead = await transaction.query(
        'crm_leads',
        columns: ['id', 'etapa'],
        where: 'id = ?',
        whereArgs: [leadId],
        limit: 1,
      );
      if (lead.isEmpty) {
        throw StateError('Lead não encontrado.');
      }

      await transaction.update(
        'crm_leads',
        {
          'etapa': etapa,
          'motivo_perda': etapa == 'Perdido' ? motivoPerda.trim() : '',
          'convertido_em': {'Ganho', 'Perdido'}.contains(etapa) ? agora : null,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [leadId],
      );

      await transaction.insert('crm_interacoes', {
        'lead_id': leadId,
        'tipo': 'Mudança de etapa',
        'descricao': etapa == 'Perdido'
            ? 'Lead marcado como Perdido: ${motivoPerda.trim()}'
            : 'Lead movido para $etapa',
        'data_interacao': agora,
        'criado_em': agora,
      });
    });
  }

  Future<int> adicionarInteracao({
    required int leadId,
    required String tipo,
    required String descricao,
    DateTime? data,
  }) async {
    final texto = descricao.trim();
    if (texto.length < 2) {
      throw ArgumentError('Descreva o contato realizado.');
    }
    final database = await _databaseProvider();
    final agora = DateTime.now().toIso8601String();
    final momento = (data ?? DateTime.now()).toIso8601String();

    return database.transaction<int>((transaction) async {
      final lead = await transaction.query(
        'crm_leads',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [leadId],
        limit: 1,
      );
      if (lead.isEmpty) {
        throw StateError('Lead não encontrado.');
      }

      final id = await transaction.insert('crm_interacoes', {
        'lead_id': leadId,
        'tipo': tipo.trim().isEmpty ? 'Contato' : tipo.trim(),
        'descricao': texto,
        'data_interacao': momento,
        'criado_em': agora,
      });
      await transaction.update(
        'crm_leads',
        {'atualizado_em': agora},
        where: 'id = ?',
        whereArgs: [leadId],
      );
      return id;
    });
  }

  Future<List<CrmInteracao>> listarInteracoes(int leadId) async {
    final database = await _databaseProvider();
    final resultado = await database.query(
      'crm_interacoes',
      where: 'lead_id = ?',
      whereArgs: [leadId],
      orderBy: 'data_interacao DESC, id DESC',
    );
    return resultado
        .map((item) => CrmInteracao.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<int> converterEmCliente(int leadId) async {
    final database = await _databaseProvider();
    return database.transaction<int>((transaction) async {
      final rows = await transaction.query(
        'crm_leads',
        where: 'id = ?',
        whereArgs: [leadId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Lead não encontrado.');
      }
      final lead = CrmLead.fromMap(Map<String, dynamic>.from(rows.first));
      if (lead.clienteId != null) {
        return lead.clienteId!;
      }

      final telefone = _digitos(lead.telefone);
      final email = lead.email.trim().toLowerCase();
      final existentes = await transaction.rawQuery(
        '''
        SELECT id
        FROM clientes
        WHERE COALESCE(ativo, 1) = 1
          AND (
            (? != '' AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(telefone, ''), '(', ''), ')', ''), '-', ''), ' ', ''), '+', '') = ?)
            OR (? != '' AND LOWER(TRIM(COALESCE(email, ''))) = ?)
          )
        ORDER BY id ASC
        LIMIT 1
        ''',
        [telefone, telefone, email, email],
      );

      int clienteId;
      if (existentes.isNotEmpty) {
        clienteId = (existentes.first['id'] as num).toInt();
      } else {
        clienteId = await transaction.insert('clientes', {
          'nome': lead.nome.trim(),
          'telefone': lead.telefone.trim(),
          'email': lead.email.trim(),
          'endereco': '',
          'observacoes': lead.observacoes.trim().isEmpty
              ? 'Cliente convertido pelo CRM.'
              : 'CRM: ${lead.observacoes.trim()}',
          'data_nascimento': null,
          'ativo': 1,
          'arquivado_em': null,
        });
      }

      await _vincularClienteConvertido(transaction, leadId, clienteId);
      return clienteId;
    });
  }

  Future<void> vincularCliente({
    required int leadId,
    required int clienteId,
  }) async {
    final database = await _databaseProvider();
    final cliente = await database.query(
      'clientes',
      columns: ['id'],
      where: 'id = ? AND COALESCE(ativo, 1) = 1',
      whereArgs: [clienteId],
      limit: 1,
    );
    if (cliente.isEmpty) {
      throw StateError('Cliente não encontrado ou inativo.');
    }
    await database.update(
      'crm_leads',
      {
        'cliente_id': clienteId,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [leadId],
    );
  }

  Future<void> agendarLead({
    required int leadId,
    required int clienteId,
    required int veiculoId,
    required DateTime data,
    required String hora,
    required String servico,
    required double valor,
    String observacoes = '',
  }) async {
    if (servico.trim().isEmpty) {
      throw ArgumentError('Informe o serviço.');
    }
    if (hora.trim().isEmpty) {
      throw ArgumentError('Informe o horário.');
    }
    final database = await _databaseProvider();
    await database.transaction<void>((transaction) async {
      final veiculo = await transaction.query(
        'veiculos',
        columns: ['id'],
        where: 'id = ? AND cliente_id = ?',
        whereArgs: [veiculoId, clienteId],
        limit: 1,
      );
      if (veiculo.isEmpty) {
        throw StateError('O veículo selecionado não pertence ao cliente.');
      }
      final id = await transaction.insert('agendamentos', {
        'cliente_id': clienteId,
        'veiculo_id': veiculoId,
        'servico': servico.trim(),
        'data': DateTime(data.year, data.month, data.day).toIso8601String(),
        'hora': hora.trim(),
        'valor': valor,
        'status': 'Agendado',
        'observacoes': observacoes.trim(),
      });
      final agora = DateTime.now().toIso8601String();
      await transaction.update(
        'crm_leads',
        {
          'cliente_id': clienteId,
          'veiculo_id': veiculoId,
          'agendamento_id': id,
          'etapa': 'Agendado',
          'proximo_contato': null,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [leadId],
      );
      await transaction.insert('crm_interacoes', {
        'lead_id': leadId,
        'tipo': 'Agendamento',
        'descricao': 'Agendamento criado para ${servico.trim()}.',
        'data_interacao': agora,
        'criado_em': agora,
      });
    });
  }

  Future<CrmResumo> carregarResumo({DateTime? referencia}) async {
    final database = await _databaseProvider();
    final agora = referencia ?? DateTime.now();
    final inicioMes = DateTime(agora.year, agora.month, 1).toIso8601String();
    final fimMes = DateTime(agora.year, agora.month + 1, 1).toIso8601String();

    final abertos = await database.rawQuery('''
      SELECT COUNT(*) AS total,
             COALESCE(SUM(valor_potencial), 0) AS valor
      FROM crm_leads
      WHERE etapa NOT IN ('Ganho', 'Perdido')
    ''');
    final atrasados = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM crm_leads
      WHERE etapa NOT IN ('Ganho', 'Perdido')
        AND proximo_contato IS NOT NULL
        AND datetime(proximo_contato) < datetime(?)
      ''',
      [agora.toIso8601String()],
    );
    final encerrados = await database.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN etapa = 'Ganho' THEN 1 ELSE 0 END) AS ganhos,
        SUM(CASE WHEN etapa = 'Perdido' THEN 1 ELSE 0 END) AS perdidos,
        COALESCE(SUM(CASE WHEN etapa = 'Ganho' THEN valor_potencial ELSE 0 END), 0) AS valor_ganhos
      FROM crm_leads
      WHERE convertido_em >= ? AND convertido_em < ?
      ''',
      [inicioMes, fimMes],
    );
    final grupos = await database.rawQuery('''
      SELECT etapa, COUNT(*) AS total
      FROM crm_leads
      GROUP BY etapa
    ''');

    return CrmResumo(
      totalAbertos: _int(abertos.first['total']),
      valorPipeline: _double(abertos.first['valor']),
      followUpsAtrasados: _int(atrasados.first['total']),
      ganhosMes: _int(encerrados.first['ganhos']),
      perdidosMes: _int(encerrados.first['perdidos']),
      valorGanhosMes: _double(encerrados.first['valor_ganhos']),
      porEtapa: {
        for (final row in grupos)
          (row['etapa'] ?? '').toString(): _int(row['total']),
      },
    );
  }

  Future<List<CrmCampanha>> listarCampanhas({
    bool incluirInativas = true,
  }) async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'crm_campanhas',
      where: incluirInativas ? null : 'ativo = 1',
      orderBy: 'ativo DESC, tipo ASC, nome COLLATE NOCASE ASC, id ASC',
    );
    return rows
        .map((row) => CrmCampanha.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<int> salvarCampanha(CrmCampanha campanha) async {
    final nome = campanha.nome.trim();
    if (nome.length < 3) {
      throw ArgumentError('Informe o nome da campanha.');
    }
    if (!CrmCampanha.tipos.contains(campanha.tipo)) {
      throw ArgumentError('Tipo de campanha inválido.');
    }
    if (!CrmCampanha.tiposBeneficio.contains(campanha.beneficioTipo)) {
      throw ArgumentError('Tipo de benefício inválido.');
    }
    if (campanha.beneficioValor < 0 || campanha.valorMinimo < 0) {
      throw ArgumentError('Valores da campanha não podem ser negativos.');
    }
    if (campanha.beneficioTipo == 'Percentual' &&
        campanha.beneficioValor > 100) {
      throw ArgumentError('O percentual não pode ser maior que 100%.');
    }
    if (campanha.diasValidade < 1 || campanha.diasValidade > 365) {
      throw ArgumentError('A validade deve ficar entre 1 e 365 dias.');
    }

    final database = await _databaseProvider();
    final agora = DateTime.now().toIso8601String();
    final dados = campanha.toMap(incluirId: false)
      ..['nome'] = nome
      ..['beneficio_descricao'] = campanha.beneficioDescricao.trim()
      ..['atualizado_em'] = agora;

    if (campanha.id == null) {
      dados['criado_em'] = agora;
      return database.insert('crm_campanhas', dados);
    }
    await database.update(
      'crm_campanhas',
      dados..remove('criado_em'),
      where: 'id = ?',
      whereArgs: [campanha.id],
    );
    return campanha.id!;
  }

  Future<void> atualizarNascimentoCliente(int clienteId, DateTime? data) async {
    final database = await _databaseProvider();
    await database.update(
      'clientes',
      {'data_nascimento': data == null ? null : _dataDia(data)},
      where: 'id = ?',
      whereArgs: [clienteId],
    );
  }

  Future<List<Map<String, dynamic>>> listarClientesParaBeneficios() async {
    final database = await _databaseProvider();
    return database.rawQuery('''
      SELECT
        c.id,
        c.nome,
        c.telefone,
        c.email,
        c.data_nascimento,
        MAX(
          CASE
            WHEN LOWER(os.status) = 'finalizada'
              THEN COALESCE(
                os.data_finalizacao,
                os.data_inicio,
                os.data_abertura
              )
            ELSE NULL
          END
        ) AS ultimo_servico
      FROM clientes c
      LEFT JOIN ordens_servico os ON os.cliente_id = c.id
      WHERE COALESCE(c.ativo, 1) = 1
      GROUP BY c.id, c.nome, c.telefone, c.email, c.data_nascimento
      ORDER BY c.nome COLLATE NOCASE ASC
    ''');
  }

  Future<int> gerarBeneficiosAniversario({DateTime? referencia}) async {
    final database = await _databaseProvider();
    final ref = referencia ?? DateTime.now();
    return database.transaction<int>((transaction) async {
      await _expirarCupons(transaction, ref);
      final campanhas = await transaction.query(
        'crm_campanhas',
        where: "tipo = 'Aniversário' AND ativo = 1",
      );
      if (campanhas.isEmpty) {
        return 0;
      }

      final clientes = await transaction.rawQuery('''
        SELECT id, nome, data_nascimento
        FROM clientes
        WHERE COALESCE(ativo, 1) = 1
          AND data_nascimento IS NOT NULL
          AND TRIM(data_nascimento) != ''
        ''');

      var criados = 0;
      for (final campanhaRow in campanhas) {
        final campanha = CrmCampanha.fromMap(
          Map<String, dynamic>.from(campanhaRow),
        );
        for (final cliente in clientes) {
          final nascimento = DateTime.tryParse(
            (cliente['data_nascimento'] ?? '').toString(),
          );
          if (nascimento == null || nascimento.month != ref.month) {
            continue;
          }
          final clienteId = (cliente['id'] as num).toInt();
          final aniversario = _aniversarioNoAno(nascimento, ref.year);
          final chave = 'aniversario:${campanha.id}:$clienteId:${ref.year}';
          final inserido = await _inserirCupomSeAusente(
            transaction,
            campanha: campanha,
            clienteId: clienteId,
            chaveGeracao: chave,
            inicio: aniversario,
          );
          if (inserido) {
            criados++;
          }
        }
      }
      return criados;
    });
  }

  Future<int> gerarBeneficiosReativacao({DateTime? referencia}) async {
    final database = await _databaseProvider();
    final ref = referencia ?? DateTime.now();
    return database.transaction<int>((transaction) async {
      await _expirarCupons(transaction, ref);
      final campanhas = await transaction.query(
        'crm_campanhas',
        where: "tipo = 'Reativação' AND ativo = 1",
      );
      var criados = 0;
      for (final campanhaRow in campanhas) {
        final campanha = CrmCampanha.fromMap(
          Map<String, dynamic>.from(campanhaRow),
        );
        final limite = ref.subtract(Duration(days: campanha.diasSemRetorno));
        final clientes = await transaction.rawQuery(
          '''
          SELECT
            c.id,
            c.nome,
            MAX(COALESCE(os.data_finalizacao, os.data_inicio, os.data_abertura)) AS ultimo_servico
          FROM clientes c
          INNER JOIN ordens_servico os ON os.cliente_id = c.id
          WHERE COALESCE(c.ativo, 1) = 1
            AND LOWER(os.status) = 'finalizada'
          GROUP BY c.id, c.nome
          HAVING datetime(ultimo_servico) < datetime(?)
          ''',
          [limite.toIso8601String()],
        );
        for (final cliente in clientes) {
          final clienteId = (cliente['id'] as num).toInt();
          final chave =
              'reativacao:${campanha.id}:$clienteId:${ref.year}-${ref.month.toString().padLeft(2, '0')}';
          final inserido = await _inserirCupomSeAusente(
            transaction,
            campanha: campanha,
            clienteId: clienteId,
            chaveGeracao: chave,
            inicio: ref,
          );
          if (inserido) {
            criados++;
          }
        }
      }
      return criados;
    });
  }

  Future<List<Map<String, dynamic>>> listarCupons({
    bool somenteAtivos = false,
  }) async {
    final database = await _databaseProvider();
    await _expirarCupons(database, DateTime.now());
    return database.rawQuery('''
      SELECT cp.*, c.nome AS cliente_nome, ca.nome AS campanha_nome
      FROM crm_cupons cp
      LEFT JOIN clientes c ON c.id = cp.cliente_id
      LEFT JOIN crm_campanhas ca ON ca.id = cp.campanha_id
      ${somenteAtivos ? "WHERE cp.status = 'Ativo'" : ''}
      ORDER BY cp.validade_fim DESC, cp.id DESC
    ''');
  }

  Future<void> usarCupom({
    required int cupomId,
    required int ordemServicoId,
    DateTime? data,
  }) async {
    final database = await _databaseProvider();
    await database.transaction<void>((transaction) async {
      await _expirarCupons(transaction, data ?? DateTime.now());
      final rows = await transaction.query(
        'crm_cupons',
        where: "id = ? AND status = 'Ativo'",
        whereArgs: [cupomId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Cupom não está disponível para uso.');
      }
      final os = await transaction.query(
        'ordens_servico',
        columns: ['id', 'cliente_id', 'valor_total', 'desconto'],
        where: 'id = ?',
        whereArgs: [ordemServicoId],
        limit: 1,
      );
      if (os.isEmpty) {
        throw StateError('Ordem de Serviço não encontrada.');
      }
      final clienteCupom = (rows.first['cliente_id'] as num?)?.toInt();
      final clienteOs = (os.first['cliente_id'] as num?)?.toInt();
      if (clienteCupom != null && clienteCupom != clienteOs) {
        throw StateError('Este cupom pertence a outro cliente.');
      }
      final subtotal = _double(os.first['valor_total']);
      final minimo = _double(rows.first['valor_minimo']);
      if (subtotal + 0.000001 < minimo) {
        throw StateError('A OS não atingiu o valor mínimo deste benefício.');
      }
      final agora = (data ?? DateTime.now()).toIso8601String();
      await transaction.update(
        'crm_cupons',
        {
          'status': 'Usado',
          'usado_em': agora,
          'ordem_servico_id': ordemServicoId,
        },
        where: 'id = ?',
        whereArgs: [cupomId],
      );
    });
  }

  Future<void> cancelarCupom(int cupomId) async {
    final database = await _databaseProvider();
    await database.update(
      'crm_cupons',
      {'status': 'Cancelado'},
      where: "id = ? AND status = 'Ativo'",
      whereArgs: [cupomId],
    );
  }

  Map<String, dynamic> simularBeneficio({
    required CrmCupom cupom,
    required double valorBase,
    required double precoMinimoSeguro,
  }) {
    var desconto = 0.0;
    if (cupom.beneficioTipo == 'Percentual') {
      desconto = valorBase * cupom.beneficioValor / 100;
    } else if (cupom.beneficioTipo == 'Valor' ||
        cupom.beneficioTipo == 'Crédito') {
      desconto = cupom.beneficioValor;
    }
    desconto = min(desconto, valorBase);
    final finalCalculado = max(0.0, valorBase - desconto);
    return {
      'valor_base': valorBase,
      'desconto': desconto,
      'valor_final': finalCalculado,
      'abaixo_preco_minimo': finalCalculado + 0.000001 < precoMinimoSeguro,
    };
  }

  Future<void> _vincularClienteConvertido(
    DatabaseExecutor database,
    int leadId,
    int clienteId,
  ) async {
    final agora = DateTime.now().toIso8601String();
    await database.update(
      'crm_leads',
      {'cliente_id': clienteId, 'atualizado_em': agora},
      where: 'id = ?',
      whereArgs: [leadId],
    );
    await database.insert('crm_interacoes', {
      'lead_id': leadId,
      'tipo': 'Conversão de cadastro',
      'descricao': 'Contato convertido/vinculado a um cliente do cadastro.',
      'data_interacao': agora,
      'criado_em': agora,
    });
  }

  Future<List<Map<String, dynamic>>> listarVeiculosCliente(
    int clienteId,
  ) async {
    final database = await _databaseProvider();
    return database.query(
      'veiculos',
      columns: ['id', 'placa', 'marca', 'modelo', 'ano', 'cor'],
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'modelo COLLATE NOCASE ASC, placa COLLATE NOCASE ASC',
    );
  }

  Future<bool> _inserirCupomSeAusente(
    DatabaseExecutor database, {
    required CrmCampanha campanha,
    required int clienteId,
    required String chaveGeracao,
    required DateTime inicio,
  }) async {
    final existe = await database.query(
      'crm_cupons',
      columns: ['id'],
      where: 'chave_geracao = ?',
      whereArgs: [chaveGeracao],
      limit: 1,
    );
    if (existe.isNotEmpty) {
      return false;
    }
    final fim = inicio.add(Duration(days: campanha.diasValidade));
    final codigo = _codigoCupom(campanha, clienteId, inicio);
    await database.insert('crm_cupons', {
      'codigo': codigo,
      'campanha_id': campanha.id,
      'cliente_id': clienteId,
      'lead_id': null,
      'beneficio_tipo': campanha.beneficioTipo,
      'beneficio_valor': campanha.beneficioValor,
      'beneficio_descricao': campanha.beneficioDescricao,
      'valor_minimo': campanha.valorMinimo,
      'validade_inicio': _dataDia(inicio),
      'validade_fim': _dataDia(fim),
      'status': 'Ativo',
      'usado_em': null,
      'ordem_servico_id': null,
      'chave_geracao': chaveGeracao,
      'criado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return true;
  }

  Future<void> _expirarCupons(
    DatabaseExecutor database,
    DateTime referencia,
  ) async {
    await database.update(
      'crm_cupons',
      {'status': 'Expirado'},
      where: "status = 'Ativo' AND date(validade_fim) < date(?)",
      whereArgs: [_dataDia(referencia)],
    );
  }

  static DateTime _aniversarioNoAno(DateTime nascimento, int ano) {
    if (nascimento.month == 2 && nascimento.day == 29) {
      final bissexto = DateTime(ano, 3, 0).day == 29;
      return DateTime(ano, 2, bissexto ? 29 : 28);
    }
    return DateTime(ano, nascimento.month, nascimento.day);
  }

  static String _codigoCupom(
    CrmCampanha campanha,
    int clienteId,
    DateTime data,
  ) {
    final tipo = campanha.tipo;
    final prefixo = tipo == 'Aniversário'
        ? 'NIVER'
        : tipo == 'Reativação'
        ? 'VOLTA'
        : 'IMP';
    final campanhaId = campanha.id ?? 0;
    final sufixo =
        ((clienteId * 7919 + campanhaId * 101 + data.year * 31 + data.month) %
                100000)
            .toString()
            .padLeft(5, '0');
    return '$prefixo-$sufixo';
  }

  static String _digitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');
  static String _dataDia(DateTime data) =>
      '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';

  static int _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic valor) {
    if (valor is num) {
      return valor.toDouble();
    }
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
