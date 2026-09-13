import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

const String _tenantKey = 'imperium_tenant_atual';
const String _nomeBancoLegado = 'imperium_detailing_web.db';

bool _inicializado = false;

Future<void> inicializarTenantDatabasePlatform() async {
  if (_inicializado) return;

  databaseFactory = databaseFactoryFfiWeb;
  _inicializado = true;
}

Future<String?> lerTenantAtivoPlatform() async {
  await inicializarTenantDatabasePlatform();
  final preferencias = await SharedPreferences.getInstance();
  final valor = preferencias.getString(_tenantKey)?.trim() ?? '';
  return valor.isEmpty ? null : valor;
}

Future<void> salvarTenantAtivoPlatform(String empresaId) async {
  await inicializarTenantDatabasePlatform();
  final preferencias = await SharedPreferences.getInstance();
  await preferencias.setString(_tenantKey, empresaId);
}

Future<String> caminhoBancoLegadoPlatform() async {
  await inicializarTenantDatabasePlatform();
  return _nomeBancoLegado;
}

Future<String> caminhoBancoEmpresaPlatform(String empresaId) async {
  await inicializarTenantDatabasePlatform();
  return 'imperium_detailing_empresa_$empresaId.db';
}

Future<bool> bancoExistePlatform(String caminho) async {
  await inicializarTenantDatabasePlatform();
  return databaseFactory.databaseExists(caminho);
}

Future<bool> suportaAdocaoBancoLegadoPlatform() async => false;

Future<void> copiarBancoLegadoPlatform(String destino) async {
  throw UnsupportedError(
    'O navegador não adota o SQLite legado do Android. '
    'Cada tenant Web começa em seu próprio IndexedDB.',
  );
}

Future<List<String>> listarEmpresasLocaisPlatform() async {
  await inicializarTenantDatabasePlatform();

  final atual = await lerTenantAtivoPlatform();
  if (atual == null || atual.isEmpty) {
    return const <String>[];
  }

  final caminho = await caminhoBancoEmpresaPlatform(atual);
  if (!await bancoExistePlatform(caminho)) {
    return const <String>[];
  }

  return <String>[atual];
}

String descricaoTenantDatabasePlatform() => 'sqlite-wasm-indexeddb';
