import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'ponto_nuvem_diagnostico_service.dart';
import 'ponto_offline_sync_service.dart';

class PontoEtapa1ValidacaoService {
  PontoEtapa1ValidacaoService._();

  static final PontoEtapa1ValidacaoService instance =
      PontoEtapa1ValidacaoService._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final PontoNuvemDiagnosticoService _diagnostico =
      PontoNuvemDiagnosticoService.instance;
  final PontoOfflineSyncService _offline = PontoOfflineSyncService.instance;

  Future<void> garantirEstrutura() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_ponto_validacao_etapa1 (
        empresa_id TEXT PRIMARY KEY,
        dois_aparelhos INTEGER NOT NULL DEFAULT 0,
        offline_online INTEGER NOT NULL DEFAULT 0,
        revogacao INTEGER NOT NULL DEFAULT 0,
        permissoes INTEGER NOT NULL DEFAULT 0,
        isolamento_multiempresa INTEGER NOT NULL DEFAULT 0,
        observacoes TEXT NOT NULL DEFAULT '',
        atualizado_em TEXT NOT NULL
      )
    ''');
  }

  Future<Map<String, dynamic>> carregarManual(String empresaId) async {
    await garantirEstrutura();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_ponto_validacao_etapa1',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return {
        'empresa_id': empresaId,
        'dois_aparelhos': false,
        'offline_online': false,
        'revogacao': false,
        'permissoes': false,
        'isolamento_multiempresa': false,
        'observacoes': '',
      };
    }

    final item = rows.first;
    return {
      'empresa_id': empresaId,
      'dois_aparelhos': _bool(item['dois_aparelhos']),
      'offline_online': _bool(item['offline_online']),
      'revogacao': _bool(item['revogacao']),
      'permissoes': _bool(item['permissoes']),
      'isolamento_multiempresa': _bool(item['isolamento_multiempresa']),
      'observacoes': (item['observacoes'] ?? '').toString(),
      'atualizado_em': item['atualizado_em'],
    };
  }

  Future<void> salvarManual({
    required String empresaId,
    required bool doisAparelhos,
    required bool offlineOnline,
    required bool revogacao,
    required bool permissoes,
    required bool isolamentoMultiempresa,
    String observacoes = '',
  }) async {
    if (empresaId.trim().isEmpty) {
      throw StateError('Empresa não identificada.');
    }

    await garantirEstrutura();
    final database = await _appDatabase.database;

    await database.insert(
      'imperium_ponto_validacao_etapa1',
      {
        'empresa_id': empresaId.trim(),
        'dois_aparelhos': doisAparelhos ? 1 : 0,
        'offline_online': offlineOnline ? 1 : 0,
        'revogacao': revogacao ? 1 : 0,
        'permissoes': permissoes ? 1 : 0,
        'isolamento_multiempresa': isolamentoMultiempresa ? 1 : 0,
        'observacoes': observacoes.trim(),
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>> executar({required String empresaId}) async {
    final empresa = empresaId.trim();
    if (empresa.isEmpty) {
      return const {
        'automatico_ok': false,
        'manual_ok': false,
        'concluida': false,
        'mensagem': 'Empresa não identificada.',
      };
    }

    await garantirEstrutura();

    final diagnostico = await _diagnostico.diagnosticar(
      empresaEsperadaId: empresa,
    );

    final pendentes = await _offline.contarPendentes();
    final banco = await _appDatabase.database;

    final vinculosLocais = await _empresasLocaisDoDispositivo(banco);
    final tenantLocalOk =
        vinculosLocais.isNotEmpty &&
        vinculosLocais.every((item) => item == empresa);

    final mapeamentosOutraEmpresa = await _contarMapeamentosOutraEmpresa(
      banco,
      empresaId: empresa,
    );

    final manual = await carregarManual(empresa);

    final manualOk =
        manual['dois_aparelhos'] == true &&
        manual['offline_online'] == true &&
        manual['revogacao'] == true &&
        manual['permissoes'] == true &&
        manual['isolamento_multiempresa'] == true;

    final automaticoOk =
        diagnostico['saudavel'] == true &&
        pendentes == 0 &&
        tenantLocalOk &&
        mapeamentosOutraEmpresa == 0;

    return {
      'empresa_id': empresa,
      'diagnostico': diagnostico,
      'backend_ok': diagnostico['saudavel'] == true,
      'migracao_ok': diagnostico['migracao_concluida'] == true,
      'realtime_ok': diagnostico['realtime_ponto_registros'] == true,
      'idempotencia_ok':
          diagnostico['rpc_batida_offline'] == true &&
          diagnostico['tabela_idempotencia'] == true,
      'fila_pendente': pendentes,
      'fila_ok': pendentes == 0,
      'tenant_local_ok': tenantLocalOk,
      'empresas_locais': vinculosLocais.toList()..sort(),
      'mapeamentos_outra_empresa': mapeamentosOutraEmpresa,
      'mapeamentos_ok': mapeamentosOutraEmpresa == 0,
      'automatico_ok': automaticoOk,
      'manual': manual,
      'manual_ok': manualOk,
      'concluida': automaticoOk && manualOk,
      'mensagem': automaticoOk && manualOk
          ? 'Etapa 1 homologada neste aparelho.'
          : 'Etapa 1 implementada. Conclua os itens pendentes de homologação.',
    };
  }

  Future<Set<String>> _empresasLocaisDoDispositivo(Database database) async {
    final empresas = <String>{};

    for (final tabela in const [
      'imperium_dispositivo_acesso',
      'imperium_dispositivo_empresa',
    ]) {
      if (!await _tabelaExiste(database, tabela)) continue;

      final colunas = await database.rawQuery('PRAGMA table_info($tabela)');
      final nomes = colunas
          .map((item) => (item['name'] ?? '').toString())
          .toSet();

      if (!nomes.contains('empresa_id')) continue;

      final rows = await database.query(tabela, columns: ['empresa_id']);

      for (final row in rows) {
        final id = (row['empresa_id'] ?? '').toString().trim();
        if (id.isNotEmpty) empresas.add(id);
      }
    }

    return empresas;
  }

  Future<int> _contarMapeamentosOutraEmpresa(
    Database database, {
    required String empresaId,
  }) async {
    if (!await _tabelaExiste(database, 'sincronizacao_ponto_colaboradores')) {
      return 0;
    }

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM sincronizacao_ponto_colaboradores
      WHERE empresa_id <> ?
      ''',
      [empresaId],
    );

    if (resultado.isEmpty) return 0;
    return _int(resultado.first['total']);
  }

  Future<bool> _tabelaExiste(Database database, String nome) async {
    final rows = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name = ?
      LIMIT 1
      ''',
      [nome],
    );

    return rows.isNotEmpty;
  }

  static bool _bool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor.toInt() == 1;
    final texto = valor?.toString().trim().toLowerCase() ?? '';
    return texto == '1' || texto == 'true' || texto == 'sim';
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
