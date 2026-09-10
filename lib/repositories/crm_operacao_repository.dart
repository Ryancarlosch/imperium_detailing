import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/crm_acao_relacionamento.dart';

class CrmOperacaoResumo {
  const CrmOperacaoResumo({
    required this.atrasadas,
    required this.hoje,
    required this.proximosSeteDias,
    required this.concluidasMes,
    required this.orcamentosPendentes,
    required this.valorOrcamentosPendentes,
    required this.cuponsAtivos,
    required this.receitaCuponsUsados,
  });

  final int atrasadas;
  final int hoje;
  final int proximosSeteDias;
  final int concluidasMes;
  final int orcamentosPendentes;
  final double valorOrcamentosPendentes;
  final int cuponsAtivos;
  final double receitaCuponsUsados;
}

class CrmOrigemDesempenho {
  const CrmOrigemDesempenho({
    required this.origem,
    required this.total,
    required this.ganhos,
    required this.perdidos,
    required this.valorPotencial,
    required this.valorGanho,
  });

  final String origem;
  final int total;
  final int ganhos;
  final int perdidos;
  final double valorPotencial;
  final double valorGanho;

  double get conversao => total <= 0 ? 0 : ganhos * 100 / total;
}

class CrmMotivoPerdaResumo {
  const CrmMotivoPerdaResumo({required this.motivo, required this.quantidade});

  final String motivo;
  final int quantidade;
}

class CrmCampanhaDesempenho {
  const CrmCampanhaDesempenho({
    required this.nome,
    required this.gerados,
    required this.ativos,
    required this.usados,
    required this.expirados,
    required this.receitaAtribuida,
  });

  final String nome;
  final int gerados;
  final int ativos;
  final int usados;
  final int expirados;
  final double receitaAtribuida;
}

class CrmDesempenhoResumo {
  const CrmDesempenhoResumo({
    required this.inicio,
    required this.fim,
    required this.leadsCriados,
    required this.ganhos,
    required this.perdidos,
    required this.abertos,
    required this.valorPotencial,
    required this.valorGanho,
    required this.orcamentosCriados,
    required this.orcamentosAprovados,
    required this.valorOrcamentos,
    required this.valorOrcamentosAprovados,
    required this.acoesConcluidas,
    required this.origens,
    required this.motivosPerda,
    required this.campanhas,
  });

  final DateTime inicio;
  final DateTime fim;
  final int leadsCriados;
  final int ganhos;
  final int perdidos;
  final int abertos;
  final double valorPotencial;
  final double valorGanho;
  final int orcamentosCriados;
  final int orcamentosAprovados;
  final double valorOrcamentos;
  final double valorOrcamentosAprovados;
  final int acoesConcluidas;
  final List<CrmOrigemDesempenho> origens;
  final List<CrmMotivoPerdaResumo> motivosPerda;
  final List<CrmCampanhaDesempenho> campanhas;

  double get conversaoLeads =>
      leadsCriados <= 0 ? 0 : ganhos * 100 / leadsCriados;

  double get aprovacaoOrcamentos => orcamentosCriados <= 0
      ? 0
      : orcamentosAprovados * 100 / orcamentosCriados;
}

