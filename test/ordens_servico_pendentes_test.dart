import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/ordem_servico_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pasta;
  late String caminho;
  late OrdemServicoRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pasta = await Directory.systemTemp.createTemp(
      'imperium_os_pendentes_test_',
    );
    await databaseFactory.setDatabasesPath(pasta.path);
    caminho = path.join(pasta.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminho);
    repository = OrdemServicoRepository();
  });

  tearDown(() async => _removerBanco(caminho));

  tearDownAll(() async {
    if (await pasta.exists()) {
      await pasta.delete(recursive: true);
    }
  });

  test('filtro Pendentes retorna Aberta e Em andamento', () async {
    final database = await AppDatabase.instance.database;
    final clienteId = await database.insert('clientes', {
      'nome': 'Cliente filtro OS',
      'telefone': '',
      'email': '',
      'endereco': '',
      'observacoes': '',
    });

    Future<void> inserir(String numero, String status) async {
      await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'numero': numero,
        'status': status,
        'data_abertura': '2026-09-10T08:00:00.000',
        'funcionario_responsavel': '',
        'observacoes': '',
        'valor_total': 100,
        'desconto': 0,
        'quilometragem_entrada': '',
        'combustivel_entrada': '',
      });
    }

    await inserir('OS-PEND-1', 'Aberta');
    await inserir('OS-PEND-2', 'Em andamento');
    await inserir('OS-PEND-3', 'Finalizada');
    await inserir('OS-PEND-4', 'Cancelada');

    final lista = await repository.listarOrdensServico(status: 'Pendentes');
    expect(lista, hasLength(2));
    expect(lista.map((item) => item.status).toSet(), {
      'Aberta',
      'Em andamento',
    });

    final detalhes = await repository.listarOrdensServicoComDetalhes(
      status: 'Pendentes',
    );
    expect(detalhes, hasLength(2));
    expect(detalhes.map((item) => item['status']).toSet(), {
      'Aberta',
      'Em andamento',
    });
  });

  test('tela expõe Pendentes sem criar novo status de OS', () {
    final tela = File(
      'lib/screens/ordens_servico_page.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/repositories/ordem_servico_repository.dart',
    ).readAsStringSync();

    expect(tela, contains("'Pendentes'"));
    expect(repo, contains("os.status IN (?, ?)"));
    expect(repo, contains("['Aberta', 'Em andamento']"));
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
