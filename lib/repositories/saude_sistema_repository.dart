import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../services/operacional_sync_service.dart';
import '../services/os_cloud_upload_service.dart';
import '../services/ponto_nuvem_diagnostico_service.dart';
import '../services/ponto_offline_sync_service.dart';
import '../services/supabase_bootstrap.dart';
import 'ponto_repository.dart';
import 'usuario_repository.dart';

enum SaudeNivel { informacao, ok, atencao, critico }

class SaudeItem {
  const SaudeItem({
    required this.chave,
    required this.titulo,
    required this.detalhe,
    required this.nivel,
  });

  final String chave;
  final String titulo;
  final String detalhe;
  final SaudeNivel nivel;
}

class SaudeCoberturaSync {
  const SaudeCoberturaSync({
    required this.entidade,
    required this.locais,
    required this.mapeados,
  });

  final String entidade;
  final int locais;
  final int mapeados;

  int get pendentes => locais > mapeados ? locais - mapeados : 0;

  double get percentual {
    if (locais <= 0) {
      return 100;
    }
    return (mapeados / locais * 100).clamp(0, 100).toDouble();
  }
}

class SaudeAcessosResumo {
  const SaudeAcessosResumo({
    required this.usuariosAtivos,
    required this.usuariosInativos,
    required this.usuariosSemPin,
    required this.sucessos24h,
    required this.falhas24h,
    required this.acessosRecentes,
  });

  final int usuariosAtivos;
  final int usuariosInativos;
  final int usuariosSemPin;
  final int sucessos24h;
  final int falhas24h;
  final List<Map<String, dynamic>> acessosRecentes;
}

class SaudeSistemaResumo {
  const SaudeSistemaResumo({
    required this.versaoSchema,
    required this.sqliteIntegro,
    required this.sqliteMensagem,
    required this.violacoesForeignKey,
    required this.contagens,
    required this.coberturaSync,
    required this.exclusoesSyncPendentes,
    required this.pontoPendentes,
    required this.tenantsMapeados,
    required this.empresaCache,
    required this.ultimoSyncEm,
    required this.itens,
    required this.acessos,
  });

  final int versaoSchema;
  final bool sqliteIntegro;
  final String sqliteMensagem;
  final int violacoesForeignKey;
  final Map<String, int> contagens;
  final List<SaudeCoberturaSync> coberturaSync;
  final int exclusoesSyncPendentes;
  final int pontoPendentes;
  final int tenantsMapeados;
  final String? empresaCache;
  final String? ultimoSyncEm;
  final List<SaudeItem> itens;
  final SaudeAcessosResumo acessos;

  int get criticos =>
      itens.where((item) => item.nivel == SaudeNivel.critico).length;

  int get atencoes =>
      itens.where((item) => item.nivel == SaudeNivel.atencao).length;

  bool get saudavelLocal => criticos == 0;

  String gerarRelatorio() {
    final buffer = StringBuffer()
      ..writeln('IMPERIUM MANAGER - RELATÓRIO DE SAÚDE')
      ..writeln('Gerado em: ${DateTime.now().toIso8601String()}')
      ..writeln('Schema: $versaoSchema / esperado ${AppDatabase.schemaVersion}')
      ..writeln('SQLite: ${sqliteIntegro ? 'OK' : 'FALHA'} - $sqliteMensagem')
      ..writeln('Foreign keys: $violacoesForeignKey violação(ões)')
      ..writeln('Empresa local: ${_mascararId(empresaCache)}')
      ..writeln('Último sync: ${ultimoSyncEm ?? 'nunca registrado'}')
      ..writeln('Tenants mapeados neste aparelho: $tenantsMapeados')
      ..writeln('Exclusões aguardando sync: $exclusoesSyncPendentes')
      ..writeln('Batidas de ponto aguardando sync: $pontoPendentes')
      ..writeln('')
      ..writeln('CONTAGENS LOCAIS');

    for (final entry in contagens.entries) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }

    buffer
      ..writeln('')
      ..writeln('COBERTURA DE SINCRONIZAÇÃO');

    for (final item in coberturaSync) {
      buffer.writeln(
        '- ${item.entidade}: ${item.mapeados}/${item.locais} '
        '(${item.percentual.toStringAsFixed(1)}%)',
      );
    }

    buffer
      ..writeln('')
      ..writeln('ACESSOS')
      ..writeln('- usuários ativos: ${acessos.usuariosAtivos}')
      ..writeln('- usuários sem PIN: ${acessos.usuariosSemPin}')
      ..writeln('- sucessos 24h: ${acessos.sucessos24h}')
      ..writeln('- falhas 24h: ${acessos.falhas24h}')
      ..writeln('')
      ..writeln('ALERTAS');

