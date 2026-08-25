import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/main.dart';
import 'package:imperium_detailing/services/primeiro_uso_assistente.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_widget_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);

    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);

    // Cria o banco e o schema antes de montar o aplicativo.
    await AppDatabase.instance.database;
  });

  tearDown(() async {
    await AppDatabase.instance.fecharBanco();

    if (await databaseFactory.databaseExists(caminhoBanco)) {
      await databaseFactory.deleteDatabase(caminhoBanco);
    }
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('ImperiumApp', () {
    testWidgets('inicia corretamente', (tester) async {
      _configurarTela(tester);

      await tester.pumpWidget(const ImperiumApp());

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verifica somente a estrutura principal do aplicativo.
      // A tela inicial pode mudar conforme login,
      // primeiro uso ou estado salvo do sistema.
      expect(find.byType(ImperiumApp), findsOneWidget);

      expect(find.byType(MaterialApp), findsOneWidget);

      await _encerrarArvore(tester);
    });

    testWidgets('mantém locale pt-BR e tema escuro', (tester) async {
      _configurarTela(tester);

      await tester.pumpWidget(const ImperiumApp());

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.title, 'Imperium Detailing');

      expect(materialApp.locale, const Locale('pt', 'BR'));

      expect(materialApp.debugShowCheckedModeBanner, isFalse);

      expect(materialApp.theme?.brightness, Brightness.dark);

      await _encerrarArvore(tester);
    });
  });

  group('Assistente de primeiro uso', () {
    testWidgets('abre, avança e fecha corretamente', (tester) async {
      _configurarTela(tester);

      await tester.pumpWidget(const MaterialApp(home: _AssistenteTesteHost()));

      await tester.tap(find.text('Abrir assistente'));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Primeiros passos'), findsOneWidget);

      expect(find.text('Configurações da empresa'), findsOneWidget);

      expect(find.text('1 de 6'), findsOneWidget);

      await tester.tap(find.text('Próximo'));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Serviços'), findsOneWidget);

      expect(find.text('2 de 6'), findsOneWidget);

      await tester.tap(find.text('Fechar'));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Primeiros passos'), findsNothing);

      expect(find.text('Abrir assistente'), findsOneWidget);
    });
  });
}

class _AssistenteTesteHost extends StatelessWidget {
  const _AssistenteTesteHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () {
            mostrarAssistentePrimeiroUso(context, forcarExibicao: true);
          },
          child: const Text('Abrir assistente'),
        ),
      ),
    );
  }
}

void _configurarTela(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1200);

  tester.view.devicePixelRatio = 1;

  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _encerrarArvore(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.runAsync(() async {
    await Future.delayed(const Duration(milliseconds: 350));
  });
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
