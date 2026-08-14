import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/google_drive_oauth_config.dart';

class GoogleDriveBackupException implements Exception {
  const GoogleDriveBackupException(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

class GoogleDriveEstado {
  const GoogleDriveEstado({
    required this.configurado,
    required this.conectado,
    this.email,
    this.nome,
    this.ultimoEnvioEm,
    this.ultimoArquivoNome,
    this.ultimoErro,
  });

  final bool configurado;
  final bool conectado;
  final String? email;
  final String? nome;
  final String? ultimoEnvioEm;
  final String? ultimoArquivoNome;
  final String? ultimoErro;
}

class GoogleDriveUploadResultado {
  const GoogleDriveUploadResultado({
    required this.executado,
    required this.sucesso,
    required this.mensagem,
    this.arquivoId,
    this.arquivoNome,
  });

  final bool executado;
  final bool sucesso;
  final String mensagem;
  final String? arquivoId;
  final String? arquivoNome;
}

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static final GoogleDriveBackupService instance = GoogleDriveBackupService._();

  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const String _nomePasta = 'Imperium Detailing - Backups';
  static const String _nomeEstadoLocal = 'imperium_google_drive.json';
  static const String _prefixoBackupAutomatico = 'imperium_backup_auto_';

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<void>? _inicializacao;
  GoogleSignInAccount? _usuario;

  bool get configurado => GoogleDriveOAuthConfig.configurado;

  Future<void> inicializar() {
    return _inicializacao ??= _inicializarInterno();
  }

  Future<void> _inicializarInterno() async {
    if (!configurado) {
      return;
    }

    await _googleSignIn.initialize(
      serverClientId: GoogleDriveOAuthConfig.serverClientId,
    );

    _googleSignIn.authenticationEvents.listen((evento) {
      if (evento is GoogleSignInAuthenticationEventSignIn) {
        _usuario = evento.user;
      } else if (evento is GoogleSignInAuthenticationEventSignOut) {
        _usuario = null;
      }
    });

    try {
      final tentativa = _googleSignIn.attemptLightweightAuthentication();

      if (tentativa != null) {
        final usuario = await tentativa;
        if (usuario != null) {
          _usuario = usuario;
        }
      }
    } catch (_) {
      // A restauração silenciosa é best-effort.
      // A conexão interativa continua disponível na tela.
    }
  }

  Future<GoogleDriveEstado> obterEstado() async {
    final local = await _lerEstadoLocal();

    if (!configurado) {
      return GoogleDriveEstado(
        configurado: false,
        conectado: false,
        email: _textoNulo(local['email']),
        nome: _textoNulo(local['nome']),
        ultimoEnvioEm: _textoNulo(local['ultimo_envio_em']),
        ultimoArquivoNome: _textoNulo(local['ultimo_arquivo_nome']),
        ultimoErro: _textoNulo(local['ultimo_erro']),
      );
    }

    await inicializar();

    final usuario = _usuario;

    return GoogleDriveEstado(
      configurado: true,
      conectado: usuario != null,
      email: usuario?.email ?? _textoNulo(local['email']),
      nome: usuario?.displayName ?? _textoNulo(local['nome']),
      ultimoEnvioEm: _textoNulo(local['ultimo_envio_em']),
      ultimoArquivoNome: _textoNulo(local['ultimo_arquivo_nome']),
      ultimoErro: _textoNulo(local['ultimo_erro']),
    );
  }

  Future<GoogleDriveEstado> conectar() async {
    if (!configurado) {
      throw const GoogleDriveBackupException(
        'O Client ID do Google ainda não foi configurado.',
      );
    }

    await inicializar();

    GoogleSignInAccount? usuario = _usuario;

    if (usuario == null) {
      if (!_googleSignIn.supportsAuthenticate()) {
        throw const GoogleDriveBackupException(
          'Este dispositivo não oferece o fluxo de login Google esperado.',
        );
      }

      usuario = await _googleSignIn.authenticate(scopeHint: _scopes);
      _usuario = usuario;
    }

    await usuario.authorizationClient.authorizeScopes(_scopes);

    final headers = await usuario.authorizationClient.authorizationHeaders(
      _scopes,
    );

    if (headers == null) {
      throw const GoogleDriveBackupException(
        'O Google não liberou a autorização necessária para o Drive.',
      );
    }

    await _garantirPasta(headers);

    await _atualizarEstadoLocal({
      'email': usuario.email,
      'nome': usuario.displayName,
      'ultimo_erro': null,
    });

    return obterEstado();
  }

  Future<GoogleDriveEstado> desconectar() async {
    if (configurado) {
      await inicializar();

      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Mantém o estado local consistente mesmo se o provedor falhar.
      }
    }

    _usuario = null;

    await _atualizarEstadoLocal({
      'email': null,
      'nome': null,
      'ultimo_erro': null,
    });

    return obterEstado();
  }

