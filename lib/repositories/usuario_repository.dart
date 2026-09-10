import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class UsuarioRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  static const String perfilAdministrador = 'Administrador';
  static const String perfilFuncionario = 'Funcionário';

  static const List<String> perfis = <String>[
    perfilAdministrador,
    perfilFuncionario,
  ];

  static const int maxTentativasPin = 5;
  static const Duration janelaBloqueioPin = Duration(minutes: 15);

  Future<void> garantirEstrutura() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);
  }

  Future<void> _garantirEstrutura(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        login TEXT NOT NULL COLLATE NOCASE,
        perfil TEXT NOT NULL,
        colaborador_id INTEGER,
        ativo INTEGER NOT NULL DEFAULT 1,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        UNIQUE (login),
        FOREIGN KEY (colaborador_id)
          REFERENCES financeiro_colaboradores_custo (id)
          ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_financeiro_usuarios_perfil
      ON financeiro_usuarios (
        perfil,
        ativo
      )
    ''');

    final colunasUsuarios = await database.rawQuery(
      'PRAGMA table_info(financeiro_usuarios)',
    );

    final nomesColunas = colunasUsuarios
        .map((item) => (item['name'] ?? '').toString())
        .toSet();

    if (!nomesColunas.contains('pin_salt')) {
      await database.execute(
        'ALTER TABLE financeiro_usuarios ADD COLUMN pin_salt TEXT',
      );
    }

    if (!nomesColunas.contains('pin_hash')) {
      await database.execute(
        'ALTER TABLE financeiro_usuarios ADD COLUMN pin_hash TEXT',
      );
    }

    if (!nomesColunas.contains('pin_iteracoes')) {
      await database.execute(
        'ALTER TABLE financeiro_usuarios '
        'ADD COLUMN pin_iteracoes INTEGER NOT NULL DEFAULT 120000',
      );
    }

    if (!nomesColunas.contains('pin_atualizado_em')) {
      await database.execute(
        'ALTER TABLE financeiro_usuarios ADD COLUMN pin_atualizado_em TEXT',
      );
    }

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_usuario_acessos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER,
        login TEXT NOT NULL,
        sucesso INTEGER NOT NULL,
        motivo TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        FOREIGN KEY (usuario_id)
          REFERENCES financeiro_usuarios (id)
          ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_financeiro_usuario_acessos_login
      ON financeiro_usuario_acessos (
        login,
        criado_em
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_usuario_auditoria (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER,
        ator_usuario_id INTEGER,
        acao TEXT NOT NULL,
        detalhe TEXT NOT NULL DEFAULT '',
        criado_em TEXT NOT NULL,
        FOREIGN KEY (usuario_id)
          REFERENCES financeiro_usuarios (id)
          ON DELETE SET NULL,
        FOREIGN KEY (ator_usuario_id)
          REFERENCES financeiro_usuarios (id)
          ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_financeiro_usuario_auditoria_usuario
      ON financeiro_usuario_auditoria (
        usuario_id,
        criado_em
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_usuario_permissoes (
        usuario_id INTEGER NOT NULL,
        modulo TEXT NOT NULL,
        permitido INTEGER NOT NULL DEFAULT 0,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (usuario_id, modulo),
        FOREIGN KEY (usuario_id)
          REFERENCES financeiro_usuarios (id)
          ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS financeiro_usuario_sessao (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        usuario_id INTEGER NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (usuario_id)
          REFERENCES financeiro_usuarios (id)
          ON DELETE CASCADE
      )
    ''');

    final admins =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM financeiro_usuarios
            WHERE perfil = ?
            ''',
            [perfilAdministrador],
          ),
        ) ??
        0;

    if (admins == 0) {
      final agora = DateTime.now().toIso8601String();

      await database.insert('financeiro_usuarios', {
        'nome': 'Administrador',
        'login': 'admin',
        'perfil': perfilAdministrador,
        'colaborador_id': null,
        'ativo': 1,
        'pin_salt': null,
        'pin_hash': null,
        'pin_iteracoes': 120000,
        'pin_atualizado_em': null,
        'criado_em': agora,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Map<String, dynamic>? _sessaoAtual;

  Map<String, dynamic>? get sessaoAtual {
    final sessao = _sessaoAtual;
    return sessao == null ? null : Map<String, dynamic>.from(sessao);
  }

  bool get possuiSessao => _sessaoAtual != null;

  Future<bool> possuiAdministradorComPin() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM financeiro_usuarios
      WHERE perfil = ?
        AND ativo = 1
        AND pin_hash IS NOT NULL
        AND TRIM(pin_hash) != ''
        AND pin_salt IS NOT NULL
        AND TRIM(pin_salt) != ''
      ''',
      [perfilAdministrador],
    );

    return (Sqflite.firstIntValue(resultado) ?? 0) > 0;
  }

  Future<bool> usuarioTemPin(int usuarioId) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_usuarios',
      columns: ['pin_hash', 'pin_salt'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return false;
    }

    final hash = (resultado.first['pin_hash'] ?? '').toString().trim();
    final salt = (resultado.first['pin_salt'] ?? '').toString().trim();

    return hash.isNotEmpty && salt.isNotEmpty;
  }

  Future<void> definirPin({required int usuarioId, required String pin}) async {
    _validarPin(pin);

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final usuario = await database.query(
      'financeiro_usuarios',
      columns: ['id', 'ativo'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );

    if (usuario.isEmpty) {
      throw StateError('Usuário não encontrado.');
    }

    if (_int(usuario.first['ativo']) != 1) {
      throw StateError('Ative o usuário antes de configurar o PIN.');
    }

    const iteracoes = 120000;
    final salt = _gerarSalt();
    final hash = _derivarPin(pin: pin, salt: salt, iteracoes: iteracoes);
    final agora = DateTime.now().toIso8601String();

    await database.update(
      'financeiro_usuarios',
      {
        'pin_salt': salt,
        'pin_hash': hash,
        'pin_iteracoes': iteracoes,
        'pin_atualizado_em': agora,
        'atualizado_em': agora,
      },
      where: 'id = ?',
      whereArgs: [usuarioId],
    );

    await _registrarAuditoria(
      database,
      usuarioId: usuarioId,
      acao: 'DefinicaoPin',
      detalhe: 'PIN definido ou redefinido pelo administrador.',
    );
  }

  Future<void> removerPin(int usuarioId) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final usuario = await database.query(
      'financeiro_usuarios',
      columns: ['id', 'perfil'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );

    if (usuario.isEmpty) {
      throw StateError('Usuário não encontrado.');
    }

    final perfil = (usuario.first['perfil'] ?? '').toString();

    if (perfil == perfilAdministrador) {
      final outrosAdminsComPin =
          Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT COUNT(*)
              FROM financeiro_usuarios
              WHERE id != ?
                AND perfil = ?
                AND ativo = 1
                AND pin_hash IS NOT NULL
                AND TRIM(pin_hash) != ''
                AND pin_salt IS NOT NULL
                AND TRIM(pin_salt) != ''
              ''',
              [usuarioId, perfilAdministrador],
            ),
          ) ??
          0;

      if (outrosAdminsComPin == 0) {
        throw StateError(
          'Mantenha pelo menos um Administrador ativo com PIN configurado.',
        );
      }
    }

    await database.update(
      'financeiro_usuarios',
      {
        'pin_salt': null,
        'pin_hash': null,
        'pin_atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [usuarioId],
    );

    await _registrarAuditoria(
      database,
      usuarioId: usuarioId,
      acao: 'RemocaoPin',
      detalhe: 'PIN removido pelo administrador.',
    );

    if (_int(_sessaoAtual?['id']) == usuarioId) {
      await limparSessaoPersistida();
      encerrarSessao();
    }
  }

  Future<Map<String, dynamic>> autenticar({
    required String login,
    required String pin,
    bool manterConectado = false,
  }) async {
    final loginLimpo = login.trim().toLowerCase();
    final pinLimpo = pin.trim();

    if (loginLimpo.isEmpty || pinLimpo.isEmpty) {
      throw ArgumentError('Informe login e PIN.');
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final bloqueio = await obterBloqueioLogin(loginLimpo, database: database);
    if (bloqueio['bloqueado'] == true) {
      throw StateError(
        'Muitas tentativas de PIN incorreto. Aguarde alguns minutos ou peça ao administrador para liberar o acesso.',
      );
    }

    final resultado = await database.rawQuery(
      '''
      SELECT
        u.*,
        c.nome AS colaborador_nome,
        c.funcao AS colaborador_funcao
      FROM financeiro_usuarios u
      LEFT JOIN financeiro_colaboradores_custo c
        ON c.id = u.colaborador_id
      WHERE LOWER(u.login) = LOWER(?)
      LIMIT 1
      ''',
      [loginLimpo],
    );

    if (resultado.isEmpty) {
      await _registrarTentativa(
        database,
        usuarioId: null,
        login: loginLimpo,
        sucesso: false,
        motivo: 'Usuário não encontrado',
      );
      throw StateError('Login ou PIN inválido.');
    }

    final usuario = Map<String, dynamic>.from(resultado.first);
    final usuarioId = _int(usuario['id']);

    if (_int(usuario['ativo']) != 1) {
      await _registrarTentativa(
        database,
        usuarioId: usuarioId,
        login: loginLimpo,
        sucesso: false,
        motivo: 'Usuário inativo',
      );
      throw StateError('Este usuário está inativo.');
    }

    final salt = (usuario['pin_salt'] ?? '').toString().trim();
    final hashEsperado = (usuario['pin_hash'] ?? '').toString().trim();
    final iteracoes = _int(usuario['pin_iteracoes']) > 0
        ? _int(usuario['pin_iteracoes'])
        : 120000;

    if (salt.isEmpty || hashEsperado.isEmpty) {
      await _registrarTentativa(
        database,
        usuarioId: usuarioId,
        login: loginLimpo,
        sucesso: false,
        motivo: 'PIN não configurado',
      );
      throw StateError('Este usuário ainda não possui PIN configurado.');
    }

    final hashInformado = _derivarPin(
      pin: pinLimpo,
      salt: salt,
      iteracoes: iteracoes,
    );

    if (!_comparacaoTempoConstante(hashEsperado, hashInformado)) {
      await _registrarTentativa(
        database,
        usuarioId: usuarioId,
        login: loginLimpo,
        sucesso: false,
        motivo: 'PIN inválido',
      );
      throw StateError('Login ou PIN inválido.');
    }

    final permissoes = await obterPermissoes(usuarioId);

    final sessao = <String, dynamic>{
      'id': usuarioId,
      'nome': (usuario['nome'] ?? '').toString(),
      'login': (usuario['login'] ?? '').toString(),
      'perfil': (usuario['perfil'] ?? '').toString(),
      'colaborador_id': usuario['colaborador_id'],
      'colaborador_nome': (usuario['colaborador_nome'] ?? '').toString(),
      'permissoes': permissoes,
      'autenticado_em': DateTime.now().toIso8601String(),
    };

    _sessaoAtual = sessao;

    if (manterConectado) {
      await salvarSessaoPersistida(usuarioId);
    } else {
      await limparSessaoPersistida();
    }

    await _registrarTentativa(
      database,
      usuarioId: usuarioId,
      login: loginLimpo,
      sucesso: true,
      motivo: 'Login realizado',
    );

    return Map<String, dynamic>.from(sessao);
  }

  Future<void> salvarSessaoPersistida(int usuarioId) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final agora = DateTime.now().toIso8601String();

    await database.insert('financeiro_usuario_sessao', {
      'id': 1,
      'usuario_id': usuarioId,
      'criado_em': agora,
      'atualizado_em': agora,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> restaurarSessaoPersistida() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final sessaoSalva = await database.query(
      'financeiro_usuario_sessao',
      where: 'id = 1',
      limit: 1,
    );

    if (sessaoSalva.isEmpty) {
      return null;
    }

    final usuarioId = _int(sessaoSalva.first['usuario_id']);

    if (usuarioId <= 0) {
      await limparSessaoPersistida();
      return null;
    }

    final resultado = await database.rawQuery(
      '''
      SELECT
        u.*,
        c.nome AS colaborador_nome,
        c.funcao AS colaborador_funcao
      FROM financeiro_usuarios u
      LEFT JOIN financeiro_colaboradores_custo c
        ON c.id = u.colaborador_id
      WHERE u.id = ?
        AND u.ativo = 1
      LIMIT 1
      ''',
      [usuarioId],
    );

    if (resultado.isEmpty) {
      await limparSessaoPersistida();
      return null;
    }

    final usuario = Map<String, dynamic>.from(resultado.first);

    final salt = (usuario['pin_salt'] ?? '').toString().trim();
    final hash = (usuario['pin_hash'] ?? '').toString().trim();

    if (salt.isEmpty || hash.isEmpty) {
      await limparSessaoPersistida();
      return null;
    }

    final permissoes = await obterPermissoes(usuarioId);

    final sessao = <String, dynamic>{
      'id': usuarioId,
      'nome': (usuario['nome'] ?? '').toString(),
      'login': (usuario['login'] ?? '').toString(),
      'perfil': (usuario['perfil'] ?? '').toString(),
      'colaborador_id': usuario['colaborador_id'],
      'colaborador_nome': (usuario['colaborador_nome'] ?? '').toString(),
      'permissoes': permissoes,
      'autenticado_em': DateTime.now().toIso8601String(),
      'sessao_restaurada': true,
    };

    _sessaoAtual = sessao;

    return Map<String, dynamic>.from(sessao);
  }

  Future<void> limparSessaoPersistida() async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    await database.delete('financeiro_usuario_sessao', where: 'id = 1');
  }

  Future<void> sair() async {
    encerrarSessao();
    await limparSessaoPersistida();
  }

  void encerrarSessao() {
    _sessaoAtual = null;
  }

  bool sessaoPodeAcessar(String modulo) {
    final sessao = _sessaoAtual;
    if (sessao == null) {
      return false;
    }

    if ((sessao['perfil'] ?? '').toString() == perfilAdministrador) {
      return true;
    }

    final permissoesBrutas = sessao['permissoes'];
    if (permissoesBrutas is Map) {
      final valor = permissoesBrutas[modulo];
      if (valor is bool) {
        return valor;
      }
    }

    return false;
  }

  Future<Map<String, dynamic>> obterBloqueioLogin(
    String login, {
    DatabaseExecutor? database,
  }) async {
    final executor = database ?? await _appDatabase.database;
    await _garantirEstrutura(executor);

    final loginLimpo = login.trim().toLowerCase();
    if (loginLimpo.isEmpty) {
      return const <String, dynamic>{'bloqueado': false, 'falhas': 0};
    }

    final agora = DateTime.now();
    final limite = agora.subtract(janelaBloqueioPin);

    final ultimoSucesso = await executor.rawQuery(
      '''
      SELECT MAX(criado_em) AS ultimo_sucesso
      FROM financeiro_usuario_acessos
      WHERE LOWER(login) = LOWER(?)
        AND sucesso = 1
      ''',
      [loginLimpo],
    );

    final ultimoSucessoTexto = (ultimoSucesso.first['ultimo_sucesso'] ?? '')
        .toString();
    final ultimoSucessoData = DateTime.tryParse(ultimoSucessoTexto);

    final inicioJanela =
        ultimoSucessoData != null && ultimoSucessoData.isAfter(limite)
        ? ultimoSucessoData
        : limite;

    final falhas =
        Sqflite.firstIntValue(
          await executor.rawQuery(
            '''
            SELECT COUNT(*)
            FROM financeiro_usuario_acessos
            WHERE LOWER(login) = LOWER(?)
              AND sucesso = 0
              AND motivo IN ('PIN inválido', 'Usuário não encontrado')
              AND datetime(criado_em) > datetime(?)
            ''',
            [loginLimpo, inicioJanela.toIso8601String()],
          ),
        ) ??
        0;

    return <String, dynamic>{
      'bloqueado': falhas >= maxTentativasPin,
      'falhas': falhas,
      'restantes': (maxTentativasPin - falhas).clamp(0, maxTentativasPin),
      'janela_minutos': janelaBloqueioPin.inMinutes,
    };
  }

  Future<void> liberarBloqueioUsuario(int usuarioId) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final usuario = await database.query(
      'financeiro_usuarios',
      columns: ['id', 'login', 'nome'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );

    if (usuario.isEmpty) {
      throw StateError('Usuário não encontrado.');
    }

    final login = (usuario.first['login'] ?? '').toString();

    await database.transaction((transaction) async {
      await _registrarTentativa(
        transaction,
        usuarioId: usuarioId,
        login: login,
        sucesso: true,
        motivo: 'Bloqueio de tentativas liberado pelo administrador',
      );
      await _registrarAuditoria(
        transaction,
        usuarioId: usuarioId,
        acao: 'LiberacaoBloqueio',
        detalhe: 'Tentativas de PIN liberadas manualmente.',
      );
    });
  }

  Future<void> alterarPinComPinAtual({
    required int usuarioId,
    required String pinAtual,
    required String novoPin,
  }) async {
    _validarPin(pinAtual);
    _validarPin(novoPin);

    if (pinAtual.trim() == novoPin.trim()) {
      throw ArgumentError('O novo PIN precisa ser diferente do PIN atual.');
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.query(
      'financeiro_usuarios',
      columns: [
        'id',
        'login',
        'ativo',
        'pin_salt',
        'pin_hash',
        'pin_iteracoes',
      ],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );

    if (resultado.isEmpty || _int(resultado.first['ativo']) != 1) {
      throw StateError('Usuário não encontrado ou inativo.');
    }

    final usuario = resultado.first;
    final saltAtual = (usuario['pin_salt'] ?? '').toString().trim();
    final hashAtual = (usuario['pin_hash'] ?? '').toString().trim();
    final iteracoesAtuais = _int(usuario['pin_iteracoes']) > 0
        ? _int(usuario['pin_iteracoes'])
        : 120000;

    if (saltAtual.isEmpty || hashAtual.isEmpty) {
      throw StateError('Este usuário ainda não possui PIN configurado.');
    }

    final hashInformado = _derivarPin(
      pin: pinAtual.trim(),
      salt: saltAtual,
      iteracoes: iteracoesAtuais,
    );

    if (!_comparacaoTempoConstante(hashAtual, hashInformado)) {
      await _registrarTentativa(
        database,
        usuarioId: usuarioId,
        login: (usuario['login'] ?? '').toString(),
        sucesso: false,
        motivo: 'PIN atual inválido na troca',
      );
      throw StateError('O PIN atual informado está incorreto.');
    }

    const novasIteracoes = 120000;
    final novoSalt = _gerarSalt();
    final novoHash = _derivarPin(
      pin: novoPin.trim(),
      salt: novoSalt,
      iteracoes: novasIteracoes,
    );
    final agora = DateTime.now().toIso8601String();

    await database.transaction((transaction) async {
      await transaction.update(
        'financeiro_usuarios',
        {
          'pin_salt': novoSalt,
          'pin_hash': novoHash,
          'pin_iteracoes': novasIteracoes,
          'pin_atualizado_em': agora,
          'atualizado_em': agora,
        },
        where: 'id = ?',
        whereArgs: [usuarioId],
      );

      await _registrarTentativa(
        transaction,
        usuarioId: usuarioId,
        login: (usuario['login'] ?? '').toString(),
        sucesso: true,
        motivo: 'PIN alterado pelo próprio usuário',
      );

      await _registrarAuditoria(
        transaction,
        usuarioId: usuarioId,
        acao: 'AlteracaoPinProprio',
        detalhe: 'PIN alterado após validação do PIN atual.',
      );
    });
  }

  Future<List<Map<String, dynamic>>> listarAuditoriaUsuario({
    int? usuarioId,
    int limite = 200,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final where = usuarioId == null ? '' : 'WHERE a.usuario_id = ?';
    final args = <Object?>[?usuarioId, limite.clamp(1, 500)];

    return database.rawQuery('''
      SELECT
        a.*,
        u.nome AS usuario_nome,
        ator.nome AS ator_nome
      FROM financeiro_usuario_auditoria a
      LEFT JOIN financeiro_usuarios u
        ON u.id = a.usuario_id
      LEFT JOIN financeiro_usuarios ator
        ON ator.id = a.ator_usuario_id
      $where
      ORDER BY a.id DESC
      LIMIT ?
      ''', args);
  }

  Future<List<Map<String, dynamic>>> listarAcessos({int limite = 100}) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    return database.rawQuery(
      '''
      SELECT
        a.*,
        u.nome AS usuario_nome
      FROM financeiro_usuario_acessos a
      LEFT JOIN financeiro_usuarios u
        ON u.id = a.usuario_id
      ORDER BY a.id DESC
      LIMIT ?
      ''',
      [limite.clamp(1, 500)],
    );
  }

  Future<void> _registrarTentativa(
    DatabaseExecutor database, {
    required int? usuarioId,
    required String login,
    required bool sucesso,
    required String motivo,
  }) async {
    await database.insert('financeiro_usuario_acessos', {
      'usuario_id': usuarioId,
      'login': login,
      'sucesso': sucesso ? 1 : 0,
      'motivo': motivo,
      'criado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> _registrarAuditoria(
    DatabaseExecutor database, {
    required int? usuarioId,
    required String acao,
    String detalhe = '',
  }) async {
    await database.insert('financeiro_usuario_auditoria', {
      'usuario_id': usuarioId,
      'ator_usuario_id': _intNulo(_sessaoAtual?['id']),
      'acao': acao,
      'detalhe': detalhe.trim(),
      'criado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  static void _validarPin(String pin) {
    final limpo = pin.trim();

    if (!RegExp(r'^\d{4,8}$').hasMatch(limpo)) {
      throw ArgumentError('O PIN deve ter entre 4 e 8 números.');
    }
  }

  static String _gerarSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _derivarPin({
    required String pin,
    required String salt,
    required int iteracoes,
  }) {
    List<int> bytes = utf8.encode('$salt:$pin');

    for (var i = 0; i < iteracoes; i++) {
      bytes = sha256.convert(bytes).bytes;
    }

    return base64UrlEncode(bytes);
  }

  static bool _comparacaoTempoConstante(String esperado, String informado) {
    final a = utf8.encode(esperado);
    final b = utf8.encode(informado);

    var diferenca = a.length ^ b.length;
    final tamanho = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < tamanho; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      diferenca |= av ^ bv;
    }

    return diferenca == 0;
  }

  Future<List<Map<String, dynamic>>> listarUsuarios({
    bool incluirInativos = true,
  }) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final where = incluirInativos ? '' : 'WHERE u.ativo = 1';

    final resultado = await database.rawQuery('''
      SELECT
        u.*,
        c.nome AS colaborador_nome,
        c.funcao AS colaborador_funcao
      FROM financeiro_usuarios u
      LEFT JOIN financeiro_colaboradores_custo c
        ON c.id = u.colaborador_id
      $where
      ORDER BY
        CASE u.perfil
          WHEN '$perfilAdministrador' THEN 1
          ELSE 2
        END,
        u.nome COLLATE NOCASE ASC
      ''');

    return resultado.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<Map<String, dynamic>?> buscarUsuarioPorId(int id) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final resultado = await database.rawQuery(
      '''
      SELECT
        u.*,
        c.nome AS colaborador_nome,
        c.funcao AS colaborador_funcao
      FROM financeiro_usuarios u
      LEFT JOIN financeiro_colaboradores_custo c
        ON c.id = u.colaborador_id
      WHERE u.id = ?
      LIMIT 1
      ''',
      [id],
    );

    if (resultado.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(resultado.first);
  }

  Future<int> salvarUsuario({
    int? id,
    required String nome,
    required String login,
    required String perfil,
    int? colaboradorId,
    required bool ativo,
  }) async {
    final nomeLimpo = nome.trim();
    final loginLimpo = login.trim().toLowerCase();

    if (nomeLimpo.length < 2) {
      throw ArgumentError('Informe o nome do usuário.');
    }

    if (loginLimpo.length < 3) {
      throw ArgumentError('O login precisa ter pelo menos 3 caracteres.');
    }

    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(loginLimpo)) {
      throw ArgumentError(
        'Use apenas letras, números, ponto, hífen ou underline no login.',
      );
    }

    if (!perfis.contains(perfil)) {
      throw ArgumentError('Perfil de usuário inválido.');
    }

    if (perfil == perfilFuncionario && colaboradorId == null) {
      throw ArgumentError(
        'Vincule o usuário Funcionário a um funcionário cadastrado.',
      );
    }

    final database = await _appDatabase.database;

    return database.transaction<int>((transaction) async {
      await _garantirEstrutura(transaction);

      if (colaboradorId != null) {
        final colaborador = await transaction.query(
          'financeiro_colaboradores_custo',
          columns: ['id'],
          where: 'id = ? AND ativo = 1',
          whereArgs: [colaboradorId],
          limit: 1,
        );

        if (colaborador.isEmpty) {
          throw StateError(
            'O funcionário selecionado não foi encontrado ou está inativo.',
          );
        }

        final vinculado = await transaction.query(
          'financeiro_usuarios',
          columns: ['id'],
          where: 'colaborador_id = ? AND id != ?',
          whereArgs: [colaboradorId, id ?? -1],
          limit: 1,
        );

        if (vinculado.isNotEmpty) {
          throw StateError(
            'Este funcionário já está vinculado a outro usuário.',
          );
        }
      }

      final repetido = await transaction.query(
        'financeiro_usuarios',
        columns: ['id'],
        where: 'LOWER(login) = LOWER(?) AND id != ?',
        whereArgs: [loginLimpo, id ?? -1],
        limit: 1,
      );

      if (repetido.isNotEmpty) {
        throw StateError('Este login já está sendo usado.');
      }

      final agora = DateTime.now().toIso8601String();

      final dados = <String, dynamic>{
        'nome': nomeLimpo,
        'login': loginLimpo,
        'perfil': perfil,
        'colaborador_id': perfil == perfilFuncionario ? colaboradorId : null,
        'ativo': ativo ? 1 : 0,
        'atualizado_em': agora,
      };

      int usuarioId;

      if (id == null) {
        dados['criado_em'] = agora;

        usuarioId = await transaction.insert(
          'financeiro_usuarios',
          dados,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        final atual = await transaction.query(
          'financeiro_usuarios',
          columns: ['id', 'perfil', 'ativo'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );

        if (atual.isEmpty) {
          throw StateError('Usuário não encontrado.');
        }

        final eraAdmin =
            (atual.first['perfil'] ?? '').toString() == perfilAdministrador;
        final eraAtivo = _int(atual.first['ativo']) == 1;

        final deixaraDeSerAdminAtivo =
            eraAdmin && eraAtivo && (perfil != perfilAdministrador || !ativo);

        if (deixaraDeSerAdminAtivo) {
          final outrosAdmins =
              Sqflite.firstIntValue(
                await transaction.rawQuery(
                  '''
                  SELECT COUNT(*)
                  FROM financeiro_usuarios
                  WHERE id != ?
                    AND perfil = ?
                    AND ativo = 1
                  ''',
                  [id, perfilAdministrador],
                ),
              ) ??
              0;

          if (outrosAdmins == 0) {
            throw StateError(
              'O sistema precisa manter pelo menos um Administrador ativo.',
            );
          }
        }

        await transaction.update(
          'financeiro_usuarios',
          dados,
          where: 'id = ?',
          whereArgs: [id],
        );

        usuarioId = id;
      }

      await _sincronizarPermissoesPadrao(
        transaction,
        usuarioId: usuarioId,
        perfil: perfil,
      );

      return usuarioId;
    });
  }

  Future<void> _sincronizarPermissoesPadrao(
    DatabaseExecutor database, {
    required int usuarioId,
    required String perfil,
  }) async {
    final agora = DateTime.now().toIso8601String();

    for (final modulo in modulos) {
      await database.insert(
        'financeiro_usuario_permissoes',
        {
          'usuario_id': usuarioId,
          'modulo': modulo,
          'permitido': permissaoPadrao(perfil, modulo) ? 1 : 0,
          'atualizado_em': agora,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> salvarPermissao({
    required int usuarioId,
    required String modulo,
    required bool permitido,
  }) async {
    if (!modulos.contains(modulo)) {
      throw ArgumentError('Módulo inválido.');
    }

    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final usuario = await database.query(
      'financeiro_usuarios',
      columns: ['perfil'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );

    if (usuario.isEmpty) {
      throw StateError('Usuário não encontrado.');
    }

    final perfil = (usuario.first['perfil'] ?? '').toString();

    if (perfil == perfilAdministrador && !permitido) {
      throw StateError('O perfil Administrador possui acesso completo.');
    }

    await database.insert(
      'financeiro_usuario_permissoes',
      {
        'usuario_id': usuarioId,
        'modulo': modulo,
        'permitido': permitido ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _registrarAuditoria(
      database,
      usuarioId: usuarioId,
      acao: 'Permissao',
      detalhe:
          '${nomesModulos[modulo] ?? modulo}: ${permitido ? 'liberado' : 'bloqueado'}',
    );

    if (_int(_sessaoAtual?['id']) == usuarioId) {
      final atual = _sessaoAtual;
      if (atual != null) {
        final permissoes = <String, bool>{};
        final brutas = atual['permissoes'];
        if (brutas is Map) {
          for (final entry in brutas.entries) {
            permissoes[entry.key.toString()] = entry.value == true;
          }
        }
        permissoes[modulo] = permitido;
        _sessaoAtual = <String, dynamic>{...atual, 'permissoes': permissoes};
      }
    }
  }

  Future<Map<String, bool>> obterPermissoes(int usuarioId) async {
    final database = await _appDatabase.database;
    await _garantirEstrutura(database);

    final usuario = await database.query(
      'financeiro_usuarios',
      columns: ['perfil'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );

    if (usuario.isEmpty) {
      return <String, bool>{};
    }

    final perfil = (usuario.first['perfil'] ?? '').toString();

    if (perfil == perfilAdministrador) {
      return {for (final modulo in modulos) modulo: true};
    }

    final resultado = await database.query(
      'financeiro_usuario_permissoes',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
    );

    final mapa = <String, bool>{
      for (final modulo in modulos) modulo: permissaoPadrao(perfil, modulo),
    };

    for (final item in resultado) {
      final modulo = (item['modulo'] ?? '').toString();
      if (modulos.contains(modulo)) {
        mapa[modulo] = _int(item['permitido']) == 1;
      }
    }

    return mapa;
  }

  Future<bool> podeAcessar({
    required int usuarioId,
    required String modulo,
  }) async {
    final permissoes = await obterPermissoes(usuarioId);
    return permissoes[modulo] ?? false;
  }

  static const List<String> modulos = <String>[
    'dashboard',
    'clientes',
    'crm',
    'agenda',
    'orcamentos',
    'ordens_servico',
    'estoque',
    'financeiro',
    'dre',
    'precificacao',
    'funcionarios',
    'ponto',
    'configuracoes',
  ];

  static const Map<String, String> nomesModulos = <String, String>{
    'dashboard': 'Dashboard',
    'clientes': 'Clientes',
    'crm': 'CRM',
    'agenda': 'Agenda',
    'orcamentos': 'Orçamentos',
    'ordens_servico': 'Ordens de Serviço',
    'estoque': 'Estoque',
    'financeiro': 'Financeiro',
    'dre': 'DRE',
    'precificacao': 'Precificação',
    'funcionarios': 'Funcionários',
    'ponto': 'Ponto',
    'configuracoes': 'Configurações',
  };

  static bool permissaoPadrao(String perfil, String modulo) {
    if (perfil == perfilAdministrador) {
      return true;
    }

    if (perfil == perfilFuncionario) {
      return <String>{'ponto'}.contains(modulo);
    }

    return false;
  }

  static int? _intNulo(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
