import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../models/configuracao.dart';
import '../repositories/configuracao_repository.dart';
import 'supabase_bootstrap.dart';

/// Configuracoes Cloud V1.
///
/// Sincroniza apenas dados portaveis da empresa. Arquivos locais e metadados
/// de backup continuam locais e serao tratados por Storage em outra etapa.
class ConfiguracaoCloudService {
  ConfiguracaoCloudService._();

  static final ConfiguracaoCloudService instance = ConfiguracaoCloudService._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final ConfiguracaoRepository _repository = ConfiguracaoRepository();

  SupabaseClient? get _client => SupabaseBootstrap.client;

  // configuracoes-cloud-v1
  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        dispositivo_id TEXT NOT NULL,
        empresa_id TEXT,
        ultimo_sync_em TEXT
      )
    ''');

    final syncConfig = await database.query(
      'imperium_sync_config',
      columns: ['id'],
      where: 'id = 1',
      limit: 1,
    );

    if (syncConfig.isEmpty) {
      await database.insert('imperium_sync_config', {
        'id': 1,
        'dispositivo_id': _novoDispositivoId(),
        'empresa_id': null,
        'ultimo_sync_em': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_configuracao_empresa (
        empresa_id TEXT PRIMARY KEY,
        local_hash TEXT NOT NULL,
        remoto_atualizado_em TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_sync_configuracao_conflitos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empresa_id TEXT NOT NULL,
        motivo TEXT NOT NULL,
        local_hash_base TEXT,
        local_hash_atual TEXT,
        remoto_atualizado_base TEXT,
        remoto_atualizado_atual TEXT,
        local_json TEXT NOT NULL DEFAULT '',
        remoto_json TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Pendente',
        resolucao TEXT,
        resolucao_detalhe TEXT,
        detectado_em TEXT NOT NULL,
        resolvido_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_config_conflitos_pendentes
      ON imperium_sync_configuracao_conflitos (
        empresa_id,
        status,
        detectado_em
      )
    ''');
  }

  Future<void> sincronizar(String empresaId) async {
    final client = _client;
    if (empresaId.trim().isEmpty || client == null) return;

    try {
      await garantirEstruturaLocal();

      if (await possuiConflitoPendente(empresaId)) return;

      final local = await _repository.obterConfiguracao();
      final localHash = _hash(local);
      final mapa = await _mapa(empresaId);
      final remoto = await _buscarRemoto(empresaId);

      if (mapa == null) {
        if (remoto != null) {
          await _aplicarRemoto(remoto);
          final aplicado = await _repository.obterConfiguracao();
          await _salvarMapa(
            empresaId: empresaId,
            localHash: _hash(aplicado),
            remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
          );
          return;
        }

        final criado = await client
            .from('imperium_configuracoes_empresa')
            .upsert({
              'empresa_id': empresaId,
              ...await _payload(local),
            }, onConflict: 'empresa_id')
            .select('empresa_id,atualizado_em')
            .single();

        await _salvarMapa(
          empresaId: empresaId,
          localHash: localHash,
          remotoAtualizadoEm: criado['atualizado_em']?.toString(),
        );
        return;
      }

      final baseHash = _texto(mapa['local_hash']);
      final baseTs = _texto(mapa['remoto_atualizado_em']);
      final localMudou = localHash != baseHash;

      if (remoto == null) {
        await _registrarConflito(
          empresaId: empresaId,
          motivo: 'registro_remoto_ausente',
          mapa: mapa,
          local: local,
          localHashAtual: localHash,
          remoto: const <String, dynamic>{},
        );
        return;
      }

      final remotoTs = _texto(remoto['atualizado_em']);
      final remotoMudou = baseTs.isEmpty || remotoTs != baseTs;

      if (localMudou && remotoMudou) {
        await _registrarConflito(
          empresaId: empresaId,
          motivo: 'alteracao_concorrente',
          mapa: mapa,
          local: local,
          localHashAtual: localHash,
          remoto: remoto,
        );
        return;
      }

      if (localMudou) {
        final payload = await _payload(local);

        final List<dynamic> rows;
        if (baseTs.isEmpty) {
          rows = await client
              .from('imperium_configuracoes_empresa')
              .update(payload)
              .eq('empresa_id', empresaId)
              .select('empresa_id,atualizado_em');
        } else {
          rows = await client
              .from('imperium_configuracoes_empresa')
              .update(payload)
              .eq('empresa_id', empresaId)
              .eq('atualizado_em', baseTs)
              .select('empresa_id,atualizado_em');
        }

        if (rows.isEmpty) {
          final atual = await _buscarRemoto(empresaId);
          await _registrarConflito(
            empresaId: empresaId,
            motivo: 'cas_falhou_alteracao_concorrente',
            mapa: mapa,
            local: local,
            localHashAtual: localHash,
            remoto: atual ?? const <String, dynamic>{},
          );
          return;
        }

        await _salvarMapa(
          empresaId: empresaId,
          localHash: localHash,
          remotoAtualizadoEm: rows.first['atualizado_em']?.toString(),
        );
        return;
      }

      if (remotoMudou) {
        await _aplicarRemoto(remoto);
        final aplicado = await _repository.obterConfiguracao();

        await _salvarMapa(
          empresaId: empresaId,
          localHash: _hash(aplicado),
          remotoAtualizadoEm: remotoTs,
        );
      }
    } on PostgrestException catch (error) {
      if (error.code == '42501') return;
      rethrow;
    }
  }

  Future<bool> possuiConflitoPendente(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_configuracao_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    String? empresaId,
  }) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    return database.query(
      'imperium_sync_configuracao_conflitos',
      where: empresaId == null
          ? "status = 'Pendente'"
          : "empresa_id = ? AND status = 'Pendente'",
      whereArgs: empresaId == null ? null : [empresaId],
      orderBy: 'detectado_em DESC, id DESC',
    );
  }

  Future<void> resolverUsandoLocal(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final client = _client;

    if (client == null) {
      throw StateError('Supabase indisponível.');
    }

    final local = await _repository.obterConfiguracao();
    final remoto = await client
        .from('imperium_configuracoes_empresa')
        .upsert({
          'empresa_id': empresaId,
          ...await _payload(local),
        }, onConflict: 'empresa_id')
        .select('empresa_id,atualizado_em')
        .single();

    await _salvarMapa(
      empresaId: empresaId,
      localHash: _hash(local),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'local',
      detalhe: 'Configuração deste aparelho aplicada na nuvem.',
    );
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    final conflito = await _conflitoPendente(conflitoId);
    final empresaId = _texto(conflito['empresa_id']);
    final remoto = await _buscarRemoto(empresaId);

    if (remoto == null) {
      throw StateError('Configuração remota não existe mais.');
    }

    await _aplicarRemoto(remoto);
    final aplicado = await _repository.obterConfiguracao();

    await _salvarMapa(
      empresaId: empresaId,
      localHash: _hash(aplicado),
      remotoAtualizadoEm: remoto['atualizado_em']?.toString(),
    );

    await _encerrarConflito(
      conflitoId,
      resolucao: 'nuvem',
      detalhe: 'Configuração da nuvem aplicada neste aparelho.',
    );
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;
    final mapa = await _mapa(empresaId);

    final conflitos =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM imperium_sync_configuracao_conflitos
            WHERE empresa_id = ?
              AND status = 'Pendente'
            ''',
            [empresaId],
          ),
        ) ??
        0;

    return <String, Object?>{
      'empresa_id': empresaId,
      'mapeada': mapa != null,
      'remoto_atualizado_em': mapa?['remoto_atualizado_em'],
      'conflitos_pendentes': conflitos,
      'arquivos_locais_fora_do_cloud': true,
      'backup_local_fora_do_cloud': true,
    };
  }

  Future<Map<String, dynamic>?> _buscarRemoto(String empresaId) async {
    final client = _client;
    if (client == null) return null;

    final raw = await client
        .from('imperium_configuracoes_empresa')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  Future<Map<String, Object?>?> _mapa(String empresaId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_configuracao_empresa',
      where: 'empresa_id = ?',
      whereArgs: [empresaId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _salvarMapa({
    required String empresaId,
    required String localHash,
    String? remotoAtualizadoEm,
  }) async {
    final database = await _appDatabase.database;

    await database.insert(
      'imperium_sync_configuracao_empresa',
      {
        'empresa_id': empresaId,
        'local_hash': localHash,
        'remoto_atualizado_em': remotoAtualizadoEm,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>> _payload(Configuracao config) async {
    return <String, dynamic>{
      'nome_fantasia': config.nomeFantasia.trim(),
      'razao_social': config.razaoSocial.trim(),
      'cnpj': config.cnpj.trim(),
      'inscricao_estadual': config.inscricaoEstadual.trim(),
      'telefone': config.telefone.trim(),
      'whatsapp': config.whatsapp.trim(),
      'email': config.email.trim(),
      'site': config.site.trim(),
      'instagram': config.instagram.trim(),
      'facebook': config.facebook.trim(),
      'endereco': config.endereco.trim(),
      'numero': config.numero.trim(),
      'complemento': config.complemento.trim(),
      'bairro': config.bairro.trim(),
      'cidade': config.cidade.trim(),
      'estado': config.estado.trim(),
      'cep': config.cep.trim(),
      'nome_aplicativo': config.nomeAplicativo.trim(),
      'cor_principal': config.corPrincipal,
      'cor_secundaria': config.corSecundaria,
      'tema': config.tema.trim(),
      'validade_orcamento_dias': config.validadeOrcamentoDias,
      'rodape_documentos': config.rodapeDocumentos.trim(),
      'termos_orcamento': config.termosOrcamento.trim(),
      'termos_ordem_servico': config.termosOrdemServico.trim(),
      'observacao_padrao': config.observacaoPadrao.trim(),
      'mensagem_agradecimento': config.mensagemAgradecimento.trim(),
      'mensagem_orcamento': config.mensagemOrcamento.trim(),
      'mensagem_confirmacao': config.mensagemConfirmacao.trim(),
      'mensagem_entrega': config.mensagemEntrega.trim(),
      'mensagem_cobranca': config.mensagemCobranca.trim(),
      'origem_dispositivo': await _dispositivoId(),
      'origem_atualizado_em': config.atualizadoEm,
    };
  }

  Future<void> _aplicarRemoto(Map<String, dynamic> remoto) async {
    final atual = await _repository.obterConfiguracao();

    final nova = atual.copyWith(
      nomeFantasia: _texto(remoto['nome_fantasia']),
      razaoSocial: _texto(remoto['razao_social']),
      cnpj: _texto(remoto['cnpj']),
      inscricaoEstadual: _texto(remoto['inscricao_estadual']),
      telefone: _texto(remoto['telefone']),
      whatsapp: _texto(remoto['whatsapp']),
      email: _texto(remoto['email']),
      site: _texto(remoto['site']),
      instagram: _texto(remoto['instagram']),
      facebook: _texto(remoto['facebook']),
      endereco: _texto(remoto['endereco']),
      numero: _texto(remoto['numero']),
      complemento: _texto(remoto['complemento']),
      bairro: _texto(remoto['bairro']),
      cidade: _texto(remoto['cidade']),
      estado: _texto(remoto['estado']),
      cep: _texto(remoto['cep']),
      nomeAplicativo: _textoPadrao(
        remoto['nome_aplicativo'],
        atual.nomeAplicativo,
      ),
      corPrincipal: _inteiro(remoto['cor_principal'], atual.corPrincipal),
      corSecundaria: _inteiro(remoto['cor_secundaria'], atual.corSecundaria),
      tema: _textoPadrao(remoto['tema'], atual.tema),
      validadeOrcamentoDias: _inteiro(
        remoto['validade_orcamento_dias'],
        atual.validadeOrcamentoDias,
      ),
      rodapeDocumentos: _texto(remoto['rodape_documentos']),
      termosOrcamento: _texto(remoto['termos_orcamento']),
      termosOrdemServico: _texto(remoto['termos_ordem_servico']),
      observacaoPadrao: _texto(remoto['observacao_padrao']),
      mensagemAgradecimento: _texto(remoto['mensagem_agradecimento']),
      mensagemOrcamento: _texto(remoto['mensagem_orcamento']),
      mensagemConfirmacao: _texto(remoto['mensagem_confirmacao']),
      mensagemEntrega: _texto(remoto['mensagem_entrega']),
      mensagemCobranca: _texto(remoto['mensagem_cobranca']),
    );

    await _repository.salvarConfiguracao(nova);
  }

  String _hash(Configuracao config) {
    final dados = <Object?>[
      config.nomeFantasia.trim(),
      config.razaoSocial.trim(),
      config.cnpj.trim(),
      config.inscricaoEstadual.trim(),
      config.telefone.trim(),
      config.whatsapp.trim(),
      config.email.trim(),
      config.site.trim(),
      config.instagram.trim(),
      config.facebook.trim(),
      config.endereco.trim(),
      config.numero.trim(),
      config.complemento.trim(),
      config.bairro.trim(),
      config.cidade.trim(),
      config.estado.trim(),
      config.cep.trim(),
      config.nomeAplicativo.trim(),
      config.corPrincipal,
      config.corSecundaria,
      config.tema.trim(),
      config.validadeOrcamentoDias,
      config.rodapeDocumentos.trim(),
      config.termosOrcamento.trim(),
      config.termosOrdemServico.trim(),
      config.observacaoPadrao.trim(),
      config.mensagemAgradecimento.trim(),
      config.mensagemOrcamento.trim(),
      config.mensagemConfirmacao.trim(),
      config.mensagemEntrega.trim(),
      config.mensagemCobranca.trim(),
    ];

    return sha256.convert(utf8.encode(jsonEncode(dados))).toString();
  }

  Future<void> _registrarConflito({
    required String empresaId,
    required String motivo,
    required Map<String, Object?> mapa,
    required Configuracao local,
    required String localHashAtual,
    required Map<String, dynamic> remoto,
  }) async {
    final database = await _appDatabase.database;

    final existentes = await database.query(
      'imperium_sync_configuracao_conflitos',
      columns: ['id'],
      where: "empresa_id = ? AND status = 'Pendente'",
      whereArgs: [empresaId],
      limit: 1,
    );

    final dados = <String, Object?>{
      'empresa_id': empresaId,
      'motivo': motivo,
      'local_hash_base': _texto(mapa['local_hash']),
      'local_hash_atual': localHashAtual,
      'remoto_atualizado_base': _texto(mapa['remoto_atualizado_em']),
      'remoto_atualizado_atual': _texto(remoto['atualizado_em']),
      'local_json': jsonEncode(_jsonSeguro(local)),
      'remoto_json': jsonEncode(remoto),
      'status': 'Pendente',
      'resolucao': null,
      'resolucao_detalhe': null,
      'detectado_em': DateTime.now().toIso8601String(),
      'resolvido_em': null,
    };

    if (existentes.isEmpty) {
      await database.insert('imperium_sync_configuracao_conflitos', dados);
    } else {
      await database.update(
        'imperium_sync_configuracao_conflitos',
        dados,
        where: 'id = ?',
        whereArgs: [existentes.first['id']],
      );
    }
  }

  Map<String, Object?> _jsonSeguro(Configuracao config) {
    return <String, Object?>{
      'nome_fantasia': config.nomeFantasia,
      'razao_social': config.razaoSocial,
      'cnpj': config.cnpj,
      'telefone': config.telefone,
      'whatsapp': config.whatsapp,
      'email': config.email,
      'cidade': config.cidade,
      'estado': config.estado,
      'nome_aplicativo': config.nomeAplicativo,
      'tema': config.tema,
      'validade_orcamento_dias': config.validadeOrcamentoDias,
      'rodape_documentos': config.rodapeDocumentos,
      'termos_orcamento': config.termosOrcamento,
      'termos_ordem_servico': config.termosOrdemServico,
    };
  }

  Future<Map<String, Object?>> _conflitoPendente(int id) async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final rows = await database.query(
      'imperium_sync_configuracao_conflitos',
      where: "id = ? AND status = 'Pendente'",
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Conflito de configuração pendente não encontrado.');
    }

    return rows.first;
  }

  Future<void> _encerrarConflito(
    int id, {
    required String resolucao,
    required String detalhe,
  }) async {
    final database = await _appDatabase.database;

    await database.update(
      'imperium_sync_configuracao_conflitos',
      {
        'status': 'Resolvido',
        'resolucao': resolucao,
        'resolucao_detalhe': detalhe,
        'resolvido_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String> _dispositivoId() async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'imperium_sync_config',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final atual = _texto(rows.first['dispositivo_id']);
      if (atual.isNotEmpty) return atual;
    }

    final novo = _novoDispositivoId();
    await database.insert('imperium_sync_config', {
      'id': 1,
      'dispositivo_id': novo,
      'empresa_id': null,
      'ultimo_sync_em': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return novo;
  }

  String _novoDispositivoId() {
    final random = Random.secure();
    final tempo = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final aleatorio = List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    return '$tempo-$aleatorio';
  }

  static int _inteiro(Object? value, int padrao) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? padrao;
  }

  static String _texto(Object? value) => (value ?? '').toString().trim();

  static String _textoPadrao(Object? value, String padrao) {
    final texto = _texto(value);
    return texto.isEmpty ? padrao : texto;
  }
}