    if (itens.isEmpty) {
      buffer.writeln('- Nenhuma inconsistência local detectada.');
    } else {
      for (final item in itens) {
        buffer.writeln(
          '- [${item.nivel.name.toUpperCase()}] ${item.titulo}: ${item.detalhe}',
        );
      }
    }

    return buffer.toString().trimRight();
  }

  static String _mascararId(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return 'não identificada';
    }
    if (texto.length <= 10) {
      return texto;
    }
    return '${texto.substring(0, 6)}…${texto.substring(texto.length - 4)}';
  }
}

class SaudeSistemaRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final OperacionalSyncService _operacional = OperacionalSyncService.instance;
  final OsCloudUploadService _osCloud = OsCloudUploadService.instance;
  final PontoOfflineSyncService _pontoOffline =
      PontoOfflineSyncService.instance;
  final PontoRepository _pontoRepository = PontoRepository();
  final UsuarioRepository _usuarioRepository = UsuarioRepository();

  Future<SaudeSistemaResumo> diagnosticarLocal() async {
    await _operacional.garantirEstruturaLocal();
    await _osCloud.garantirEstruturaLocal();
    await _pontoOffline.garantirEstrutura();
    await _pontoRepository.garantirEstrutura();
    await _usuarioRepository.garantirEstrutura();

    final database = await _appDatabase.database;
    final tabelas = await _listarTabelas(database);
    final versaoSchema = await database.getVersion();
    final quickCheck = await database.rawQuery('PRAGMA quick_check');
    final quickMensagem = quickCheck.isEmpty
        ? 'sem resposta'
        : quickCheck.first.values.first?.toString().trim() ?? 'sem resposta';
    final sqliteIntegro = quickMensagem.toLowerCase() == 'ok';
    final foreignKeys = await database.rawQuery('PRAGMA foreign_key_check');

    final contagens = <String, int>{
      'Clientes': await _contar(database, tabelas, 'clientes'),
      'Veículos': await _contar(database, tabelas, 'veiculos'),
      'Agenda': await _contar(database, tabelas, 'agendamentos'),
      'Ordens de serviço': await _contar(database, tabelas, 'ordens_servico'),
      'Itens de estoque': await _contar(database, tabelas, 'itens_estoque'),
      'Movimentos financeiros': await _contar(
        database,
        tabelas,
        'movimentos_financeiros',
      ),
      'Notas fiscais': await _contar(
        database,
        tabelas,
        'notas_fiscais_entrada',
      ),
      'Leads CRM': await _contar(database, tabelas, 'crm_leads'),
      'Registros de ponto': await _contar(
        database,
        tabelas,
        'financeiro_ponto_registros',
      ),
    };

    final configSync = await _primeiraLinha(
      database,
      tabelas,
      'imperium_sync_config',
    );
    final empresaCache = (configSync?['empresa_id'] ?? '').toString().trim();
    final ultimoSyncEm = (configSync?['ultimo_sync_em'] ?? '')
        .toString()
        .trim();

    final cobertura = <SaudeCoberturaSync>[
      SaudeCoberturaSync(
        entidade: 'Clientes',
        locais: contagens['Clientes'] ?? 0,
        mapeados: await _contarMapeados(
          database,
          tabelas,
          'imperium_sync_clientes',
          empresaCache,
        ),
      ),
      SaudeCoberturaSync(
        entidade: 'Veículos',
        locais: contagens['Veículos'] ?? 0,
        mapeados: await _contarMapeados(
          database,
          tabelas,
          'imperium_sync_veiculos',
          empresaCache,
        ),
      ),
      SaudeCoberturaSync(
        entidade: 'Agenda',
        locais: contagens['Agenda'] ?? 0,
        mapeados: await _contarMapeados(
          database,
          tabelas,
          'imperium_sync_agendamentos',
          empresaCache,
        ),
      ),
      SaudeCoberturaSync(
        entidade: 'OS',
        locais: contagens['Ordens de serviço'] ?? 0,
        mapeados: await _contarMapeados(
          database,
          tabelas,
          'imperium_sync_ordens_servico',
          empresaCache,
        ),
      ),
    ];

    final exclusoesSyncPendentes = await _contar(
      database,
      tabelas,
      'imperium_sync_exclusoes',
    );
    final pontoPendentes = await _pontoOffline.contarPendentes();
    final tenantsMapeados = await _contarTenantsMapeados(database, tabelas);
    final acessos = await _diagnosticarAcessos(database, tabelas);

    final itens = <SaudeItem>[];

    if (!sqliteIntegro) {
      itens.add(
        SaudeItem(
          chave: 'sqlite_integridade',
          titulo: 'Integridade do banco local',
          detalhe: 'PRAGMA quick_check retornou: $quickMensagem.',
          nivel: SaudeNivel.critico,
        ),
      );
    }

    if (versaoSchema != AppDatabase.schemaVersion) {
      itens.add(
        SaudeItem(
          chave: 'schema_divergente',
          titulo: 'Versão do banco divergente',
          detalhe:
              'Banco em $versaoSchema, aplicativo espera ${AppDatabase.schemaVersion}.',
          nivel: SaudeNivel.critico,
        ),
      );
    }

    if (foreignKeys.isNotEmpty) {
      itens.add(
        SaudeItem(
          chave: 'foreign_keys',
          titulo: 'Vínculos quebrados no SQLite',
          detalhe:
              '${foreignKeys.length} referência(s) inválida(s) encontrada(s).',
          nivel: SaudeNivel.critico,
        ),
      );
    }

    final estoqueNegativo = await _scalar(
      database,
      tabelas,
      'itens_estoque',
      '''
      SELECT COUNT(*)
      FROM itens_estoque
      WHERE ativo = 1
        AND quantidade < -0.000001
      ''',
    );
    if (estoqueNegativo > 0) {
      itens.add(
        SaudeItem(
          chave: 'estoque_negativo',
          titulo: 'Estoque negativo',
          detalhe:
              '$estoqueNegativo item(ns) ativo(s) com saldo abaixo de zero.',
          nivel: SaudeNivel.critico,
        ),
      );
    }

    final notasSemItens = await _scalar(
      database,
      tabelas,
      'notas_fiscais_entrada',
      '''
      SELECT COUNT(*)
      FROM notas_fiscais_entrada n
      WHERE n.status_importacao = 'processada'
        AND NOT EXISTS (
          SELECT 1
          FROM notas_fiscais_entrada_itens i
          WHERE i.nota_fiscal_id = n.id
        )
      ''',
      tabelasObrigatorias: const ['notas_fiscais_entrada_itens'],
    );
    if (notasSemItens > 0) {
      itens.add(
        SaudeItem(
          chave: 'nota_processada_sem_itens',
          titulo: 'Nota fiscal processada sem itens',
          detalhe:
              '$notasSemItens nota(s) marcada(s) como processada(s) sem produtos.',
          nivel: SaudeNivel.atencao,
        ),
      );
    }

    final movimentosDocumentoVazio = await _scalar(
      database,
      tabelas,
      'movimentos_financeiros',
      '''
      SELECT COUNT(*)
      FROM movimentos_financeiros
      WHERE status != 'Cancelado'
        AND TRIM(COALESCE(numero_documento, '')) = ''
      ''',
    );
    if (movimentosDocumentoVazio > 0) {
      itens.add(
        SaudeItem(
          chave: 'movimento_sem_documento',
          titulo: 'Movimentos sem documento',
          detalhe:
              '$movimentosDocumentoVazio movimento(s) ativo(s) sem número de documento.',
          nivel: SaudeNivel.atencao,
        ),
      );
    }

    final duplicidadesFiscais = await _scalar(
      database,
      tabelas,
      'movimentos_financeiros',
      '''
      SELECT COUNT(*)
      FROM (
        SELECT nota_fiscal_id, COALESCE(parcela_numero, 1) AS parcela
        FROM movimentos_financeiros
        WHERE nota_fiscal_id IS NOT NULL
          AND origem = 'Nota fiscal de entrada'
          AND status != 'Cancelado'
        GROUP BY nota_fiscal_id, COALESCE(parcela_numero, 1)
        HAVING COUNT(*) > 1
      ) duplicados
      ''',
    );
    if (duplicidadesFiscais > 0) {
      itens.add(
        SaudeItem(
          chave: 'financeiro_fiscal_duplicado',
          titulo: 'Parcela fiscal duplicada',
          detalhe:
              '$duplicidadesFiscais nota/parcela(s) possui(em) mais de um lançamento ativo.',
          nivel: SaudeNivel.critico,
        ),
      );
    }

    final veiculosOrfaos = await _scalar(
      database,
      tabelas,
      'veiculos',
      '''
      SELECT COUNT(*)
      FROM veiculos v
      LEFT JOIN clientes c ON c.id = v.cliente_id
      WHERE c.id IS NULL
      ''',
      tabelasObrigatorias: const ['clientes'],
    );
    if (veiculosOrfaos > 0) {
      itens.add(
        SaudeItem(
          chave: 'veiculos_orfaos',
          titulo: 'Veículos sem cliente válido',
          detalhe:
              '$veiculosOrfaos veículo(s) perdeu(ram) o vínculo com cliente.',
          nivel: SaudeNivel.critico,
        ),
      );
    }

    if (tenantsMapeados > 1) {
      itens.add(
        SaudeItem(
          chave: 'multiplos_tenants_local',
          titulo: 'Mais de uma empresa nos mapas locais',
          detalhe:
              '$tenantsMapeados empresas diferentes aparecem nos mapas de sincronização deste aparelho.',
          nivel: SaudeNivel.atencao,
        ),
      );
    }

    if (exclusoesSyncPendentes > 0) {
      itens.add(
        SaudeItem(
          chave: 'exclusoes_sync_pendentes',
          titulo: 'Exclusões aguardando nuvem',
          detalhe:
              '$exclusoesSyncPendentes exclusão(ões) local(is) ainda não foi(ram) sincronizada(s).',
          nivel: SaudeNivel.atencao,
        ),
      );
    }

    if (pontoPendentes > 0) {
      itens.add(
        SaudeItem(
          chave: 'ponto_offline_pendente',
          titulo: 'Batidas de ponto aguardando sincronização',
          detalhe: '$pontoPendentes batida(s) offline ainda está(ão) na fila.',
          nivel: SaudeNivel.atencao,
        ),
      );
    }

    for (final item in cobertura) {
      if (item.pendentes <= 0) {
        continue;
      }
      itens.add(
        SaudeItem(
          chave: 'sync_${item.entidade.toLowerCase()}',
          titulo: '${item.entidade} ainda não totalmente mapeado(s)',
          detalhe:
              '${item.mapeados}/${item.locais} registro(s) possui(em) vínculo local ↔ nuvem.',
          nivel: SaudeNivel.informacao,
        ),
      );
    }

    if (acessos.usuariosSemPin > 0) {
      itens.add(
        SaudeItem(
          chave: 'usuarios_sem_pin',
          titulo: 'Usuários ativos sem PIN',
          detalhe:
              '${acessos.usuariosSemPin} usuário(s) ativo(s) ainda não possui(em) PIN configurado.',
          nivel: SaudeNivel.atencao,
        ),
      );
    }

    if (acessos.falhas24h >= 5) {
      itens.add(
        SaudeItem(
          chave: 'falhas_login_24h',
          titulo: 'Muitas falhas de login recentes',
          detalhe:
              '${acessos.falhas24h} tentativa(s) falharam nas últimas 24 horas.',
          nivel: SaudeNivel.atencao,
        ),
      );
    }

    return SaudeSistemaResumo(
      versaoSchema: versaoSchema,
      sqliteIntegro: sqliteIntegro,
      sqliteMensagem: quickMensagem,
      violacoesForeignKey: foreignKeys.length,
      contagens: contagens,
      coberturaSync: cobertura,
      exclusoesSyncPendentes: exclusoesSyncPendentes,
      pontoPendentes: pontoPendentes,
      tenantsMapeados: tenantsMapeados,
      empresaCache: empresaCache.isEmpty ? null : empresaCache,
      ultimoSyncEm: ultimoSyncEm.isEmpty ? null : ultimoSyncEm,
      itens: itens,
      acessos: acessos,
    );
  }

  Future<Map<String, dynamic>> diagnosticarNuvem() async {
    final client = SupabaseBootstrap.client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) {
      return {
        'saudavel': false,
        'conectado': false,
        'mensagem': SupabaseBootstrap.inicializado
            ? 'Nenhuma conta Supabase autenticada neste aparelho.'
            : 'Supabase ainda não foi inicializado neste aparelho.',
      };
    }

    final empresaId = await _operacional.empresaAtualId();
    if (empresaId == null || empresaId.trim().isEmpty) {
      return {
        'saudavel': false,
        'conectado': true,
        'usuario_autenticado': true,
        'mensagem':
            'Conta autenticada, mas a empresa atual não foi identificada.',
      };
    }

    final ponto = await PontoNuvemDiagnosticoService.instance.diagnosticar(
      empresaEsperadaId: empresaId,
    );

    return {
      'conectado': true,
      'usuario_autenticado': true,
      'empresa_id': empresaId,
      'ponto': ponto,
      'saudavel': ponto['saudavel'] == true,
      'mensagem': ponto['saudavel'] == true
          ? 'Supabase autenticado e diagnóstico do Ponto aprovado.'
          : (ponto['mensagem'] ?? 'A nuvem respondeu com pendências.')
                .toString(),
    };
  }

  Future<bool> sincronizarAgora() async {
    final client = SupabaseBootstrap.client;
    if (client?.auth.currentUser == null) {
      return false;
    }

    final empresaId = await _operacional.empresaAtualId();
    if (empresaId == null || empresaId.trim().isEmpty) {
      return false;
    }

    await _operacional.sincronizarTudo();
    return true;
  }

  Future<int> sincronizarPontoPendente() async {
    return _pontoOffline.sincronizarPendentes();
  }

  Future<Set<String>> _listarTabelas(Database database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    return rows
        .map((row) => (row['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<int> _contar(
    Database database,
    Set<String> tabelas,
    String tabela,
  ) async {
    if (!tabelas.contains(tabela)) return 0;
    return Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM $tabela'),
        ) ??
        0;
  }

  Future<int> _contarMapeados(
    Database database,
    Set<String> tabelas,
    String tabela,
    String empresaId,
  ) async {
    if (!tabelas.contains(tabela)) {
      return 0;
    }

    if (empresaId.trim().isEmpty) {
      return _contar(database, tabelas, tabela);
    }

    return Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM $tabela WHERE empresa_id = ?',
            [empresaId.trim()],
          ),
        ) ??
        0;
  }

  Future<int> _scalar(
    Database database,
    Set<String> tabelas,
    String tabela,
    String sql, {
    List<String> tabelasObrigatorias = const [],
  }) async {
    if (!tabelas.contains(tabela)) return 0;
    if (tabelasObrigatorias.any((item) => !tabelas.contains(item))) return 0;

    return Sqflite.firstIntValue(await database.rawQuery(sql)) ?? 0;
  }

  Future<Map<String, Object?>?> _primeiraLinha(
    Database database,
    Set<String> tabelas,
    String tabela,
  ) async {
    if (!tabelas.contains(tabela)) return null;
    final rows = await database.query(tabela, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> _contarTenantsMapeados(
    Database database,
    Set<String> tabelas,
  ) async {
    final tabelasMapeamento = <String>[
      'imperium_sync_clientes',
      'imperium_sync_veiculos',
      'imperium_sync_agendamentos',
      'imperium_sync_ordens_servico',
      'imperium_sync_ordem_servico_itens',
    ].where(tabelas.contains).toList();

    if (tabelasMapeamento.isEmpty) {
      return 0;
    }

    final union = tabelasMapeamento
        .map((tabela) => 'SELECT empresa_id FROM $tabela')
        .join(' UNION ALL ');
    final rows = await database.rawQuery(
      'SELECT COUNT(DISTINCT empresa_id) AS total FROM ($union) AS mapas',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<SaudeAcessosResumo> _diagnosticarAcessos(
    Database database,
    Set<String> tabelas,
  ) async {
    if (!tabelas.contains('financeiro_usuarios') ||
        !tabelas.contains('financeiro_usuario_acessos')) {
      return const SaudeAcessosResumo(
        usuariosAtivos: 0,
        usuariosInativos: 0,
        usuariosSemPin: 0,
        sucessos24h: 0,
        falhas24h: 0,
        acessosRecentes: [],
      );
    }

    final usuariosAtivos =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM financeiro_usuarios WHERE ativo = 1',
          ),
        ) ??
        0;
    final usuariosInativos =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM financeiro_usuarios WHERE ativo = 0',
          ),
        ) ??
        0;
    final usuariosSemPin =
        Sqflite.firstIntValue(
          await database.rawQuery('''
            SELECT COUNT(*)
            FROM financeiro_usuarios
            WHERE ativo = 1
              AND (
                pin_hash IS NULL OR TRIM(pin_hash) = '' OR
                pin_salt IS NULL OR TRIM(pin_salt) = ''
              )
          '''),
        ) ??
        0;

    final desde = DateTime.now()
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    final sucessos24h =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM financeiro_usuario_acessos
            WHERE sucesso = 1
              AND criado_em >= ?
            ''',
            [desde],
          ),
        ) ??
        0;
    final falhas24h =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM financeiro_usuario_acessos
            WHERE sucesso = 0
              AND criado_em >= ?
            ''',
            [desde],
          ),
        ) ??
        0;

    final acessosRecentes = await _usuarioRepository.listarAcessos(limite: 50);

    return SaudeAcessosResumo(
      usuariosAtivos: usuariosAtivos,
      usuariosInativos: usuariosInativos,
      usuariosSemPin: usuariosSemPin,
      sucessos24h: sucessos24h,
      falhas24h: falhas24h,
      acessosRecentes: acessosRecentes,
    );
  }
}