  Future<GoogleDriveUploadResultado> enviarSeConectado(
    String caminhoArquivo, {
    required int manterCopias,
  }) async {
    if (!configurado) {
      return const GoogleDriveUploadResultado(
        executado: false,
        sucesso: true,
        mensagem: 'Google Drive ainda não configurado.',
      );
    }

    await inicializar();

    final usuario = _usuario;
    if (usuario == null) {
      return const GoogleDriveUploadResultado(
        executado: false,
        sucesso: true,
        mensagem: 'Google Drive não conectado.',
      );
    }

    final autorizacao = await usuario.authorizationClient
        .authorizationForScopes(_scopes);

    if (autorizacao == null) {
      return const GoogleDriveUploadResultado(
        executado: false,
        sucesso: true,
        mensagem: 'Google Drive precisa ser autorizado novamente.',
      );
    }

    return _enviarArquivo(
      usuario,
      caminhoArquivo,
      manterCopias: manterCopias,
      permitirInteracao: false,
    );
  }

  Future<GoogleDriveUploadResultado> enviarAgora(
    String caminhoArquivo, {
    required int manterCopias,
  }) async {
    if (!configurado) {
      throw const GoogleDriveBackupException(
        'O Client ID do Google ainda não foi configurado.',
      );
    }

    await inicializar();

    final usuario = _usuario;
    if (usuario == null) {
      throw const GoogleDriveBackupException(
        'Conecte uma conta Google antes de enviar o backup.',
      );
    }

    return _enviarArquivo(
      usuario,
      caminhoArquivo,
      manterCopias: manterCopias,
      permitirInteracao: true,
    );
  }

  Future<GoogleDriveUploadResultado> _enviarArquivo(
    GoogleSignInAccount usuario,
    String caminhoArquivo, {
    required int manterCopias,
    required bool permitirInteracao,
  }) async {
    final arquivo = File(caminhoArquivo);

    if (!await arquivo.exists()) {
      throw const GoogleDriveBackupException(
        'O arquivo de backup local não foi encontrado.',
      );
    }

    try {
      if (permitirInteracao) {
        final autorizacao = await usuario.authorizationClient
            .authorizationForScopes(_scopes);

        if (autorizacao == null) {
          await usuario.authorizationClient.authorizeScopes(_scopes);
        }
      }

      final headers = await usuario.authorizationClient.authorizationHeaders(
        _scopes,
      );

      if (headers == null) {
        throw const GoogleDriveBackupException(
          'A autorização do Google Drive expirou. Reconecte a conta.',
        );
      }

      final pastaId = await _garantirPasta(headers);
      final resultado = await _uploadResumivel(
        headers: headers,
        arquivo: arquivo,
        pastaId: pastaId,
      );

      await _aplicarRetencao(
        headers: headers,
        pastaId: pastaId,
        manter: manterCopias.clamp(1, 30),
      );

      final agora = DateTime.now().toIso8601String();

      await _atualizarEstadoLocal({
        'email': usuario.email,
        'nome': usuario.displayName,
        'ultimo_envio_em': agora,
        'ultimo_arquivo_id': resultado.$1,
        'ultimo_arquivo_nome': resultado.$2,
        'ultimo_erro': null,
      });

      return GoogleDriveUploadResultado(
        executado: true,
        sucesso: true,
        mensagem: 'Backup enviado ao Google Drive.',
        arquivoId: resultado.$1,
        arquivoNome: resultado.$2,
      );
    } catch (erro) {
      final mensagem = _textoErro(erro);

      await registrarFalha(mensagem);

      if (erro is GoogleDriveBackupException) {
        rethrow;
      }

      throw GoogleDriveBackupException(mensagem);
    }
  }

