import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

const String _nomeBancoLegado = 'imperium_detailing.db';
const String _nomeMarcadorTenant = 'imperium_tenant_atual.txt';

Future<void> inicializarTenantDatabasePlatform() async {}

Future<String?> lerTenantAtivoPlatform() async {
  final pastaBanco = await getDatabasesPath();
  final marcador = File(path.join(pastaBanco, _nomeMarcadorTenant));

  if (!await marcador.exists()) return null;

  try {
    final valor = (await marcador.readAsString()).trim();
    return valor.isEmpty ? null : valor;
  } catch (_) {
    return null;
  }
}

Future<void> salvarTenantAtivoPlatform(String empresaId) async {
  final pastaBanco = await getDatabasesPath();
  final marcador = File(path.join(pastaBanco, _nomeMarcadorTenant));
  final temporario = File('${marcador.path}.tmp');

  if (await temporario.exists()) {
    await temporario.delete();
  }

  await temporario.writeAsString(empresaId, flush: true);

  if (await marcador.exists()) {
    await marcador.delete();
  }

  await temporario.rename(marcador.path);
}

Future<String> caminhoBancoLegadoPlatform() async {
  return path.join(await getDatabasesPath(), _nomeBancoLegado);
}

Future<String> caminhoBancoEmpresaPlatform(String empresaId) async {
  return path.join(
    await getDatabasesPath(),
    'imperium_detailing_empresa_$empresaId.db',
  );
}

Future<bool> bancoExistePlatform(String caminho) {
  return File(caminho).exists();
}

Future<bool> suportaAdocaoBancoLegadoPlatform() async => true;

Future<void> copiarBancoLegadoPlatform(String destino) async {
  final origem = File(await caminhoBancoLegadoPlatform());

  if (!await origem.exists()) {
    throw StateError('Banco legado não encontrado.');
  }

  final arquivoDestino = File(destino);
  final temporario = File('$destino.adocao_tmp');

  if (await temporario.exists()) {
    await temporario.delete();
  }

  await origem.copy(temporario.path);

  if (await arquivoDestino.exists()) {
    await arquivoDestino.delete();
  }

  await temporario.rename(arquivoDestino.path);
}

Future<List<String>> listarEmpresasLocaisPlatform() async {
  final pastaBanco = Directory(await getDatabasesPath());

  if (!await pastaBanco.exists()) return const <String>[];

  final resultado = <String>[];
  const prefixo = 'imperium_detailing_empresa_';
  const sufixo = '.db';

  await for (final entidade in pastaBanco.list(followLinks: false)) {
    if (entidade is! File) continue;

    final nome = path.basename(entidade.path);

    if (!nome.startsWith(prefixo) || !nome.endsWith(sufixo)) continue;

    final empresa = nome.substring(prefixo.length, nome.length - sufixo.length);

    if (empresa.isNotEmpty) {
      resultado.add(empresa);
    }
  }

  resultado.sort();
  return resultado;
}

String descricaoTenantDatabasePlatform() => 'sqlite-arquivo';
