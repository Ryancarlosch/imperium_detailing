import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/services/backup_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory raiz;
  late Directory documentos;
  late Directory temporarios;
  late Directory bancos;
  late String caminhoBanco;
  late BackupService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.fecharBanco();

    raiz = await Directory.systemTemp.createTemp(
      'imperium_backup_service_test_',
    );

    documentos = Directory(path.join(raiz.path, 'documentos'));
    temporarios = Directory(path.join(raiz.path, 'temporarios'));
    bancos = Directory(path.join(raiz.path, 'bancos'));

    await documentos.create(recursive: true);
    await temporarios.create(recursive: true);
    await bancos.create(recursive: true);

    await databaseFactory.setDatabasesPath(bancos.path);

    caminhoBanco = path.join(bancos.path, 'imperium_detailing.db');

    service = _criarService(documentos: documentos, temporarios: temporarios);
  });

  tearDown(() async {
    await AppDatabase.instance.fecharBanco();

    if (await databaseFactory.databaseExists(caminhoBanco)) {
      await databaseFactory.deleteDatabase(caminhoBanco);
    }

    if (await raiz.exists()) {
      await raiz.delete(recursive: true);
    }
  });

  group('BackupService - criação', () {
    test('inclui banco, metadados e todos os arquivos persistentes', () async {
      final dados = await _prepararDadosComArquivos(documentos);

      final resumo = await service.criarBackup();

      expect(File(resumo.caminhoArquivo).existsSync(), isTrue);
      expect(resumo.tamanhoBytes, greaterThan(0));
      expect(resumo.versaoApp, '1.0.0');
      expect(resumo.versaoBanco, AppDatabase.schemaVersion);
      expect(resumo.avisos, isEmpty);
      expect(resumo.quantidadeArquivos, 9);

      final archive = ZipDecoder().decodeBytes(
        await File(resumo.caminhoArquivo).readAsBytes(),
      );

      final nomes = archive.files
          .where((arquivo) => arquivo.isFile)
          .map((arquivo) => arquivo.name.replaceAll('\\', '/'))
          .toList();

      expect(nomes.any((nome) => nome.endsWith('/metadata.json')), isTrue);
      expect(
        nomes.any((nome) => nome.endsWith('/imperium_detailing.db')),
        isTrue,
      );

      for (final relativo in dados.relativosArquivos) {
        expect(
          nomes.any(
            (nome) => nome.endsWith('/files/${relativo.replaceAll('\\', '/')}'),
          ),
          isTrue,
          reason: 'Arquivo não encontrado no ZIP: $relativo',
        );
      }

      final metadataEntry = archive.files.firstWhere(
        (arquivo) =>
            arquivo.isFile &&
            arquivo.name.replaceAll('\\', '/').endsWith('/metadata.json'),
      );

      final metadata =
          jsonDecode(utf8.decode(metadataEntry.content as List<int>))
              as Map<String, dynamic>;

      expect(metadata['app'], 'Imperium Detailing');
      expect(metadata['formato_backup'], 'zip');
      expect(metadata['identificador_formato'], 'imperium_detailing_backup_v1');
      expect(metadata['versao_banco'], AppDatabase.schemaVersion);
      expect(metadata['versao_app'], '1.0.0');
      expect(metadata['build_app'], '100');
      expect(metadata['quantidade_arquivos'], 9);

      final database = await AppDatabase.instance.database;
      final configuracao = await database.query(
        'configuracoes',
        columns: [
          'ultimo_backup_em',
          'ultimo_backup_caminho',
          'ultimo_backup_tamanho_bytes',
        ],
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );

      expect(configuracao, hasLength(1));
      expect(
        configuracao.single['ultimo_backup_caminho'],
        resumo.caminhoArquivo,
      );
      expect(
        (configuracao.single['ultimo_backup_tamanho_bytes'] as num).toInt(),
        resumo.tamanhoBytes,
      );
      expect(
        configuracao.single['ultimo_backup_em']?.toString().trim(),
        isNotEmpty,
      );
    });

    test(
      'arquivo persistente ausente gera aviso sem invalidar o backup',
      () async {
        final database = await AppDatabase.instance.database;

        final caminhoAusente = path.join(
          documentos.path,
          'logos',
          'logo_ausente.png',
        );

        await database.update(
          'configuracoes',
          {'caminho_logo': caminhoAusente},
          where: 'id = ?',
          whereArgs: [1],
        );

        final resumo = await service.criarBackup();

        expect(File(resumo.caminhoArquivo).existsSync(), isTrue);
        expect(resumo.avisos, hasLength(1));
        expect(resumo.avisos.single, contains('logo_ausente.png'));
        expect(resumo.quantidadeArquivos, 2);
      },
    );
  });

  group('BackupService - validação e restauração', () {
    test('restaura banco e arquivos em uma nova pasta de documentos', () async {
      final dados = await _prepararDadosComArquivos(documentos);

      final resumo = await service.criarBackup();
      final backupExterno = File(path.join(raiz.path, 'backup_externo.zip'));
      await File(resumo.caminhoArquivo).copy(backupExterno.path);

      final database = await AppDatabase.instance.database;

      await database.update(
        'clientes',
        {'nome': 'Cliente alterado depois do backup'},
        where: 'id = ?',
        whereArgs: [dados.clienteId],
      );

      await database.insert('clientes', {
        'nome': 'Cliente que não existe no backup',
      });

      await File(
        dados.caminhoLogo,
      ).writeAsString('CONTEUDO ALTERADO', flush: true);

      final novosDocumentos = Directory(
        path.join(raiz.path, 'documentos_restaurados'),
      );
      await novosDocumentos.create(recursive: true);

      final serviceNovaPasta = _criarService(
        documentos: novosDocumentos,
        temporarios: temporarios,
      );

      final resumoRestauracao = await serviceNovaPasta.restaurarBackup(
        backupExterno.path,
      );

      expect(
        resumoRestauracao.avisos
            .where((aviso) => aviso.contains('rollback'))
            .isEmpty,
        isTrue,
      );

      final bancoRestaurado = await AppDatabase.instance.database;

      final cliente = await bancoRestaurado.query(
        'clientes',
        columns: ['nome'],
        where: 'id = ?',
        whereArgs: [dados.clienteId],
        limit: 1,
      );

      final clienteExtra = await bancoRestaurado.query(
        'clientes',
        where: 'nome = ?',
        whereArgs: ['Cliente que não existe no backup'],
      );

      expect(cliente.single['nome'], 'Cliente original do backup');
      expect(clienteExtra, isEmpty);

      for (final relativo in dados.relativosArquivos) {
        final arquivo = File(path.join(novosDocumentos.path, relativo));

        expect(
          await arquivo.exists(),
          isTrue,
          reason: 'Arquivo não restaurado: $relativo',
        );
      }

      final configuracao = await bancoRestaurado.query(
        'configuracoes',
        columns: ['caminho_logo', 'caminho_assinatura_empresa'],
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );

      expect(
        configuracao.single['caminho_logo'],
        path.join(novosDocumentos.path, 'logos', 'logo_empresa.png'),
      );

      expect(
        configuracao.single['caminho_assinatura_empresa'],
        path.join(
          novosDocumentos.path,
          'assinaturas_empresa',
          'assinatura_empresa.png',
        ),
      );

      final ordem = await bancoRestaurado.query(
        'ordens_servico',
        columns: ['assinatura_cliente'],
        where: 'id = ?',
        whereArgs: [dados.ordemId],
        limit: 1,
      );

      expect(
        ordem.single['assinatura_cliente'],
        path.join(
          novosDocumentos.path,
          'assinaturas_ordens_servico',
          'assinatura_cliente.png',
        ),
      );

      final fotoOs = await bancoRestaurado.query(
        'ordem_servico_fotos',
        columns: ['caminho'],
        where: 'ordem_servico_id = ?',
        whereArgs: [dados.ordemId],
        limit: 1,
      );

      expect(
        fotoOs.single['caminho'],
        path.join(
          novosDocumentos.path,
          'ordens_servico',
          'os_001',
          'foto_antes.jpg',
        ),
      );
    });

    test(
      'backup de outro aplicativo é recusado sem alterar os dados atuais',
      () async {
        final database = await AppDatabase.instance.database;

        final clienteId = await database.insert('clientes', {
          'nome': 'Cliente preservado',
        });

        final arquivo = await _criarZipControlado(
          raiz: raiz,
          nome: 'backup_outro_app.zip',
          metadata: _metadataValido(
            app: 'Outro Aplicativo',
            versaoBanco: AppDatabase.schemaVersion,
          ),
          bancoBytes: const [1, 2, 3],
        );

        await expectLater(
          service.restaurarBackup(arquivo.path),
          throwsA(
            isA<BackupException>().having(
              (erro) => erro.mensagem,
              'mensagem',
              contains('não pertence'),
            ),
          ),
        );

        final bancoDepois = await AppDatabase.instance.database;
        final cliente = await bancoDepois.query(
          'clientes',
          where: 'id = ?',
          whereArgs: [clienteId],
          limit: 1,
        );

        expect(cliente, hasLength(1));
        expect(cliente.single['nome'], 'Cliente preservado');
      },
    );

    test(
      'backup de schema futuro é recusado sem substituir o banco atual',
      () async {
        final database = await AppDatabase.instance.database;

        final clienteId = await database.insert('clientes', {
          'nome': 'Cliente atual',
        });

        final arquivo = await _criarZipControlado(
          raiz: raiz,
          nome: 'backup_futuro.zip',
          metadata: _metadataValido(versaoBanco: AppDatabase.schemaVersion + 1),
          bancoBytes: const [1, 2, 3],
        );

        await expectLater(
          service.restaurarBackup(arquivo.path),
          throwsA(
            isA<BackupException>().having(
              (erro) => erro.mensagem,
              'mensagem',
              contains('schema de banco mais novo'),
            ),
          ),
        );

        final bancoDepois = await AppDatabase.instance.database;
        final cliente = await bancoDepois.query(
          'clientes',
          where: 'id = ?',
          whereArgs: [clienteId],
          limit: 1,
        );

        expect(cliente, hasLength(1));
        expect(cliente.single['nome'], 'Cliente atual');
      },
    );

    test('banco corrompido aciona rollback e preserva o banco atual', () async {
      final database = await AppDatabase.instance.database;

      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente protegido pelo rollback',
      });

      final arquivo = await _criarZipControlado(
        raiz: raiz,
        nome: 'backup_corrompido.zip',
        metadata: _metadataValido(versaoBanco: AppDatabase.schemaVersion),
        bancoBytes: utf8.encode('isto não é um banco sqlite'),
      );

      await expectLater(
        service.restaurarBackup(arquivo.path),
        throwsA(isA<BackupException>()),
      );

      final bancoDepois = await AppDatabase.instance.database;

      final cliente = await bancoDepois.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
        limit: 1,
      );

      expect(cliente, hasLength(1));
      expect(cliente.single['nome'], 'Cliente protegido pelo rollback');

      final integridade = await bancoDepois.rawQuery('PRAGMA integrity_check');

      expect(integridade.first.values.first.toString().toLowerCase(), 'ok');
    });

    test('arquivo inexistente é recusado de forma controlada', () async {
      await expectLater(
        service.restaurarBackup(path.join(raiz.path, 'nao_existe.zip')),
        throwsA(
          isA<BackupException>().having(
            (erro) => erro.mensagem,
            'mensagem',
            contains('não existe'),
          ),
        ),
      );
    });
  });
}