  Future<void> registrarFalha(Object erro) async {
    await _atualizarEstadoLocal({'ultimo_erro': _textoErro(erro)});
  }

  Future<(String, String)> _uploadResumivel({
    required Map<String, String> headers,
    required File arquivo,
    required String pastaId,
  }) async {
    final tamanho = await arquivo.length();
    final nome = path.basename(arquivo.path);

    final sessao = await http
        .post(
          Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files'
            '?uploadType=resumable&fields=id,name,createdTime,size',
          ),
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json; charset=UTF-8',
            'X-Upload-Content-Type': 'application/zip',
            'X-Upload-Content-Length': tamanho.toString(),
          },
          body: jsonEncode({
            'name': nome,
            'parents': [pastaId],
            'mimeType': 'application/zip',
            'description': 'Backup automático do Imperium Detailing',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (sessao.statusCode < 200 || sessao.statusCode >= 300) {
      throw GoogleDriveBackupException(
        _mensagemRespostaGoogle(sessao.statusCode, sessao.body),
      );
    }

    final localizacao = sessao.headers['location'];

    if (localizacao == null || localizacao.trim().isEmpty) {
      throw const GoogleDriveBackupException(
        'O Google Drive não retornou a sessão de upload.',
      );
    }

    final cliente = http.Client();

    try {
      final requisicao = http.StreamedRequest('PUT', Uri.parse(localizacao));
      requisicao.headers.addAll({
        ...headers,
        'Content-Type': 'application/zip',
      });
      requisicao.contentLength = tamanho;

      await requisicao.sink.addStream(arquivo.openRead());
      await requisicao.sink.close();

      final respostaStream = await cliente
          .send(requisicao)
          .timeout(const Duration(minutes: 2));
      final corpo = await respostaStream.stream.bytesToString();

      if (respostaStream.statusCode < 200 || respostaStream.statusCode >= 300) {
        throw GoogleDriveBackupException(
          _mensagemRespostaGoogle(respostaStream.statusCode, corpo),
        );
      }

      final mapa = corpo.trim().isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(corpo) as Map);

      final id = mapa['id']?.toString().trim() ?? '';
      final nomeRetornado = mapa['name']?.toString().trim() ?? nome;

      if (id.isEmpty) {
        throw const GoogleDriveBackupException(
          'O upload terminou, mas o Google Drive não retornou o ID do arquivo.',
        );
      }

      return (id, nomeRetornado);
    } finally {
      cliente.close();
    }
  }

