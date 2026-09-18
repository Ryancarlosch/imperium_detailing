import '../database/app_database.dart';
import 'operacional_sync_service.dart';
import 'supabase_bootstrap.dart';

class MigracaoFinalAuditoriaItem {
  const MigracaoFinalAuditoriaItem({
    required this.chave,
    required this.titulo,
    required this.local,
    required this.cloud,
    required this.unidade,
    this.tolerancia = 0,
  });

  final String chave;
  final String titulo;
  final double local;
  final double cloud;
  final String unidade;
  final double tolerancia;

  double get diferenca => cloud - local;

  bool get confere => diferenca.abs() <= tolerancia;

  bool get inteiro => unidade == 'registros';
}

class MigracaoFinalAuditoriaResultado {
  const MigracaoFinalAuditoriaResultado({
    required this.empresaId,
    required this.geradoEmCloud,
    required this.itens,
  });

  final String empresaId;
  final DateTime? geradoEmCloud;
  final List<MigracaoFinalAuditoriaItem> itens;

  int get divergencias => itens.where((item) => !item.confere).length;

  bool get tudoConfere => divergencias == 0;
}

/// Gate somente leitura da migração final SQLite -> Cloud.
///
/// Compara o banco SQLite do tenant ativo com agregados protegidos por RLS no
/// Supabase. Não cria, altera ou apaga dados em nenhum dos lados.
class MigracaoFinalAuditoriaService {
  MigracaoFinalAuditoriaService._();

  static final MigracaoFinalAuditoriaService instance =
      MigracaoFinalAuditoriaService._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final OperacionalSyncService _operacional = OperacionalSyncService.instance;

  Future<MigracaoFinalAuditoriaResultado> auditar() async {
    final client = SupabaseBootstrap.client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Entre na conta Supabase antes de auditar a migração.');
    }

    final empresaId = await _operacional.empresaAtualId();
    if (empresaId == null || empresaId.trim().isEmpty) {
      throw StateError(
        'Nenhuma empresa ativa foi identificada neste aparelho.',
      );
    }

    final empresaLocal = await _appDatabase.empresaAtivaId;
    if (empresaLocal == null || empresaLocal.trim() != empresaId.trim()) {
      throw StateError(
        'O SQLite ativo não corresponde à empresa selecionada na nuvem.',
      );
    }

    final database = await _appDatabase.database;

    final local = <String, double>{
      'clientes_contagem': await _scalar(
        database,
        'SELECT COUNT(*) AS total FROM clientes',
      ),
      'veiculos_contagem': await _scalar(
        database,
        'SELECT COUNT(*) AS total FROM veiculos',
      ),
      'ordens_servico_contagem': await _scalar(
        database,
        'SELECT COUNT(*) AS total FROM ordens_servico',
      ),
      'estoque_itens_contagem': await _scalar(
        database,
        'SELECT COUNT(*) AS total FROM itens_estoque',
      ),
      'financeiro_movimentos_contagem': await _scalar(
        database,
        'SELECT COUNT(*) AS total FROM movimentos_financeiros',
      ),
      'pagamentos_os_contagem': await _scalar(
        database,
        'SELECT COUNT(*) AS total FROM ordem_servico_pagamentos',
      ),
      'estoque_quantidade_total': await _scalar(
        database,
        'SELECT COALESCE(SUM(quantidade), 0) AS total FROM itens_estoque',
      ),
      'financeiro_entradas_realizadas': await _scalar(database, '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM movimentos_financeiros
        WHERE LOWER(COALESCE(status, '')) = 'realizado'
          AND LOWER(COALESCE(tipo, '')) = 'entrada'
        '''),
      'financeiro_saidas_realizadas': await _scalar(database, '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM movimentos_financeiros
        WHERE LOWER(COALESCE(status, '')) = 'realizado'
          AND LOWER(COALESCE(tipo, '')) IN ('saida', 'saída')
        '''),
      'pagamentos_os_pagos_total': await _scalar(database, '''
        SELECT COALESCE(SUM(valor), 0) AS total
        FROM ordem_servico_pagamentos
        WHERE LOWER(COALESCE(status, '')) = 'pago'
        '''),
    };

    final resposta = await client.rpc(
      'imperium_migracao_auditoria_v1',
      params: {'p_empresa_id': empresaId},
    );

    if (resposta is! Map) {
      throw StateError(
        'A nuvem retornou um formato inválido para a auditoria.',
      );
    }

    final cloud = Map<String, dynamic>.from(resposta);

    MigracaoFinalAuditoriaItem item(
      String chave,
      String titulo,
      String unidade, {
      double tolerancia = 0,
    }) {
      return MigracaoFinalAuditoriaItem(
        chave: chave,
        titulo: titulo,
        local: local[chave] ?? 0,
        cloud: _numero(cloud[chave]),
        unidade: unidade,
        tolerancia: tolerancia,
      );
    }

    final itens = <MigracaoFinalAuditoriaItem>[
      item('clientes_contagem', 'Clientes', 'registros'),
      item('veiculos_contagem', 'Veículos', 'registros'),
      item('ordens_servico_contagem', 'Ordens de Serviço', 'registros'),
      item('estoque_itens_contagem', 'Itens de estoque', 'registros'),
      item(
        'financeiro_movimentos_contagem',
        'Movimentos financeiros',
        'registros',
      ),
      item('pagamentos_os_contagem', 'Pagamentos de OS', 'registros'),
      item(
        'estoque_quantidade_total',
        'Quantidade total em estoque',
        'quantidade',
        tolerancia: 0.000001,
      ),
      item(
        'financeiro_entradas_realizadas',
        'Entradas financeiras realizadas',
        'moeda',
        tolerancia: 0.01,
      ),
      item(
        'financeiro_saidas_realizadas',
        'Saídas financeiras realizadas',
        'moeda',
        tolerancia: 0.01,
      ),
      item(
        'pagamentos_os_pagos_total',
        'Total de pagamentos de OS pagos',
        'moeda',
        tolerancia: 0.01,
      ),
    ];

    return MigracaoFinalAuditoriaResultado(
      empresaId: empresaId,
      geradoEmCloud: DateTime.tryParse((cloud['gerado_em'] ?? '').toString()),
      itens: itens,
    );
  }

  Future<double> _scalar(dynamic database, String sql) async {
    final linhas = await database.rawQuery(sql);
    if (linhas.isEmpty) return 0;

    return _numero(linhas.first['total']);
  }

  double _numero(Object? valor) {
    if (valor is num) return valor.toDouble();

    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return 0;

    return double.tryParse(texto.replaceAll(',', '.')) ?? 0;
  }
}