BackupService _criarService({
  required Directory documentos,
  required Directory temporarios,
}) {
  return BackupService.paraTeste(
    obterDocumentos: () async => documentos,
    obterTemporario: () async => temporarios,
    obterPackageInfo: () async => PackageInfo(
      appName: 'Imperium Detailing',
      packageName: 'com.imperium.detailing',
      version: '1.0.0',
      buildNumber: '100',
    ),
  );
}

Future<_DadosBackupTeste> _prepararDadosComArquivos(
  Directory documentos,
) async {
  final logo = await _criarArquivo(
    documentos,
    path.join('logos', 'logo_empresa.png'),
    'logo original',
  );

  final assinaturaEmpresa = await _criarArquivo(
    documentos,
    path.join('assinaturas_empresa', 'assinatura_empresa.png'),
    'assinatura empresa',
  );

  final fotoLegacyAntes = await _criarArquivo(
    documentos,
    path.join('fotos_servicos', 'legacy_antes.jpg'),
    'foto legacy antes',
  );

  final fotoLegacyDepois = await _criarArquivo(
    documentos,
    path.join('fotos_servicos', 'legacy_depois.jpg'),
    'foto legacy depois',
  );

  final fotoOs = await _criarArquivo(
    documentos,
    path.join('ordens_servico', 'os_001', 'foto_antes.jpg'),
    'foto da ordem',
  );

  final fotoAvaria = await _criarArquivo(
    documentos,
    path.join('ordens_servico', 'os_001', 'avaria.jpg'),
    'foto de avaria',
  );

  final assinaturaCliente = await _criarArquivo(
    documentos,
    path.join('assinaturas_ordens_servico', 'assinatura_cliente.png'),
    'assinatura cliente',
  );

  final database = await AppDatabase.instance.database;

  await database.update(
    'configuracoes',
    {
      'nome_fantasia': 'Imperium Teste',
      'caminho_logo': logo.path,
      'caminho_assinatura_empresa': assinaturaEmpresa.path,
    },
    where: 'id = ?',
    whereArgs: [1],
  );

  final clienteId = await database.insert('clientes', {
    'nome': 'Cliente original do backup',
    'telefone': '11999999999',
  });

  final veiculoId = await database.insert('veiculos', {
    'cliente_id': clienteId,
    'marca': 'Volkswagen',
    'modelo': 'Golf',
    'placa': 'ABC1D23',
  });

  await database.insert('fotos_servico', {
    'cliente_id': clienteId,
    'veiculo_id': veiculoId,
    'caminho_antes': fotoLegacyAntes.path,
    'caminho_depois': fotoLegacyDepois.path,
    'descricao': 'Registro legado',
    'data': '2026-08-06',
  });

  final ordemId = await database.insert('ordens_servico', {
    'cliente_id': clienteId,
    'veiculo_id': veiculoId,
    'numero': 'OS-BACKUP-0001',
    'status': 'Finalizada',
    'data_abertura': '2026-08-06',
    'data_inicio': '2026-08-06',
    'data_finalizacao': '2026-08-06',
    'assinatura_cliente': assinaturaCliente.path,
  });

  await database.insert('ordem_servico_fotos', {
    'ordem_servico_id': ordemId,
    'etapa': 'Antes',
    'caminho': fotoOs.path,
    'descricao': 'Foto principal',
    'data': '2026-08-06T20:00:00.000',
    'ordem': 0,
  });

  await database.insert('ordem_servico_checklist', {
    'ordem_servico_id': ordemId,
    'categoria': 'Pintura e carroceria',
    'item': 'Porta dianteira',
    'marcado': 1,
    'status': 2,
    'observacao': 'Avaria registrada',
    'foto_avaria': fotoAvaria.path,
    'avaria_localizacao': 'Porta esquerda',
    'avaria_data_registro': '2026-08-06T20:00:00.000',
    'ordem': 0,
  });

  return _DadosBackupTeste(
    clienteId: clienteId,
    ordemId: ordemId,
    caminhoLogo: logo.path,
    relativosArquivos: [
      path.join('logos', 'logo_empresa.png'),
      path.join('assinaturas_empresa', 'assinatura_empresa.png'),
      path.join('fotos_servicos', 'legacy_antes.jpg'),
      path.join('fotos_servicos', 'legacy_depois.jpg'),
      path.join('ordens_servico', 'os_001', 'foto_antes.jpg'),
      path.join('ordens_servico', 'os_001', 'avaria.jpg'),
      path.join('assinaturas_ordens_servico', 'assinatura_cliente.png'),
    ],
  );
}

