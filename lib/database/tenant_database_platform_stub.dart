Future<void> inicializarTenantDatabasePlatform() async {}

Future<String?> lerTenantAtivoPlatform() async => null;

Future<void> salvarTenantAtivoPlatform(String empresaId) async {
  throw UnsupportedError('Plataforma de banco local não suportada.');
}

Future<String> caminhoBancoLegadoPlatform() async {
  return 'imperium_detailing.db';
}

Future<String> caminhoBancoEmpresaPlatform(String empresaId) async {
  return 'imperium_detailing_empresa_$empresaId.db';
}

Future<bool> bancoExistePlatform(String caminho) async => false;

Future<bool> suportaAdocaoBancoLegadoPlatform() async => false;

Future<void> copiarBancoLegadoPlatform(String destino) async {
  throw UnsupportedError('Adoção de banco legado não suportada.');
}

Future<List<String>> listarEmpresasLocaisPlatform() async {
  return const <String>[];
}

String descricaoTenantDatabasePlatform() => 'stub';