class CrmOperacaoRepository {
  CrmOperacaoRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => AppDatabase.instance.database);

  final Future<Database> Function() _databaseProvider;

  static const String tabelaAcoes = 'crm_acoes_relacionamento';

  Future<void> garantirEstrutura() async {
    final database = await _databaseProvider();
    await _garantirEstrutura(database);
  }

  Future<void> _garantirEstrutura(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $tabelaAcoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chave TEXT NOT NULL UNIQUE,
        tipo TEXT NOT NULL,
        entidade_tipo TEXT NOT NULL,
        entidade_id INTEGER NOT NULL,
        cliente_id INTEGER,
        lead_id INTEGER,
        titulo TEXT NOT NULL,
        nome_contato TEXT NOT NULL DEFAULT '',
        telefone TEXT NOT NULL DEFAULT '',
        mensagem_sugerida TEXT NOT NULL DEFAULT '',
        vencimento TEXT NOT NULL,
        prioridade TEXT NOT NULL DEFAULT 'Normal',
        status TEXT NOT NULL DEFAULT 'Pendente',
        concluida_em TEXT,
        adiada_para TEXT,
        observacoes TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        CHECK (prioridade IN ('Baixa', 'Normal', 'Alta')),
        CHECK (status IN ('Pendente', 'Concluida', 'Adiada', 'Ignorada'))
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_crm_acoes_status_vencimento
      ON $tabelaAcoes (status, vencimento)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_crm_acoes_entidade
      ON $tabelaAcoes (entidade_tipo, entidade_id)
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_crm_acoes_cliente
      ON $tabelaAcoes (cliente_id, status)
    ''');
  }

  Future<int> sincronizarAcoes({DateTime? referencia}) async {
    final database = await _databaseProvider();
    final ref = referencia ?? DateTime.now();
    return database.transaction<int>((transaction) async {
      await _garantirEstrutura(transaction);

      await _invalidarAcoesSemFonte(transaction);

      var criadas = 0;
      criadas += await _sincronizarLeads(transaction, ref);
      criadas += await _sincronizarOrcamentos(transaction, ref);
      criadas += await _sincronizarPosVenda(transaction, ref);
      criadas += await _sincronizarCupons(transaction, ref);
      return criadas;
    });
  }

  Future<int> _sincronizarLeads(
    DatabaseExecutor database,
    DateTime referencia,
  ) async {
    final limite = _somenteDia(referencia).add(const Duration(days: 30));
    final rows = await database.rawQuery('''
      SELECT id, nome, telefone, cliente_id, etapa,
             servico_interesse, proximo_contato
      FROM crm_leads
      WHERE etapa NOT IN ('Ganho', 'Perdido')
        AND proximo_contato IS NOT NULL
        AND TRIM(proximo_contato) != ''
      ORDER BY proximo_contato ASC
    ''');

    var criadas = 0;
    for (final row in rows) {
      final data = _parseData(row['proximo_contato']);
      if (data == null || _somenteDia(data).isAfter(limite)) {
        continue;
      }

      final leadId = _int(row['id']);
      final clienteId = _intNulo(row['cliente_id']);
      final dia = _dataDia(data);
      final chave = 'lead:$leadId:$dia';

      await database.update(
        tabelaAcoes,
        {
          'status': 'Ignorada',
          'observacoes': 'Substituída por uma nova data de follow-up.',
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where:
            "tipo = 'Follow-up lead' AND entidade_id = ? AND status IN ('Pendente', 'Adiada') AND chave != ?",
        whereArgs: [leadId, chave],
      );

      final nome = (row['nome'] ?? '').toString().trim();
      final servico = (row['servico_interesse'] ?? '').toString().trim();
      final etapa = (row['etapa'] ?? '').toString().trim();
      final mensagem = servico.isEmpty
          ? 'Olá, ${_primeiroNome(nome)}! Tudo bem? Estou entrando em contato para dar continuidade ao seu atendimento na Imperium Detailing. Posso te ajudar em algo?'
          : 'Olá, ${_primeiroNome(nome)}! Tudo bem? Estou entrando em contato para dar continuidade ao atendimento sobre $servico. Posso te ajudar a avançar?';

      final inseriu = await _inserirAcaoSeAusente(
        database,
        chave: chave,
        tipo: 'Follow-up lead',
        entidadeTipo: 'lead',
        entidadeId: leadId,
        clienteId: clienteId,
        leadId: leadId,
        titulo: etapa.isEmpty ? 'Retomar contato' : 'Retomar contato • $etapa',
        nomeContato: nome,
        telefone: (row['telefone'] ?? '').toString(),
        mensagem: mensagem,
        vencimento: data,
        prioridade: _somenteDia(data).isBefore(_somenteDia(referencia))
            ? 'Alta'
            : 'Normal',
      );
      if (inseriu) criadas++;
    }
    return criadas;
  }

  Future<int> _sincronizarOrcamentos(
    DatabaseExecutor database,
    DateTime referencia,
  ) async {
    final rows = await database.rawQuery('''
      SELECT o.id, o.cliente_id, o.valor, o.data_emissao, o.validade,
             c.nome AS cliente_nome, COALESCE(c.telefone, '') AS telefone,
             COALESCE(
               (SELECT GROUP_CONCAT(NULLIF(TRIM(oi.servico), ''), ', ')
                FROM orcamento_itens oi
                WHERE oi.orcamento_id = o.id),
               NULLIF(TRIM(o.servico), ''),
               'serviços do orçamento'
             ) AS servicos
      FROM orcamentos o
      INNER JOIN clientes c ON c.id = o.cliente_id
      WHERE LOWER(TRIM(o.status)) = 'pendente'
        AND COALESCE(c.ativo, 1) = 1
      ORDER BY o.data_emissao ASC, o.id ASC
    ''');

    var criadas = 0;
    final hoje = _somenteDia(referencia);
    for (final row in rows) {
      final emissao = _parseData(row['data_emissao']);
      if (emissao == null) continue;
      final validade = _parseData(row['validade']);
      if (validade != null && _somenteDia(validade).isBefore(hoje)) {
        await database.update(
          tabelaAcoes,
          {
            'status': 'Ignorada',
            'observacoes': 'Orçamento venceu antes do follow-up ser concluído.',
            'atualizado_em': DateTime.now().toIso8601String(),
          },
          where: "chave = ? AND status IN ('Pendente', 'Adiada')",
          whereArgs: ['orcamento:${_int(row['id'])}'],
        );
        continue;
      }

      final vencimento = _somenteDia(emissao).add(const Duration(days: 2));
      if (vencimento.isAfter(hoje.add(const Duration(days: 30)))) {
        continue;
      }

      final id = _int(row['id']);
      final nome = (row['cliente_nome'] ?? '').toString().trim();
      final valor = _double(row['valor']);
      final servicos = (row['servicos'] ?? 'serviços do orçamento').toString();
      final mensagem =
          'Olá, ${_primeiroNome(nome)}! Tudo bem? Passando para saber se conseguiu analisar o orçamento nº $id para $servicos, no valor de ${_moeda(valor)}. Se quiser, posso tirar qualquer dúvida e ajustar os detalhes com você.';

      final inseriu = await _inserirAcaoSeAusente(
        database,
        chave: 'orcamento:$id',
        tipo: 'Follow-up orçamento',
        entidadeTipo: 'orcamento',
        entidadeId: id,
        clienteId: _int(row['cliente_id']),
        titulo: 'Retomar orçamento #$id',
        nomeContato: nome,
        telefone: (row['telefone'] ?? '').toString(),
        mensagem: mensagem,
        vencimento: vencimento,
        prioridade: vencimento.isBefore(hoje) ? 'Alta' : 'Normal',
      );
      if (inseriu) criadas++;
    }
    return criadas;
  }

  Future<int> _sincronizarPosVenda(
    DatabaseExecutor database,
    DateTime referencia,
  ) async {
    final rows = await database.rawQuery('''
      SELECT os.id, os.numero, os.cliente_id,
             COALESCE(os.data_finalizacao, os.data_inicio, os.data_abertura) AS data_servico,
             c.nome AS cliente_nome, COALESCE(c.telefone, '') AS telefone
      FROM ordens_servico os
      INNER JOIN clientes c ON c.id = os.cliente_id
      WHERE LOWER(TRIM(os.status)) = 'finalizada'
        AND COALESCE(c.ativo, 1) = 1
      ORDER BY data_servico DESC, os.id DESC
    ''');

    var criadas = 0;
    final hoje = _somenteDia(referencia);
    final limitePassado = hoje.subtract(const Duration(days: 60));
    for (final row in rows) {
      final dataServico = _parseData(row['data_servico']);
      if (dataServico == null) continue;
      final diaServico = _somenteDia(dataServico);
      if (diaServico.isBefore(limitePassado) || diaServico.isAfter(hoje)) {
        continue;
      }

      final osId = _int(row['id']);
      final numero = (row['numero'] ?? osId).toString();
      final nome = (row['cliente_nome'] ?? '').toString().trim();
      final vencimento = diaServico.add(const Duration(days: 1));
      final mensagem =
          'Olá, ${_primeiroNome(nome)}! Passando para agradecer novamente pela confiança na Imperium Detailing. Como ficou o veículo depois do serviço da OS $numero? Se puder, conta pra gente como foi sua experiência. 🙌';

      final inseriu = await _inserirAcaoSeAusente(
        database,
        chave: 'posvenda:$osId',
        tipo: 'Pós-venda',
        entidadeTipo: 'ordem_servico',
        entidadeId: osId,
        clienteId: _int(row['cliente_id']),
        titulo: 'Pós-venda • OS $numero',
        nomeContato: nome,
        telefone: (row['telefone'] ?? '').toString(),
        mensagem: mensagem,
        vencimento: vencimento,
        prioridade: vencimento.isBefore(hoje) ? 'Alta' : 'Normal',
      );
      if (inseriu) criadas++;
    }
    return criadas;
  }

  Future<int> _sincronizarCupons(
    DatabaseExecutor database,
    DateTime referencia,
  ) async {
    final rows = await database.rawQuery('''
      SELECT cp.id, cp.codigo, cp.cliente_id, cp.lead_id,
             cp.beneficio_tipo, cp.beneficio_valor, cp.beneficio_descricao,
             cp.valor_minimo, cp.validade_inicio, cp.validade_fim,
             c.nome AS cliente_nome, COALESCE(c.telefone, '') AS telefone,
             ca.nome AS campanha_nome, ca.tipo AS campanha_tipo
      FROM crm_cupons cp
      LEFT JOIN clientes c ON c.id = cp.cliente_id
      LEFT JOIN crm_campanhas ca ON ca.id = cp.campanha_id
      WHERE cp.status = 'Ativo'
      ORDER BY cp.validade_fim ASC, cp.id ASC
    ''');

    var criadas = 0;
    final hoje = _somenteDia(referencia);
    for (final row in rows) {
      final fim = _parseData(row['validade_fim']);
      final inicio = _parseData(row['validade_inicio']) ?? hoje;
      final cupomId = _int(row['id']);
      if (fim == null || _somenteDia(fim).isBefore(hoje)) {
        await database.update(
          tabelaAcoes,
          {
            'status': 'Ignorada',
            'observacoes': 'Cupom expirou antes do contato ser concluído.',
            'atualizado_em': DateTime.now().toIso8601String(),
          },
          where: "chave = ? AND status IN ('Pendente', 'Adiada')",
          whereArgs: ['cupom:$cupomId'],
        );
        continue;
      }

      final nome = (row['cliente_nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final campanha = (row['campanha_nome'] ?? 'benefício').toString().trim();
      final codigo = (row['codigo'] ?? '').toString().trim();
      final beneficio = _descricaoBeneficio(row);
      final mensagem =
          'Olá, ${_primeiroNome(nome)}! Temos um benefício da Imperium Detailing para você: $beneficio. 🎁\n\nCódigo: *$codigo*\nVálido até ${_dataBr(fim)}.${campanha.isEmpty ? '' : '\nCampanha: $campanha'}\n\nSe quiser aproveitar, me chama por aqui para agendarmos.';

      final vencimento = _somenteDia(inicio).isBefore(hoje)
          ? hoje
          : _somenteDia(inicio);
      final inseriu = await _inserirAcaoSeAusente(
        database,
        chave: 'cupom:$cupomId',
        tipo: 'Benefício/cupom',
        entidadeTipo: 'cupom',
        entidadeId: cupomId,
        clienteId: _intNulo(row['cliente_id']),
        leadId: _intNulo(row['lead_id']),
        titulo: 'Enviar benefício • $codigo',
        nomeContato: nome,
        telefone: (row['telefone'] ?? '').toString(),
        mensagem: mensagem,
        vencimento: vencimento,
        prioridade: _somenteDia(fim).difference(hoje).inDays <= 3
            ? 'Alta'
            : 'Normal',
      );
      if (inseriu) criadas++;
    }
    return criadas;
  }

  Future<void> _invalidarAcoesSemFonte(DatabaseExecutor database) async {
    final agora = DateTime.now().toIso8601String();

    await database.rawUpdate(
      '''
      UPDATE $tabelaAcoes
      SET status = 'Ignorada',
          observacoes = CASE
            WHEN TRIM(observacoes) = '' THEN 'Lead encerrado ou follow-up removido.'
            ELSE observacoes
          END,
          atualizado_em = ?
      WHERE tipo = 'Follow-up lead'
        AND status IN ('Pendente', 'Adiada')
        AND NOT EXISTS (
          SELECT 1
          FROM crm_leads l
          WHERE l.id = $tabelaAcoes.entidade_id
            AND l.etapa NOT IN ('Ganho', 'Perdido')
            AND l.proximo_contato IS NOT NULL
            AND TRIM(l.proximo_contato) != ''
        )
    ''',
      [agora],
    );

    await database.rawUpdate(
      '''
      UPDATE $tabelaAcoes
      SET status = 'Ignorada',
          observacoes = CASE
            WHEN TRIM(observacoes) = '' THEN 'Orçamento não está mais pendente.'
            ELSE observacoes
          END,
          atualizado_em = ?
      WHERE tipo = 'Follow-up orçamento'
        AND status IN ('Pendente', 'Adiada')
        AND NOT EXISTS (
          SELECT 1
          FROM orcamentos o
          WHERE o.id = $tabelaAcoes.entidade_id
            AND LOWER(TRIM(o.status)) = 'pendente'
        )
    ''',
      [agora],
    );

    await database.rawUpdate(
      '''
      UPDATE $tabelaAcoes
      SET status = 'Ignorada',
          observacoes = CASE
            WHEN TRIM(observacoes) = '' THEN 'A Ordem de Serviço não está mais finalizada.'
            ELSE observacoes
          END,
          atualizado_em = ?
      WHERE tipo = 'Pós-venda'
        AND status IN ('Pendente', 'Adiada')
        AND NOT EXISTS (
          SELECT 1
          FROM ordens_servico os
          WHERE os.id = $tabelaAcoes.entidade_id
            AND LOWER(TRIM(os.status)) = 'finalizada'
        )
    ''',
      [agora],
    );

    await database.rawUpdate(
      '''
      UPDATE $tabelaAcoes
      SET status = 'Ignorada',
          observacoes = CASE
            WHEN TRIM(observacoes) = '' THEN 'Cupom não está mais ativo.'
            ELSE observacoes
          END,
          atualizado_em = ?
      WHERE tipo = 'Benefício/cupom'
        AND status IN ('Pendente', 'Adiada')
        AND NOT EXISTS (
          SELECT 1
          FROM crm_cupons cp
          WHERE cp.id = $tabelaAcoes.entidade_id
            AND cp.status = 'Ativo'
        )
    ''',
      [agora],
    );
  }

  Future<bool> _inserirAcaoSeAusente(
    DatabaseExecutor database, {
    required String chave,
    required String tipo,
    required String entidadeTipo,
    required int entidadeId,
    int? clienteId,
    int? leadId,
    required String titulo,
    required String nomeContato,
    required String telefone,
    required String mensagem,
    required DateTime vencimento,
    String prioridade = 'Normal',
  }) async {
    final existente = await database.query(
      tabelaAcoes,
      columns: ['id'],
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );
    if (existente.isNotEmpty) {
      return false;
    }

    final agora = DateTime.now().toIso8601String();
    await database.insert(tabelaAcoes, {
      'chave': chave,
      'tipo': tipo,
      'entidade_tipo': entidadeTipo,
      'entidade_id': entidadeId,
      'cliente_id': clienteId,
      'lead_id': leadId,
      'titulo': titulo,
      'nome_contato': nomeContato,
      'telefone': telefone,
      'mensagem_sugerida': mensagem,
      'vencimento': _dataDia(vencimento),
      'prioridade': prioridade,
      'status': 'Pendente',
      'concluida_em': null,
      'adiada_para': null,
      'observacoes': '',
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return true;
  }

  Future<List<CrmAcaoRelacionamento>> listarAcoes({
    String status = 'Pendente',
  }) async {
    final database = await _databaseProvider();
    await _garantirEstrutura(database);
    final rows = await database.query(
      tabelaAcoes,
      where: status == 'Todos' ? null : 'status = ?',
      whereArgs: status == 'Todos' ? null : [status],
      orderBy:
          "CASE prioridade WHEN 'Alta' THEN 0 WHEN 'Normal' THEN 1 ELSE 2 END, vencimento ASC, id ASC",
    );
    return rows
        .map(
          (row) =>
              CrmAcaoRelacionamento.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<CrmOperacaoResumo> carregarResumo({DateTime? referencia}) async {
    final database = await _databaseProvider();
    await _garantirEstrutura(database);
    final ref = _somenteDia(referencia ?? DateTime.now());
    final inicioMes = DateTime(ref.year, ref.month, 1);
    final fimSete = ref.add(const Duration(days: 7));

    final acoes = await listarAcoes(status: 'Todos');
    var atrasadas = 0;
    var hoje = 0;
    var proximas = 0;
    var concluidasMes = 0;
    for (final acao in acoes) {
      if (acao.pendente && acao.atrasadaEm(ref)) atrasadas++;
      if (acao.pendente && acao.venceEm(ref)) hoje++;
      final data = acao.vencimentoData;
      if (acao.pendente && data != null) {
        final dia = _somenteDia(data);
        if (dia.isAfter(ref) && !dia.isAfter(fimSete)) proximas++;
      }
      final concluida = _parseData(acao.concluidaEm);
      if (acao.status == 'Concluida' &&
          concluida != null &&
          !_somenteDia(concluida).isBefore(inicioMes)) {
        concluidasMes++;
      }
    }

    final orcamentos = await database.rawQuery('''
      SELECT COUNT(*) AS quantidade, COALESCE(SUM(valor), 0) AS total
      FROM orcamentos
      WHERE LOWER(TRIM(status)) = 'pendente'
    ''');
    final cupons = await database.rawQuery('''
      SELECT COUNT(*) AS quantidade
      FROM crm_cupons
      WHERE status = 'Ativo'
    ''');
    final receita = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(os.valor_total), 0) AS total
      FROM crm_cupons cp
      INNER JOIN ordens_servico os ON os.id = cp.ordem_servico_id
      WHERE cp.status = 'Usado'
        AND cp.usado_em IS NOT NULL
        AND datetime(cp.usado_em) >= datetime(?)
    ''',
      [inicioMes.toIso8601String()],
    );

    return CrmOperacaoResumo(
      atrasadas: atrasadas,
      hoje: hoje,
      proximosSeteDias: proximas,
      concluidasMes: concluidasMes,
      orcamentosPendentes: _int(orcamentos.first['quantidade']),
      valorOrcamentosPendentes: _double(orcamentos.first['total']),
      cuponsAtivos: _int(cupons.first['quantidade']),
      receitaCuponsUsados: _double(receita.first['total']),
    );
  }

  Future<void> concluirAcao(
    int acaoId, {
    String observacoes = '',
    DateTime? proximoContato,
  }) async {
    final database = await _databaseProvider();
    await database.transaction<void>((transaction) async {
      await _garantirEstrutura(transaction);
      final rows = await transaction.query(
        tabelaAcoes,
        where: 'id = ?',
        whereArgs: [acaoId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Ação de relacionamento não encontrada.');
      }
      final acao = CrmAcaoRelacionamento.fromMap(
        Map<String, dynamic>.from(rows.first),
      );
      if (acao.status == 'Concluida') return;

      final agora = DateTime.now().toIso8601String();
      await transaction.update(
        tabelaAcoes,
        {
          'status': 'Concluida',
          'concluida_em': agora,
          'observacoes': observacoes.trim(),
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [acaoId],
      );

      if (acao.leadId != null) {
        await transaction.insert('crm_interacoes', {
          'lead_id': acao.leadId,
          'tipo': acao.tipo,
          'descricao': observacoes.trim().isEmpty
              ? 'Ação de relacionamento concluída: ${acao.titulo}.'
              : observacoes.trim(),
          'data_interacao': agora,
          'criado_em': agora,
        });

        if (acao.tipo == 'Follow-up lead') {
          await transaction.update(
            'crm_leads',
            {
              'proximo_contato': proximoContato?.toIso8601String(),
              'atualizado_em': agora,
            },
            where: 'id = ?',
            whereArgs: [acao.leadId],
          );
        }
      }
    });
  }

  Future<void> adiarAcao(int acaoId, DateTime novaData) async {
    final database = await _databaseProvider();
    await _garantirEstrutura(database);
    final hoje = _somenteDia(DateTime.now());
    final nova = _somenteDia(novaData);
    if (nova.isBefore(hoje)) {
      throw ArgumentError('A nova data não pode ficar no passado.');
    }
    final alterados = await database.update(
      tabelaAcoes,
      {
        'status': 'Pendente',
        'vencimento': _dataDia(nova),
        'adiada_para': _dataDia(nova),
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND status IN ('Pendente', 'Adiada')",
      whereArgs: [acaoId],
    );
    if (alterados == 0) {
      throw StateError('Ação não está disponível para adiamento.');
    }
  }

  Future<void> ignorarAcao(int acaoId, {String motivo = ''}) async {
    final database = await _databaseProvider();
    await _garantirEstrutura(database);
    await database.update(
      tabelaAcoes,
      {
        'status': 'Ignorada',
        'observacoes': motivo.trim(),
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: "id = ? AND status != 'Concluida'",
      whereArgs: [acaoId],
    );
  }

  Future<int> criarOuAtualizarLeadDoOrcamento(int orcamentoId) async {
    final database = await _databaseProvider();
    return database.transaction<int>((transaction) async {
      final orcamentos = await transaction.rawQuery(
        '''
        SELECT o.id, o.cliente_id, o.veiculo_id, o.valor,
               c.nome, COALESCE(c.telefone, '') AS telefone,
               COALESCE(c.email, '') AS email,
               COALESCE(
                 (SELECT GROUP_CONCAT(NULLIF(TRIM(oi.servico), ''), ', ')
                  FROM orcamento_itens oi
                  WHERE oi.orcamento_id = o.id),
                 NULLIF(TRIM(o.servico), ''),
                 ''
               ) AS servicos,
               CASE
                 WHEN v.id IS NULL THEN ''
                 ELSE TRIM(COALESCE(v.marca, '') || ' ' || COALESCE(v.modelo, '') ||
                   CASE WHEN COALESCE(v.placa, '') = '' THEN '' ELSE ' • ' || v.placa END)
               END AS veiculo
        FROM orcamentos o
        INNER JOIN clientes c ON c.id = o.cliente_id
        LEFT JOIN veiculos v ON v.id = o.veiculo_id
        WHERE o.id = ?
        LIMIT 1
      ''',
        [orcamentoId],
      );
      if (orcamentos.isEmpty) {
        throw StateError('Orçamento não encontrado.');
      }
      final row = orcamentos.first;
      final clienteId = _int(row['cliente_id']);
      final agora = DateTime.now();
      final proximo = agora.add(const Duration(days: 2)).toIso8601String();
      final existentes = await transaction.query(
        'crm_leads',
        columns: ['id'],
        where: "cliente_id = ? AND etapa NOT IN ('Ganho', 'Perdido')",
        whereArgs: [clienteId],
        orderBy: 'atualizado_em DESC, id DESC',
        limit: 1,
      );

      if (existentes.isNotEmpty) {
        final id = _int(existentes.first['id']);
        await transaction.update(
          'crm_leads',
          {
            'veiculo_id': _intNulo(row['veiculo_id']),
            'etapa': 'Orçamento',
            'servico_interesse': (row['servicos'] ?? '').toString(),
            'veiculo_interesse': (row['veiculo'] ?? '').toString(),
            'valor_potencial': _double(row['valor']),
            'proximo_contato': proximo,
            'atualizado_em': agora.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        await transaction.insert('crm_interacoes', {
          'lead_id': id,
          'tipo': 'Orçamento',
          'descricao': 'Orçamento #$orcamentoId vinculado ao funil.',
          'data_interacao': agora.toIso8601String(),
          'criado_em': agora.toIso8601String(),
        });
        return id;
      }

      return transaction.insert('crm_leads', {
        'nome': (row['nome'] ?? '').toString(),
        'telefone': (row['telefone'] ?? '').toString(),
        'email': (row['email'] ?? '').toString(),
        'cliente_id': clienteId,
        'veiculo_id': _intNulo(row['veiculo_id']),
        'origem': 'Cliente antigo',
        'servico_interesse': (row['servicos'] ?? '').toString(),
        'veiculo_interesse': (row['veiculo'] ?? '').toString(),
        'valor_potencial': _double(row['valor']),
        'etapa': 'Orçamento',
        'responsavel': '',
        'proximo_contato': proximo,
        'observacoes': 'Lead criado a partir do orçamento #$orcamentoId.',
        'motivo_perda': '',
        'agendamento_id': null,
        'criado_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
        'convertido_em': agora.toIso8601String(),
      });
    });
  }

  Future<CrmDesempenhoResumo> carregarDesempenho({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final database = await _databaseProvider();
    await _garantirEstrutura(database);
    final ini = DateTime(inicio.year, inicio.month, inicio.day);
    final limite = DateTime(
      fim.year,
      fim.month,
      fim.day,
    ).add(const Duration(days: 1));

    final leadRows = await database.query('crm_leads');
    final leadsPeriodo = leadRows.where((row) {
      final data = _parseData(row['criado_em']);
      return data != null && !data.isBefore(ini) && data.isBefore(limite);
    }).toList();

    var ganhos = 0;
    var perdidos = 0;
    var abertos = 0;
    var potencial = 0.0;
    var valorGanho = 0.0;
    final porOrigem = <String, _OrigemMutable>{};
    final motivos = <String, int>{};

    for (final row in leadsPeriodo) {
      final etapa = (row['etapa'] ?? '').toString();
      final origem = (row['origem'] ?? 'Outro').toString().trim();
      final valor = _double(row['valor_potencial']);
      potencial += valor;
      if (etapa == 'Ganho') {
        ganhos++;
        valorGanho += valor;
      } else if (etapa == 'Perdido') {
        perdidos++;
        final motivo = (row['motivo_perda'] ?? '').toString().trim();
        motivos[motivo.isEmpty ? 'Não informado' : motivo] =
            (motivos[motivo.isEmpty ? 'Não informado' : motivo] ?? 0) + 1;
      } else {
        abertos++;
      }
      final item = porOrigem.putIfAbsent(
        origem.isEmpty ? 'Outro' : origem,
        () => _OrigemMutable(),
      );
      item.total++;
      item.potencial += valor;
      if (etapa == 'Ganho') {
        item.ganhos++;
        item.valorGanho += valor;
      }
      if (etapa == 'Perdido') item.perdidos++;
    }

    final orcRows = await database.query('orcamentos');
    var orcCriados = 0;
    var orcAprovados = 0;
    var valorOrc = 0.0;
    var valorAprovado = 0.0;
    for (final row in orcRows) {
      final data = _parseData(row['data_emissao']);
      if (data == null || data.isBefore(ini) || !data.isBefore(limite)) {
        continue;
      }
      orcCriados++;
      final valor = _double(row['valor']);
      valorOrc += valor;
      if ((row['status'] ?? '').toString() == 'Aprovado') {
        orcAprovados++;
        valorAprovado += valor;
      }
    }

    final acoesRows = await database.query(
      tabelaAcoes,
      columns: ['concluida_em', 'status'],
      where: "status = 'Concluida'",
    );
    final acoesConcluidas = acoesRows.where((row) {
      final data = _parseData(row['concluida_em']);
      return data != null && !data.isBefore(ini) && data.isBefore(limite);
    }).length;

    final campanhaRows = await database.rawQuery(
      '''
      SELECT ca.id, ca.nome,
             COUNT(cp.id) AS gerados,
             SUM(CASE WHEN cp.status = 'Ativo' THEN 1 ELSE 0 END) AS ativos,
             SUM(CASE WHEN cp.status = 'Usado' THEN 1 ELSE 0 END) AS usados,
             SUM(CASE WHEN cp.status = 'Expirado' THEN 1 ELSE 0 END) AS expirados,
             COALESCE(SUM(CASE
               WHEN cp.status = 'Usado' THEN os.valor_total
               ELSE 0
             END), 0) AS receita_atribuida
      FROM crm_campanhas ca
      LEFT JOIN crm_cupons cp ON cp.campanha_id = ca.id
        AND datetime(cp.criado_em) >= datetime(?)
        AND datetime(cp.criado_em) < datetime(?)
      LEFT JOIN ordens_servico os ON os.id = cp.ordem_servico_id
      GROUP BY ca.id, ca.nome
      HAVING COUNT(cp.id) > 0
      ORDER BY usados DESC, gerados DESC, ca.nome COLLATE NOCASE ASC
    ''',
      [ini.toIso8601String(), limite.toIso8601String()],
    );

    final origens =
        porOrigem.entries
            .map(
              (entry) => CrmOrigemDesempenho(
                origem: entry.key,
                total: entry.value.total,
                ganhos: entry.value.ganhos,
                perdidos: entry.value.perdidos,
                valorPotencial: entry.value.potencial,
                valorGanho: entry.value.valorGanho,
              ),
            )
            .toList()
          ..sort((a, b) {
            final porGanhos = b.ganhos.compareTo(a.ganhos);
            return porGanhos != 0 ? porGanhos : b.total.compareTo(a.total);
          });

    final motivosLista =
        motivos.entries
            .map(
              (entry) => CrmMotivoPerdaResumo(
                motivo: entry.key,
                quantidade: entry.value,
              ),
            )
            .toList()
          ..sort((a, b) => b.quantidade.compareTo(a.quantidade));

    final campanhas = campanhaRows
        .map(
          (row) => CrmCampanhaDesempenho(
            nome: (row['nome'] ?? '').toString(),
            gerados: _int(row['gerados']),
            ativos: _int(row['ativos']),
            usados: _int(row['usados']),
            expirados: _int(row['expirados']),
            receitaAtribuida: _double(row['receita_atribuida']),
          ),
        )
        .toList();

    return CrmDesempenhoResumo(
      inicio: ini,
      fim: DateTime(fim.year, fim.month, fim.day),
      leadsCriados: leadsPeriodo.length,
      ganhos: ganhos,
      perdidos: perdidos,
      abertos: abertos,
      valorPotencial: potencial,
      valorGanho: valorGanho,
      orcamentosCriados: orcCriados,
      orcamentosAprovados: orcAprovados,
      valorOrcamentos: valorOrc,
      valorOrcamentosAprovados: valorAprovado,
      acoesConcluidas: acoesConcluidas,
      origens: origens,
      motivosPerda: motivosLista,
      campanhas: campanhas,
    );
  }

  static String _descricaoBeneficio(Map<String, dynamic> row) {
    final descricao = (row['beneficio_descricao'] ?? '').toString().trim();
    if (descricao.isNotEmpty) return descricao;
    final tipo = (row['beneficio_tipo'] ?? '').toString();
    final valor = _double(row['beneficio_valor']);
    if (tipo == 'Percentual') {
      return '${valor.toStringAsFixed(0)}% de benefício';
    }
    if (tipo == 'Valor' || tipo == 'Crédito') {
      return '${_moeda(valor)} de benefício';
    }
    return 'um benefício especial';
  }

  static DateTime _somenteDia(DateTime data) =>
      DateTime(data.year, data.month, data.day);

  static DateTime? _parseData(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;
    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso;
    final br = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(texto);
    if (br != null) {
      return DateTime(
        int.parse(br.group(3)!),
        int.parse(br.group(2)!),
        int.parse(br.group(1)!),
      );
    }
    return null;
  }

  static String _dataDia(DateTime data) =>
      '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';

  static String _dataBr(DateTime data) =>
      '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

  static String _moeda(double valor) {
    final fixo = valor.toStringAsFixed(2).replaceAll('.', ',');
    final partes = fixo.split(',');
    final inteiro = partes.first;
    final buffer = StringBuffer();
    for (var i = 0; i < inteiro.length; i++) {
      if (i > 0 && (inteiro.length - i) % 3 == 0) buffer.write('.');
      buffer.write(inteiro[i]);
    }
    return 'R\$ ${buffer.toString()},${partes.last}';
  }

  static String _primeiroNome(String nome) {
    final limpo = nome.trim();
    return limpo.isEmpty ? 'cliente' : limpo.split(RegExp(r'\s+')).first;
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}

class _OrigemMutable {
  int total = 0;
  int ganhos = 0;
  int perdidos = 0;
  double potencial = 0;
  double valorGanho = 0;
}
