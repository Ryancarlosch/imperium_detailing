import 'dart:io';

import '../database/app_database.dart';
import 'configuracao_repository.dart';
import 'custos_repository.dart';
import 'ponto_repository.dart';

enum PendenciaOperacionalTipo {
  recebimentoVencido,
  contaPagarVencida,
  contaPagarProxima,
  ordemServico,
  estoque,
  ponto,
  backup,
}

enum PendenciaOperacionalNivel { critica, atencao }

class PendenciaOperacional {
  const PendenciaOperacional({
    required this.tipo,
    required this.nivel,
    required this.titulo,
    required this.descricao,
    required this.modulo,
    this.valor,
    this.data,
    this.referenciaId,
  });

  final PendenciaOperacionalTipo tipo;
  final PendenciaOperacionalNivel nivel;
  final String titulo;
  final String descricao;
  final String modulo;
  final double? valor;
  final DateTime? data;
  final int? referenciaId;
}

class PendenciasOperacionaisResumo {
  const PendenciasOperacionaisResumo({
    required this.itens,
    required this.geradoEm,
  });

  final List<PendenciaOperacional> itens;
  final DateTime geradoEm;

  bool get possuiPendencias => itens.isNotEmpty;

  int get totalCriticas => itens
      .where((item) => item.nivel == PendenciaOperacionalNivel.critica)
      .length;

  int get totalAtencao => itens
      .where((item) => item.nivel == PendenciaOperacionalNivel.atencao)
      .length;

  List<PendenciaOperacional> porTipo(PendenciaOperacionalTipo tipo) {
    return itens.where((item) => item.tipo == tipo).toList(growable: false);
  }

  int quantidadePorTipo(PendenciaOperacionalTipo tipo) {
    return itens.where((item) => item.tipo == tipo).length;
  }

  double valorPorTipo(PendenciaOperacionalTipo tipo) {
    return itens
        .where((item) => item.tipo == tipo)
        .fold<double>(0, (total, item) => total + (item.valor ?? 0));
  }
}

class PendenciasOperacionaisRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final CustosRepository _custosRepository = CustosRepository();
  final PontoRepository _pontoRepository = PontoRepository();
  final ConfiguracaoRepository _configuracaoRepository =
      ConfiguracaoRepository();

  Future<PendenciasOperacionaisResumo> carregar() async {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    final resultados = await Future.wait<List<PendenciaOperacional>>([
      _carregarRecebimentosVencidos(hoje),
      _carregarContasPagar(hoje),
      _carregarOrdensParadas(hoje),
      _carregarEstoque(),
      _carregarPonto(hoje),
      _carregarBackup(hoje),
    ]);

    final itens = <PendenciaOperacional>[
      for (final grupo in resultados) ...grupo,
    ];

    itens.sort((a, b) {
      final nivel = a.nivel.index.compareTo(b.nivel.index);
      if (nivel != 0) return nivel;

      final tipo = a.tipo.index.compareTo(b.tipo.index);
      if (tipo != 0) return tipo;

      if (a.data != null && b.data != null) {
        return a.data!.compareTo(b.data!);
      }

      if (a.data != null) return -1;
      if (b.data != null) return 1;

      return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
    });

    return PendenciasOperacionaisResumo(
      itens: List.unmodifiable(itens),
      geradoEm: agora,
    );
  }

  Future<List<PendenciaOperacional>> _carregarRecebimentosVencidos(
    DateTime hoje,
  ) async {
    final database = await _appDatabase.database;
    final hojeBanco = _dataBanco(hoje);
    final itens = <PendenciaOperacional>[];

    final parcelas = await database.rawQuery(
      '''
      SELECT
        p.id,
        p.ordem_servico_id,
        p.valor,
        p.parcela_numero,
        p.total_parcelas,
        p.vencimento,
        os.numero,
        c.nome AS cliente_nome
      FROM ordem_servico_pagamentos p
      INNER JOIN ordens_servico os
        ON os.id = p.ordem_servico_id
      INNER JOIN clientes c
        ON c.id = os.cliente_id
      WHERE p.status = 'Pendente'
        AND p.vencimento IS NOT NULL
        AND date(p.vencimento) < date(?)
        AND os.status = 'Finalizada'
      ORDER BY date(p.vencimento) ASC, p.id ASC
      ''',
      [hojeBanco],
    );

    for (final item in parcelas) {
      final numero = (item['numero'] ?? 'OS').toString().trim();
      final cliente = (item['cliente_nome'] ?? '').toString().trim();
      final parcela = _int(item['parcela_numero']);
      final totalParcelas = _int(item['total_parcelas']);
      final vencimento = _parseData(item['vencimento']);
      final sufixoParcela = parcela > 0
          ? totalParcelas > 0
                ? ' • parcela $parcela/$totalParcelas'
                : ' • parcela $parcela'
          : '';

      itens.add(
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.recebimentoVencido,
          nivel: PendenciaOperacionalNivel.critica,
          titulo: '$numero$sufixoParcela',
          descricao: [
            if (cliente.isNotEmpty) cliente,
            if (vencimento != null) 'Venceu em ${_formatarData(vencimento)}',
          ].join(' • '),
          modulo: 'financeiro',
          valor: _double(item['valor']),
          data: vencimento,
          referenciaId: _intNulo(item['ordem_servico_id']),
        ),
      );
    }

    // Cobranças sem parcelamento: considera somente o saldo efetivamente
    // vencido da OS. Se existem parcelas pendentes, elas já foram tratadas
    // individualmente acima para não somar parcelas futuras como vencidas.
    final cobrancasSemParcela = await database.rawQuery(
      '''
      SELECT
        os.id,
        os.numero,
        os.vencimento_pagamento,
        c.nome AS cliente_nome,
        MAX(
          (
            COALESCE(os.valor_total, 0)
            - COALESCE(os.desconto, 0)
            - COALESCE(os.desconto_negociacao, 0)
            + COALESCE(os.acrescimo_negociacao, 0)
            + COALESCE(os.juros_parcelamento, 0)
          ) - COALESCE(os.valor_recebido, 0),
          0
        ) AS valor_pendente
      FROM ordens_servico os
      INNER JOIN clientes c
        ON c.id = os.cliente_id
      WHERE os.status = 'Finalizada'
        AND os.status_pagamento NOT IN ('Pago', 'Cancelado')
        AND os.vencimento_pagamento IS NOT NULL
        AND date(os.vencimento_pagamento) < date(?)
        AND NOT EXISTS (
          SELECT 1
          FROM ordem_servico_pagamentos p
          WHERE p.ordem_servico_id = os.id
            AND p.status = 'Pendente'
        )
      ORDER BY date(os.vencimento_pagamento) ASC, os.id ASC
      ''',
      [hojeBanco],
    );

    for (final item in cobrancasSemParcela) {
      final valor = _double(item['valor_pendente']);
      if (valor <= 0.000001) continue;

      final numero = (item['numero'] ?? 'OS').toString().trim();
      final cliente = (item['cliente_nome'] ?? '').toString().trim();
      final vencimento = _parseData(item['vencimento_pagamento']);

      itens.add(
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.recebimentoVencido,
          nivel: PendenciaOperacionalNivel.critica,
          titulo: '$numero • recebimento vencido',
          descricao: [
            if (cliente.isNotEmpty) cliente,
            if (vencimento != null) 'Venceu em ${_formatarData(vencimento)}',
          ].join(' • '),
          modulo: 'financeiro',
          valor: valor,
          data: vencimento,
          referenciaId: _intNulo(item['id']),
        ),
      );
    }

    return itens;
  }

  Future<List<PendenciaOperacional>> _carregarContasPagar(DateTime hoje) async {
    final database = await _appDatabase.database;
    final hojeBanco = _dataBanco(hoje);
    final limiteBanco = _dataBanco(hoje.add(const Duration(days: 7)));
    final itens = <PendenciaOperacional>[];

    final vencidas = await database.rawQuery(
      '''
      SELECT
        m.id,
        m.descricao,
        m.valor,
        m.data_vencimento,
        f.nome AS fornecedor_nome
      FROM movimentos_financeiros m
      LEFT JOIN fornecedores f
        ON f.id = m.fornecedor_id
      WHERE m.status = 'Previsto'
        AND LOWER(m.tipo) IN ('saída', 'saida')
        AND m.data_vencimento IS NOT NULL
        AND date(m.data_vencimento) < date(?)
        AND m.transferencia_id IS NULL
      ORDER BY date(m.data_vencimento) ASC, m.id ASC
      ''',
      [hojeBanco],
    );

    for (final item in vencidas) {
      final descricao = (item['descricao'] ?? 'Conta a pagar')
          .toString()
          .trim();
      final fornecedor = (item['fornecedor_nome'] ?? '').toString().trim();
      final vencimento = _parseData(item['data_vencimento']);

      itens.add(
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.contaPagarVencida,
          nivel: PendenciaOperacionalNivel.critica,
          titulo: descricao.isEmpty ? 'Conta a pagar vencida' : descricao,
          descricao: [
            if (fornecedor.isNotEmpty) fornecedor,
            if (vencimento != null) 'Venceu em ${_formatarData(vencimento)}',
          ].join(' • '),
          modulo: 'financeiro',
          valor: _double(item['valor']),
          data: vencimento,
          referenciaId: _intNulo(item['id']),
        ),
      );
    }

    final proximas = await database.rawQuery(
      '''
      SELECT
        m.id,
        m.descricao,
        m.valor,
        m.data_vencimento,
        f.nome AS fornecedor_nome
      FROM movimentos_financeiros m
      LEFT JOIN fornecedores f
        ON f.id = m.fornecedor_id
      WHERE m.status = 'Previsto'
        AND LOWER(m.tipo) IN ('saída', 'saida')
        AND m.data_vencimento IS NOT NULL
        AND date(m.data_vencimento) >= date(?)
        AND date(m.data_vencimento) <= date(?)
        AND m.transferencia_id IS NULL
      ORDER BY date(m.data_vencimento) ASC, m.id ASC
      ''',
      [hojeBanco, limiteBanco],
    );

    for (final item in proximas) {
      final descricao = (item['descricao'] ?? 'Conta a pagar')
          .toString()
          .trim();
      final fornecedor = (item['fornecedor_nome'] ?? '').toString().trim();
      final vencimento = _parseData(item['data_vencimento']);
      final venceHoje = vencimento != null && _mesmoDia(vencimento, hoje);

      itens.add(
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.contaPagarProxima,
          nivel: PendenciaOperacionalNivel.atencao,
          titulo: descricao.isEmpty ? 'Conta a pagar' : descricao,
          descricao: [
            if (fornecedor.isNotEmpty) fornecedor,
            if (venceHoje)
              'Vence hoje'
            else if (vencimento != null)
              'Vence em ${_formatarData(vencimento)}',
          ].join(' • '),
          modulo: 'financeiro',
          valor: _double(item['valor']),
          data: vencimento,
          referenciaId: _intNulo(item['id']),
        ),
      );
    }

    return itens;
  }

  Future<List<PendenciaOperacional>> _carregarOrdensParadas(
    DateTime hoje,
  ) async {
    final database = await _appDatabase.database;
    final limite = hoje.subtract(const Duration(days: 7));
    final limiteBanco = _dataBanco(limite);

    final resultado = await database.rawQuery(
      '''
      SELECT
        os.id,
        os.numero,
        os.status,
        os.data_abertura,
        os.data_inicio,
        c.nome AS cliente_nome,
        v.marca AS veiculo_marca,
        v.modelo AS veiculo_modelo,
        v.placa AS veiculo_placa
      FROM ordens_servico os
      INNER JOIN clientes c
        ON c.id = os.cliente_id
      LEFT JOIN veiculos v
        ON v.id = os.veiculo_id
      WHERE (
        LOWER(os.status) = 'aberta'
        AND date(os.data_abertura) < date(?)
      ) OR (
        LOWER(os.status) = 'em andamento'
        AND date(COALESCE(os.data_inicio, os.data_abertura)) < date(?)
      )
      ORDER BY
        date(COALESCE(os.data_inicio, os.data_abertura)) ASC,
        os.id ASC
      ''',
      [limiteBanco, limiteBanco],
    );

    final itens = <PendenciaOperacional>[];

    for (final item in resultado) {
      final status = (item['status'] ?? '').toString().trim();
      final dataBase = _parseData(
        status.toLowerCase() == 'em andamento'
            ? item['data_inicio'] ?? item['data_abertura']
            : item['data_abertura'],
      );
      final dias = dataBase == null
          ? 0
          : hoje.difference(_somenteDia(dataBase)).inDays;
      final numero = (item['numero'] ?? 'OS').toString().trim();
      final cliente = (item['cliente_nome'] ?? '').toString().trim();
      final marca = (item['veiculo_marca'] ?? '').toString().trim();
      final modelo = (item['veiculo_modelo'] ?? '').toString().trim();
      final placa = (item['veiculo_placa'] ?? '').toString().trim();
      final veiculo = [
        marca,
        modelo,
        if (placa.isNotEmpty) '($placa)',
      ].where((parte) => parte.trim().isNotEmpty).join(' ');

      itens.add(
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.ordemServico,
          nivel: dias > 14
              ? PendenciaOperacionalNivel.critica
              : PendenciaOperacionalNivel.atencao,
          titulo: '$numero • $status',
          descricao: [
            if (cliente.isNotEmpty) cliente,
            if (veiculo.isNotEmpty) veiculo,
            if (dias > 0) 'Há $dias dias',
          ].join(' • '),
          modulo: 'ordens_servico',
          data: dataBase,
          referenciaId: _intNulo(item['id']),
        ),
      );
    }

    return itens;
  }

  Future<List<PendenciaOperacional>> _carregarEstoque() async {
    final database = await _appDatabase.database;

    final resultado = await database.rawQuery('''
      SELECT
        id,
        nome,
        categoria,
        quantidade,
        quantidade_minima,
        unidade
      FROM itens_estoque
      WHERE ativo = 1
        AND (
          COALESCE(quantidade, 0) <= 0
          OR (
            COALESCE(quantidade_minima, 0) > 0
            AND COALESCE(quantidade, 0) <= quantidade_minima
          )
        )
      ORDER BY
        CASE WHEN COALESCE(quantidade, 0) <= 0 THEN 1 ELSE 2 END,
        nome COLLATE NOCASE ASC
      ''');

    return resultado
        .map((item) {
          final quantidade = _double(item['quantidade']);
          final minima = _double(item['quantidade_minima']);
          final unidade = (item['unidade'] ?? 'unidade').toString().trim();
          final nome = (item['nome'] ?? 'Produto').toString().trim();
          final zerado = quantidade <= 0.000001;

          return PendenciaOperacional(
            tipo: PendenciaOperacionalTipo.estoque,
            nivel: zerado
                ? PendenciaOperacionalNivel.critica
                : PendenciaOperacionalNivel.atencao,
            titulo: zerado ? 'Estoque zerado: $nome' : 'Estoque baixo: $nome',
            descricao: zerado
                ? 'Saldo atual: 0 $unidade'
                : 'Saldo ${_formatarQuantidade(quantidade)} $unidade • '
                      'mínimo ${_formatarQuantidade(minima)} $unidade',
            modulo: 'estoque',
            referenciaId: _intNulo(item['id']),
          );
        })
        .toList(growable: false);
  }

  Future<List<PendenciaOperacional>> _carregarPonto(DateTime hoje) async {
    await _pontoRepository.garantirEstrutura();

    final colaboradores = await _custosRepository.listarColaboradores();
    final inicio = DateTime(hoje.year, hoje.month, 1);
    final itens = <PendenciaOperacional>[];

    for (final colaborador in colaboradores) {
      final id = colaborador.id;
      if (id == null) continue;

      final resumo = await _pontoRepository.obterFechamentoMes(
        colaboradorId: id,
        inicio: inicio,
        fim: hoje,
      );

      final pendencias = _int(resumo['pendencias']);
      final incompletos = _int(resumo['incompletos']);

      if (pendencias <= 0 && incompletos <= 0) {
        continue;
      }

      final partes = <String>[];
      if (pendencias > 0) {
        partes.add(
          '$pendencias ${pendencias == 1 ? 'dia pendente' : 'dias pendentes'}',
        );
      }
      if (incompletos > 0) {
        partes.add(
          '$incompletos ${incompletos == 1 ? 'ponto incompleto' : 'pontos incompletos'}',
        );
      }

      itens.add(
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.ponto,
          nivel: incompletos > 0
              ? PendenciaOperacionalNivel.critica
              : PendenciaOperacionalNivel.atencao,
          titulo: 'Ponto • ${colaborador.nome}',
          descricao: partes.join(' • '),
          modulo: 'ponto',
          referenciaId: id,
        ),
      );
    }

    return itens;
  }

  Future<List<PendenciaOperacional>> _carregarBackup(DateTime hoje) async {
    final configuracao = await _configuracaoRepository.obterConfiguracao();
    final textoData = configuracao.ultimoBackupEm?.trim() ?? '';
    final caminho = configuracao.ultimoBackupCaminho?.trim() ?? '';

    if (textoData.isEmpty) {
      return const [
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.backup,
          nivel: PendenciaOperacionalNivel.critica,
          titulo: 'Backup ainda não realizado',
          descricao:
              'Crie a primeira cópia de segurança dos dados do Imperium.',
          modulo: 'configuracoes',
        ),
      ];
    }

    final dataBackup = _parseData(textoData);
    if (dataBackup == null) {
      return const [
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.backup,
          nivel: PendenciaOperacionalNivel.critica,
          titulo: 'Data do backup inválida',
          descricao: 'Crie uma nova cópia de segurança nas Configurações.',
          modulo: 'configuracoes',
        ),
      ];
    }

    if (caminho.isEmpty || !await _arquivoExiste(caminho)) {
      return [
        PendenciaOperacional(
          tipo: PendenciaOperacionalTipo.backup,
          nivel: PendenciaOperacionalNivel.critica,
          titulo: 'Arquivo do backup não encontrado',
          descricao:
              'O último backup registrado foi em ${_formatarData(dataBackup)}, '
              'mas o arquivo local não foi encontrado.',
          modulo: 'configuracoes',
          data: dataBackup,
        ),
      ];
    }

    final dias = hoje.difference(_somenteDia(dataBackup)).inDays;

    if (dias <= 7) {
      return const [];
    }

    return [
      PendenciaOperacional(
        tipo: PendenciaOperacionalTipo.backup,
        nivel: dias > 14
            ? PendenciaOperacionalNivel.critica
            : PendenciaOperacionalNivel.atencao,
        titulo: 'Backup desatualizado',
        descricao: 'Última cópia há $dias dias (${_formatarData(dataBackup)}).',
        modulo: 'configuracoes',
        data: dataBackup,
      ),
    ];
  }

  Future<bool> _arquivoExiste(String caminho) async {
    try {
      return await File(caminho).exists();
    } catch (_) {
      return false;
    }
  }

  static bool _mesmoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime _somenteDia(DateTime data) {
    return DateTime(data.year, data.month, data.day);
  }

  static DateTime? _parseData(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return iso;

    final partes = texto.split('/');
    if (partes.length == 3) {
      final dia = int.tryParse(partes[0]);
      final mes = int.tryParse(partes[1]);
      final ano = int.tryParse(partes[2]);

      if (dia != null && mes != null && ano != null) {
        return DateTime(ano, mes, dia);
      }
    }

    return null;
  }

  static String _dataBanco(DateTime data) {
    return '${data.year.toString().padLeft(4, '0')}-'
        '${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
  }

  static String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year.toString().padLeft(4, '0')}';
  }

  static String _formatarQuantidade(double valor) {
    if ((valor - valor.roundToDouble()).abs() < 0.000001) {
      return valor.toInt().toString();
    }

    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString().trim() ?? '') ?? 0;
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString().trim());
  }

  static double _double(dynamic valor) {
    if (valor is num) return valor.toDouble();

    return double.tryParse(
          valor?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }
}
