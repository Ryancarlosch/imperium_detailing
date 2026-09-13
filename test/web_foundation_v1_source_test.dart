import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppDatabase nao importa dart io diretamente', () {
    final source = File('lib/database/app_database.dart').readAsStringSync();
    expect(source, isNot(contains("import 'dart:io';")));
    expect(source, contains("import 'tenant_database_platform.dart';"));
    expect(source, contains('static const int schemaVersion = 33;'));
  });

  test('Web usa SQLite WASM e SharedPreferences para tenant', () {
    final source = File(
      'lib/database/tenant_database_platform_web.dart',
    ).readAsStringSync();
    expect(source, contains('databaseFactoryFfiWeb'));
    expect(source, contains('SharedPreferences.getInstance'));
    expect(source, contains('sqlite-wasm-indexeddb'));
  });

  test('IO preserva copia do banco legado', () {
    final source = File(
      'lib/database/tenant_database_platform_io.dart',
    ).readAsStringSync();
    expect(source, contains('origem.copy(temporario.path)'));
    expect(source, isNot(contains('origem.rename(')));
  });

  test('Entrypoint Web continua isolado das telas mobile', () {
    final source = File('lib/main_web.dart').readAsStringSync();
    expect(source, contains('ImperiumWebApp'));
    expect(source, contains('WebOperacionalShell'));
    expect(source, isNot(contains('dashboard_page.dart')));
    expect(source, isNot(contains('backup_automatico_service.dart')));
  });

  test('Target Web e assets SQLite existem', () {
    expect(File('web/index.html').existsSync(), isTrue);
    expect(File('web/sqlite3.wasm').existsSync(), isTrue);
    expect(File('web/sqflite_sw.js').existsSync(), isTrue);
  });
}
