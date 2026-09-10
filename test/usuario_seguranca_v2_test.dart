import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/usuario_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late UsuarioRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_usuario_seguranca_v2_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
    repository = UsuarioRepository();
    repository.encerrarSessao();
    await repository.garantirEstrutura();
  });

  tearDown(() async {
    repository.encerrarSessao();
    await _removerBanco(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  test(
    'cinco falhas recentes bloqueiam e administrador pode liberar',
    () async {
      final usuarios = await repository.listarUsuarios();
      final admin = usuarios.firstWhere(
        (item) => item['perfil'] == UsuarioRepository.perfilAdministrador,
      );
      final adminId = (admin['id'] as num).toInt();

      await repository.definirPin(usuarioId: adminId, pin: '1234');

      final database = await AppDatabase.instance.database;
      final agora = DateTime.now();

      for (var i = 0; i < UsuarioRepository.maxTentativasPin; i++) {
        await database.insert('financeiro_usuario_acessos', {
          'usuario_id': adminId,
          'login': 'admin',
          'sucesso': 0,
          'motivo': 'PIN inválido',
          'criado_em': agora
              .subtract(
                Duration(seconds: UsuarioRepository.maxTentativasPin - i),
              )
              .toIso8601String(),
        });
      }

      final bloqueio = await repository.obterBloqueioLogin('admin');
      expect(bloqueio['bloqueado'], isTrue);
      expect(bloqueio['falhas'], UsuarioRepository.maxTentativasPin);

      await expectLater(
        repository.autenticar(login: 'admin', pin: '1234'),
        throwsA(isA<StateError>()),
      );

      await repository.liberarBloqueioUsuario(adminId);
      final liberado = await repository.obterBloqueioLogin('admin');
      expect(liberado['bloqueado'], isFalse);

      final sessao = await repository.autenticar(login: 'admin', pin: '1234');
      expect(sessao['id'], adminId);
    },
  );

  test('usuário troca o próprio PIN somente após validar o atual', () async {
    final usuarios = await repository.listarUsuarios();
    final adminId = (usuarios.first['id'] as num).toInt();

    await repository.definirPin(usuarioId: adminId, pin: '1234');

    await expectLater(
      repository.alterarPinComPinAtual(
        usuarioId: adminId,
        pinAtual: '9999',
        novoPin: '4321',
      ),
      throwsA(isA<StateError>()),
    );

    await repository.alterarPinComPinAtual(
      usuarioId: adminId,
      pinAtual: '1234',
      novoPin: '4321',
    );

    await expectLater(
      repository.autenticar(login: 'admin', pin: '1234'),
      throwsA(isA<StateError>()),
    );

    final sessao = await repository.autenticar(login: 'admin', pin: '4321');
    expect(sessao['id'], adminId);

    final auditoria = await repository.listarAuditoriaUsuario(
      usuarioId: adminId,
    );
    expect(
      auditoria.map((item) => item['acao']),
      contains('AlteracaoPinProprio'),
    );
  });

  test('módulo CRM permanece na matriz de permissões', () {
    expect(UsuarioRepository.modulos, contains('crm'));
    expect(UsuarioRepository.nomesModulos['crm'], 'CRM');
  });

  test(
    'telas expõem segurança do próprio usuário e liberação administrativa',
    () {
      final inicio = File(
        'lib/screens/usuario_inicio_page.dart',
      ).readAsStringSync();
      final perfil = File(
        'lib/screens/meu_perfil_page.dart',
      ).readAsStringSync();
      final permissoes = File(
        'lib/screens/usuarios_permissoes_page.dart',
      ).readAsStringSync();

      expect(inicio, contains('Meu perfil e segurança'));
      expect(perfil, contains('alterarPinComPinAtual'));
      expect(permissoes, contains('Liberar tentativas de PIN'));
      expect(permissoes, contains('Auditoria de segurança'));
    },
  );
}

Future<void> _removerBanco(String caminho) async {
  try {
    await AppDatabase.instance.fecharBanco();
  } catch (_) {
    // O banco pode não ter sido aberto neste teste.
  }

  try {
    await databaseFactory.deleteDatabase(caminho);
  } catch (_) {
    // Limpeza best-effort em Windows.
  }
}