Future<File> _criarArquivo(
  Directory documentos,
  String relativo,
  String conteudo,
) async {
  final arquivo = File(path.join(documentos.path, relativo));
  await arquivo.parent.create(recursive: true);
  await arquivo.writeAsString(conteudo, flush: true);
  return arquivo;
}

Map<String, Object?> _metadataValido({
  String app = 'Imperium Detailing',
  required int versaoBanco,
}) {
  return {
    'app': app,
    'formato_backup': 'zip',
    'identificador_formato': 'imperium_detailing_backup_v1',
    'data_criacao': '2026-08-06T20:00:00.000',
    'versao_app': '1.0.0',
    'build_app': '100',
    'versao_banco': versaoBanco,
    'quantidade_arquivos': 2,
    'tamanho_total': 0,
  };
}

Future<File> _criarZipControlado({
  required Directory raiz,
  required String nome,
  required Map<String, Object?> metadata,
  required List<int> bancoBytes,
}) async {
  final staging = Directory(
    path.join(raiz.path, 'zip_${DateTime.now().microsecondsSinceEpoch}'),
  );

  final payload = Directory(path.join(staging.path, 'payload'));
  final databaseDir = Directory(path.join(payload.path, 'database'));

  await databaseDir.create(recursive: true);

  await File(
    path.join(payload.path, 'metadata.json'),
  ).writeAsString(jsonEncode(metadata), flush: true);

  await File(
    path.join(databaseDir.path, 'imperium_detailing.db'),
  ).writeAsBytes(bancoBytes, flush: true);

  final destino = File(path.join(raiz.path, nome));

  final encoder = ZipFileEncoder();
  encoder.create(destino.path);
  encoder.addDirectory(payload);
  encoder.close();

  await staging.delete(recursive: true);

  return destino;
}

class _DadosBackupTeste {
  const _DadosBackupTeste({
    required this.clienteId,
    required this.ordemId,
    required this.caminhoLogo,
    required this.relativosArquivos,
  });

  final int clienteId;
  final int ordemId;
  final String caminhoLogo;
  final List<String> relativosArquivos;
}