  Future<String> _garantirPasta(Map<String, String> headers) async {
    final consulta =
        "name = '${_escaparConsulta(_nomePasta)}' and "
        "mimeType = 'application/vnd.google-apps.folder' and "
        "trashed = false";

    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': consulta,
      'spaces': 'drive',
      'pageSize': '10',
      'fields': 'files(id,name)',
    });

    final resposta = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));

    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      throw GoogleDriveBackupException(
        _mensagemRespostaGoogle(resposta.statusCode, resposta.body),
      );
    }

    final mapa = Map<String, dynamic>.from(jsonDecode(resposta.body) as Map);

    final arquivos = (mapa['files'] as List?) ?? const [];

    for (final item in arquivos) {
      if (item is! Map) continue;

      final id = item['id']?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        return id;
      }
    }

    final criar = await http
        .post(
          Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id,name'),
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: jsonEncode({
            'name': _nomePasta,
            'mimeType': 'application/vnd.google-apps.folder',
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (criar.statusCode < 200 || criar.statusCode >= 300) {
      throw GoogleDriveBackupException(
        _mensagemRespostaGoogle(criar.statusCode, criar.body),
      );
    }

    final criado = Map<String, dynamic>.from(jsonDecode(criar.body) as Map);

    final id = criado['id']?.toString().trim() ?? '';

    if (id.isEmpty) {
      throw const GoogleDriveBackupException(
        'A pasta do Imperium foi criada sem um ID válido.',
      );
    }

    return id;
  }

  Future<void> _aplicarRetencao({
    required Map<String, String> headers,
    required String pastaId,
    required int manter,
  }) async {
    try {
      final consulta =
          "'${_escaparConsulta(pastaId)}' in parents and "
          "trashed = false and "
          "name contains '$_prefixoBackupAutomatico'";

      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': consulta,
        'spaces': 'drive',
        'pageSize': '100',
        'orderBy': 'createdTime desc',
        'fields': 'files(id,name,createdTime)',
      });

      final resposta = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        return;
      }

      final mapa = Map<String, dynamic>.from(jsonDecode(resposta.body) as Map);

      final arquivos = (mapa['files'] as List?) ?? const [];

      for (var i = manter; i < arquivos.length; i++) {
        final item = arquivos[i];
        if (item is! Map) continue;

        final id = item['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;

        try {
          await http.delete(
            Uri.parse('https://www.googleapis.com/drive/v3/files/$id'),
            headers: headers,
          );
        } catch (_) {
          // Retenção best-effort.
        }
      }
    } catch (_) {
      // Nunca invalida um upload novo só porque a limpeza falhou.
    }
  }

  Future<Map<String, dynamic>> _lerEstadoLocal() async {
    final arquivo = await _arquivoEstadoLocal();

    if (!await arquivo.exists()) {
      return <String, dynamic>{};
    }

    try {
      final conteudo = await arquivo.readAsString();
      final decodificado = jsonDecode(conteudo);

      if (decodificado is Map) {
        return Map<String, dynamic>.from(decodificado);
      }
    } catch (_) {
      // Estado local corrompido não bloqueia o Drive.
    }

    return <String, dynamic>{};
  }

  Future<void> _atualizarEstadoLocal(Map<String, dynamic> alteracoes) async {
    final atual = await _lerEstadoLocal();

    for (final entrada in alteracoes.entries) {
      if (entrada.value == null) {
        atual.remove(entrada.key);
      } else {
        atual[entrada.key] = entrada.value;
      }
    }

    final arquivo = await _arquivoEstadoLocal();
    await arquivo.parent.create(recursive: true);

    final temporario = File('${arquivo.path}.tmp');

    await temporario.writeAsString(
      const JsonEncoder.withIndent('  ').convert(atual),
      flush: true,
    );

    if (await arquivo.exists()) {
      await arquivo.delete();
    }

    await temporario.rename(arquivo.path);
  }

  Future<File> _arquivoEstadoLocal() async {
    final documentos = await getApplicationDocumentsDirectory();

    return File(path.join(documentos.path, _nomeEstadoLocal));
  }

  String _mensagemRespostaGoogle(int status, String corpo) {
    String? mensagem;

    try {
      final mapa = jsonDecode(corpo);
      if (mapa is Map) {
        final erro = mapa['error'];

        if (erro is Map) {
          mensagem = erro['message']?.toString().trim();
        }
      }
    } catch (_) {
      // Usa fallback abaixo.
    }

    final detalhe = mensagem == null || mensagem.isEmpty
        ? 'Resposta HTTP $status.'
        : mensagem;

    if (status == 401) {
      return 'A sessão do Google expirou. Reconecte a conta. $detalhe';
    }

    if (status == 403) {
      return 'O Google Drive recusou a operação. Verifique se a Drive API '
          'está ativada e se o escopo foi autorizado. $detalhe';
    }

    return 'Falha no Google Drive. $detalhe';
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'GoogleDriveBackupException: ',
      'GoogleSignInException: ',
      'Bad state: ',
      'Invalid argument(s): ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Falha desconhecida no Google Drive.' : texto;
  }

  String _escaparConsulta(String valor) {
    return valor.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
