import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../models/colaborador_custo.dart';
import '../repositories/custos_repository.dart';
import '../repositories/usuario_repository.dart';
import 'ponto_nuvem_service.dart';
import 'supabase_bootstrap.dart';

class FuncionarioAcessoService {
  FuncionarioAcessoService._();

  static final FuncionarioAcessoService instance = FuncionarioAcessoService._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final CustosRepository _custosRepository = CustosRepository();
  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  final PontoNuvemService _pontoNuvem = PontoNuvemService.instance;

  SupabaseClient? get _client => SupabaseBootstrap.client;

  static const String redirectUrl = 'imperiumdetailing://login-callback/';

  static const Set<String> modulosRemotosProntos = <String>{
    'ponto',
    'clientes',
    'agenda',
  };

  Future<void> garantirEstruturaLocal() async {
    final database = await _appDatabase.database;

    await database.execute('''
      CREATE TABLE IF NOT EXISTS imperium_dispositivo_acesso (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        modo TEXT NOT NULL,
        empresa_id TEXT,
        colaborador_remoto_id TEXT,
        colaborador_local_id INTEGER,
        usuario_local_id INTEGER,
        auth_user_id TEXT,
        email TEXT,
        login TEXT,
        dispositivo_id TEXT,
        ponto_nuvem_ativo INTEGER NOT NULL DEFAULT 0,
        ultimo_sync_permissoes_em TEXT,
        atualizado_em TEXT NOT NULL
      )
    ''');

    final colunas = await database.rawQuery(
      'PRAGMA table_info(imperium_dispositivo_acesso)',
    );
    final nomes = colunas
        .map((item) => (item['name'] ?? '').toString())
        .toSet();

    if (!nomes.contains('dispositivo_id')) {
      await database.execute(
        'ALTER TABLE imperium_dispositivo_acesso '
        'ADD COLUMN dispositivo_id TEXT',
      );
    }

    if (!nomes.contains('ponto_nuvem_ativo')) {
      await database.execute(
        'ALTER TABLE imperium_dispositivo_acesso '
        'ADD COLUMN ponto_nuvem_ativo INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (!nomes.contains('ultimo_sync_permissoes_em')) {
      await database.execute(
        'ALTER TABLE imperium_dispositivo_acesso '
        'ADD COLUMN ultimo_sync_permissoes_em TEXT',
      );
    }

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sincronizacao_ponto_colaboradores (
        local_id INTEGER PRIMARY KEY,
        empresa_id TEXT NOT NULL,
        remoto_id TEXT NOT NULL,
        sincronizado_em TEXT NOT NULL,
        UNIQUE (empresa_id, remoto_id)
      )
    ''');
  }

  Future<String> dispositivoId() async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final atual = await database.query(
      'imperium_dispositivo_acesso',
      columns: ['dispositivo_id'],
      where: 'id = 1',
      limit: 1,
    );

    final existente = atual.isEmpty
        ? ''
        : (atual.first['dispositivo_id'] ?? '').toString().trim();

    if (existente.isNotEmpty) return existente;

    final novo = _novoDispositivoId();

    if (atual.isEmpty) {
      await database.insert('imperium_dispositivo_acesso', {
        'id': 1,
        'modo': 'nao_definido',
        'dispositivo_id': novo,
        'ponto_nuvem_ativo': 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await database.update('imperium_dispositivo_acesso', {
        'dispositivo_id': novo,
        'atualizado_em': DateTime.now().toIso8601String(),
      }, where: 'id = 1');
    }

    return novo;
  }

  String _novoDispositivoId() {
    final random = Random.secure();
    final tempo = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final aleatorio = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '$tempo-$aleatorio';
  }

  Future<bool> get dispositivoFuncionario async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'imperium_dispositivo_acesso',
      columns: ['modo'],
      where: 'id = 1',
      limit: 1,
    );

    return resultado.isNotEmpty &&
        (resultado.first['modo'] ?? '').toString() == 'funcionario';
  }

  Future<String?> get loginLocal async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'imperium_dispositivo_acesso',
      columns: ['login'],
      where: 'id = 1',
      limit: 1,
    );

    if (resultado.isEmpty) return null;

    final login = (resultado.first['login'] ?? '').toString().trim();
    return login.isEmpty ? null : login;
  }

  Future<String?> get emailLocal async {
    await garantirEstruturaLocal();
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'imperium_dispositivo_acesso',
      columns: ['email'],
      where: 'id = 1',
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    final email = (resultado.first['email'] ?? '').toString().trim();
    return email.isEmpty ? null : email;
  }

  Future<void> enviarMagicLink(String email) async {
    final client = _client;
    final emailLimpo = email.trim().toLowerCase();

    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    if (emailLimpo.isEmpty || !emailLimpo.contains('@')) {
      throw ArgumentError('Informe um e-mail válido.');
    }

    final atual = client.auth.currentUser;
    final emailAtual = (atual?.email ?? '').trim().toLowerCase();

    if (atual != null && emailAtual != emailLimpo) {
      await client.auth.signOut();
    }

    await client.auth.signInWithOtp(
      email: emailLimpo,
      emailRedirectTo: redirectUrl,
      shouldCreateUser: true,
    );
  }

  Future<void> sairSupabase() async {
    final client = _client;
    if (client == null) return;

    try {
      await client.auth.signOut();
    } catch (_) {
      // A sessão local do Imperium ainda pode ser encerrada separadamente.
    }
  }

  Future<Map<String, dynamic>> diagnosticarAcessoAtual() async {
    final client = _client;

    if (client == null || client.auth.currentUser == null) {
      return const {'autenticado': false, 'liberado': false};
    }

    final resposta = await client.rpc(
      'imperium_funcionario_diagnosticar_acesso',
    );
    return _mapa(resposta);
  }

  Future<List<Map<String, dynamic>>> listarAcessosAdmin(
    String empresaId,
  ) async {
    final client = _client;

    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final resposta = await client.rpc(
      'imperium_funcionario_listar_acessos',
      params: {'p_empresa_id': empresaId},
    );

    if (resposta is! List) return const [];

    return resposta
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> prepararAcessoAdmin({
    required String empresaId,
    required String colaboradorRemotoId,
    required String email,
    required String login,
    required Map<String, bool> permissoes,
  }) async {
    final client = _client;

    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    final resposta = await client.rpc(
      'imperium_funcionario_preparar_acesso',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorRemotoId,
        'p_email': email.trim().toLowerCase(),
        'p_login': login.trim().toLowerCase(),
        'p_permissoes': permissoes,
      },
    );

    return _mapa(resposta);
  }

  Future<bool> sincronizarPermissoesUsuarioLocal(int usuarioId) async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return false;

    final usuario = await _usuarioRepository.buscarUsuarioPorId(usuarioId);
    if (usuario == null) return false;

    if ((usuario['perfil'] ?? '').toString() !=
        UsuarioRepository.perfilFuncionario) {
      return false;
    }

    final colaboradorLocalId = _intNulo(usuario['colaborador_id']);
    if (colaboradorLocalId == null || colaboradorLocalId <= 0) return false;

    final empresaId = await _pontoNuvem.empresaAtualId();
    if (empresaId == null || empresaId.isEmpty) return false;

    final remotoId = await _pontoNuvem.remotoIdPorLocal(
      colaboradorLocalId,
      empresaId: empresaId,
    );
    if (remotoId == null || remotoId.isEmpty) return false;

    final permissoes = await _usuarioRepository.obterPermissoes(usuarioId);

    final resposta = await client.rpc(
      'imperium_funcionario_atualizar_permissoes',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': remotoId,
        'p_permissoes': permissoes,
      },
    );

    return _mapa(resposta)['configurado'] == true;
  }

  Future<void> definirAtivoAdmin({
    required String empresaId,
    required String colaboradorRemotoId,
    required bool ativo,
  }) async {
    final client = _client;

    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    await client.rpc(
      'imperium_funcionario_definir_ativo',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorRemotoId,
        'p_ativo': ativo,
      },
    );
  }

  Future<void> revogarDispositivosAdmin({
    required String empresaId,
    required String colaboradorRemotoId,
  }) async {
    final client = _client;

    if (client == null) {
      throw StateError('Supabase não está disponível.');
    }

    await client.rpc(
      'imperium_funcionario_revogar_dispositivos',
      params: {
        'p_empresa_id': empresaId,
        'p_colaborador_id': colaboradorRemotoId,
      },
    );
  }

  Future<Map<String, dynamic>> resgatarAcessoAtual() async {
    final client = _client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) {
      throw StateError(
        'Abra o Magic Link no mesmo celular para autenticar a conta.',
      );
    }

    final idDispositivo = await dispositivoId();

    final resposta = await client.rpc(
      'imperium_funcionario_resgatar_acesso',
      params: {'p_dispositivo_id': idDispositivo},
    );

    final acesso = _mapa(resposta);

    if (acesso['ativo'] != true) {
      throw StateError('O acesso do funcionário não está ativo.');
    }

    return acesso;
  }

  Future<Map<String, dynamic>> validarAcessoAtual() async {
    final client = _client;

    if (client == null || client.auth.currentUser == null) {
      return const {
        'consultado': false,
        'ativo': true,
        'motivo': 'sem_sessao_supabase',
      };
    }

    try {
      final idDispositivo = await dispositivoId();
      final resposta = await client.rpc(
        'imperium_funcionario_meu_acesso',
        params: {'p_dispositivo_id': idDispositivo},
      );
      final mapa = _mapa(resposta);
      return <String, dynamic>{'consultado': true, ...mapa};
    } catch (_) {
      return const {
        'consultado': false,
        'ativo': true,
        'motivo': 'offline_ou_indisponivel',
      };
    }
  }

  Future<Map<String, dynamic>> sincronizarPermissoesLocais() async {
    await garantirEstruturaLocal();
    await _usuarioRepository.garantirEstrutura();

    final database = await _appDatabase.database;

    final dispositivo = await database.query(
      'imperium_dispositivo_acesso',
      where: 'id = 1 AND modo = ?',
      whereArgs: ['funcionario'],
      limit: 1,
    );

    if (dispositivo.isEmpty) {
      return const {
        'consultado': false,
        'ativo': true,
        'motivo': 'nao_e_dispositivo_funcionario',
      };
    }

    final usuarioLocalId = _intNulo(dispositivo.first['usuario_local_id']);
    if (usuarioLocalId == null || usuarioLocalId <= 0) {
      return const {
        'consultado': false,
        'ativo': true,
        'motivo': 'usuario_local_ausente',
      };
    }

    final remoto = await validarAcessoAtual();

    if (remoto['consultado'] != true) {
      return remoto;
    }

    if (remoto['ativo'] != true) {
      await database.update(
        'financeiro_usuarios',
        {'ativo': 0, 'atualizado_em': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [usuarioLocalId],
      );
      await _usuarioRepository.limparSessaoPersistida();
      _usuarioRepository.encerrarSessao();
      return remoto;
    }

    final permissoes = _permissoes(remoto['permissoes']);

    for (final modulo in UsuarioRepository.modulos) {
      await _usuarioRepository.salvarPermissao(
        usuarioId: usuarioLocalId,
        modulo: modulo,
        permitido: permissoes[modulo] ?? false,
      );
    }

    await database.update(
      'financeiro_usuarios',
      {'ativo': 1, 'atualizado_em': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [usuarioLocalId],
    );

    await database.update('imperium_dispositivo_acesso', {
      'ponto_nuvem_ativo': remoto['ponto_migracao_ativa'] == true ? 1 : 0,
      'ultimo_sync_permissoes_em': DateTime.now().toIso8601String(),
      'atualizado_em': DateTime.now().toIso8601String(),
    }, where: 'id = 1');

    return remoto;
  }

  Future<Map<String, dynamic>> provisionarLocal({
    required Map<String, dynamic> acesso,
    required String pin,
  }) async {
    final pinLimpo = pin.trim();

    if (!RegExp(r'^\d{4,8}$').hasMatch(pinLimpo)) {
      throw ArgumentError('O PIN deve ter entre 4 e 8 números.');
    }

    final empresaId = (acesso['empresa_id'] ?? '').toString().trim();
    final remotoId = (acesso['colaborador_id'] ?? '').toString().trim();
    final nome = (acesso['colaborador_nome'] ?? 'Funcionário')
        .toString()
        .trim();
    final funcao = (acesso['funcao'] ?? '').toString().trim();
    final email = (acesso['email'] ?? '').toString().trim().toLowerCase();
    final authUserId = (acesso['auth_user_id'] ?? '').toString().trim();

    if (empresaId.isEmpty || remotoId.isEmpty || nome.isEmpty) {
      throw StateError('O vínculo retornado pela nuvem está incompleto.');
    }

    await garantirEstruturaLocal();
    await _usuarioRepository.garantirEstrutura();

    final idDispositivo = await dispositivoId();
    final database = await _appDatabase.database;

    final dispositivo = await database.query(
      'imperium_dispositivo_acesso',
      where: 'id = 1',
      limit: 1,
    );

    int? colaboradorLocalId;
    int? usuarioLocalId;
    String? loginExistente;

    if (dispositivo.isNotEmpty &&
        (dispositivo.first['empresa_id'] ?? '').toString() == empresaId &&
        (dispositivo.first['colaborador_remoto_id'] ?? '').toString() ==
            remotoId) {
      colaboradorLocalId = _intNulo(dispositivo.first['colaborador_local_id']);
      usuarioLocalId = _intNulo(dispositivo.first['usuario_local_id']);
      loginExistente = (dispositivo.first['login'] ?? '').toString().trim();
    }

    if (colaboradorLocalId == null || colaboradorLocalId <= 0) {
      final agora = DateTime.now().toIso8601String();

      colaboradorLocalId = await _custosRepository.salvarColaborador(
        ColaboradorCusto(
          nome: nome,
          funcao: funcao,
          remuneracaoMensal: 0,
          encargosMensais: 0,
          outrosCustosMensais: 0,
          horasProdutivasMes: 220,
          observacoes: 'Espelho operacional do funcionário na nuvem.',
          ativo: true,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );
    }

    await database.insert(
      'sincronizacao_ponto_colaboradores',
      {
        'local_id': colaboradorLocalId,
        'empresa_id': empresaId,
        'remoto_id': remotoId,
        'sincronizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final usuarios = await _usuarioRepository.listarUsuarios();
    Map<String, dynamic>? usuarioAtual;

    if (usuarioLocalId != null) {
      for (final item in usuarios) {
        if (_intNulo(item['id']) == usuarioLocalId) {
          usuarioAtual = item;
          break;
        }
      }
    }

    var login = loginExistente?.trim() ?? '';
    if (login.isEmpty) {
      login = _normalizarLogin(
        (acesso['login'] ?? '').toString(),
        email: email,
      );
    }

    if (usuarioAtual == null) {
      login = _loginDisponivel(login, usuarios);

      usuarioLocalId = await _usuarioRepository.salvarUsuario(
        nome: nome,
        login: login,
        perfil: UsuarioRepository.perfilFuncionario,
        colaboradorId: colaboradorLocalId,
        ativo: true,
      );
    } else {
      usuarioLocalId = _intNulo(usuarioAtual['id']);
      if (usuarioLocalId == null) {
        throw StateError('Usuário local do funcionário ficou inválido.');
      }

      login = (usuarioAtual['login'] ?? login).toString();

      await _usuarioRepository.salvarUsuario(
        id: usuarioLocalId,
        nome: nome,
        login: login,
        perfil: UsuarioRepository.perfilFuncionario,
        colaboradorId: colaboradorLocalId,
        ativo: true,
      );
    }

    final permissoes = _permissoes(acesso['permissoes']);

    for (final modulo in UsuarioRepository.modulos) {
      await _usuarioRepository.salvarPermissao(
        usuarioId: usuarioLocalId,
        modulo: modulo,
        permitido: permissoes[modulo] ?? false,
      );
    }

    await _usuarioRepository.definirPin(
      usuarioId: usuarioLocalId,
      pin: pinLimpo,
    );

    await database.insert('imperium_dispositivo_acesso', {
      'id': 1,
      'modo': 'funcionario',
      'empresa_id': empresaId,
      'colaborador_remoto_id': remotoId,
      'colaborador_local_id': colaboradorLocalId,
      'usuario_local_id': usuarioLocalId,
      'auth_user_id': authUserId,
      'email': email,
      'login': login,
      'dispositivo_id': idDispositivo,
      'ponto_nuvem_ativo': acesso['ponto_migracao_ativa'] == true ? 1 : 0,
      'ultimo_sync_permissoes_em': DateTime.now().toIso8601String(),
      'atualizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return _usuarioRepository.autenticar(
      login: login,
      pin: pinLimpo,
      manterConectado: true,
    );
  }

  Map<String, bool> _permissoes(dynamic bruto) {
    final mapa = bruto is Map ? bruto : const <String, dynamic>{};

    return {
      for (final modulo in UsuarioRepository.modulos)
        modulo: modulo == 'ponto'
            ? true
            : modulosRemotosProntos.contains(modulo) && mapa[modulo] == true,
    };
  }

  String _normalizarLogin(String valor, {required String email}) {
    var login = valor.trim().toLowerCase();

    if (login.isEmpty && email.contains('@')) {
      login = email.split('@').first;
    }

    login = login.replaceAll(RegExp(r'[^a-z0-9._-]'), '.');
    login = login.replaceAll(RegExp(r'\.+'), '.');
    login = login.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');

    if (login.length < 3 || login == 'admin') {
      login = 'funcionario';
    }

    return login;
  }

  String _loginDisponivel(String base, List<Map<String, dynamic>> usuarios) {
    final usados = usuarios
        .map((item) => (item['login'] ?? '').toString().toLowerCase())
        .toSet();

    if (!usados.contains(base)) return base;

    var indice = 2;
    while (usados.contains('$base$indice')) {
      indice++;
    }
    return '$base$indice';
  }

  static String textoErro(Object erro) {
    if (erro is AuthException) {
      final codigo = (erro.code ?? '').trim().toLowerCase();
      final status = (erro.statusCode ?? '').trim();

      if (codigo == 'over_email_send_rate_limit' || status == '429') {
        return 'Muitos e-mails de acesso foram solicitados. '
            'Aguarde alguns minutos e tente novamente uma única vez.';
      }

      if (codigo == 'otp_expired' || codigo == 'otp_disabled') {
        return 'Este link expirou ou não é mais válido. Solicite um novo link.';
      }

      return erro.message.trim().isEmpty
          ? 'Falha na autenticação por e-mail.'
          : erro.message.trim();
    }

    var texto = erro.toString().trim();

    for (final prefixo in const [
      'PostgrestException: ',
      'AuthException: ',
      'StateError: ',
      'Bad state: ',
      'Invalid argument(s): ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Falha desconhecida.' : texto;
  }

  static Map<String, dynamic> _mapa(dynamic valor) {
    if (valor is Map<String, dynamic>) {
      return Map<String, dynamic>.from(valor);
    }

    if (valor is Map) {
      return valor.map<String, dynamic>(
        (chave, item) => MapEntry(chave.toString(), item),
      );
    }

    return <String, dynamic>{};
  }

  static int? _intNulo(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }
}
