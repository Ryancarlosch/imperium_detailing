import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/configuracao.dart';
import '../repositories/configuracao_repository.dart';

class BackupException implements Exception {
  const BackupException(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

class BackupResumo {
  const BackupResumo({
    required this.caminhoArquivo,
    required this.tamanhoBytes,
    required this.dataCriacao,
    required this.versaoApp,
    required this.versaoBanco,
    required this.quantidadeArquivos,
    required this.avisos,
  });

  final String caminhoArquivo;
  final int tamanhoBytes;
  final DateTime dataCriacao;
  final String versaoApp;
  final int versaoBanco;
  final int quantidadeArquivos;
  final List<String> avisos;
}

class RestauracaoResumo {
  const RestauracaoResumo({required this.avisos});

  final List<String> avisos;
}

class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const String _appNome = 'Imperium Detailing';
  static const String _identificadorFormato = 'imperium_detailing_backup_v1';

  final AppDatabase _appDatabase = AppDatabase.instance;
  final ConfiguracaoRepository _configuracaoRepository =
      ConfiguracaoRepository();

  Future<BackupResumo> criarBackup() async {
    return _criarBackupInterno(
      registrarNoBanco: true,
      prefixoArquivo: 'imperium_backup',
    );
  }

  Future<RestauracaoResumo> restaurarBackup(String caminhoArquivo) async {
    final arquivoBackup = File(caminhoArquivo);

    if (!await arquivoBackup.exists()) {
      throw const BackupException(
        'O arquivo de backup selecionado não existe.',
      );
    }

    final pastaTemporariaBase = await getTemporaryDirectory();
    final pastaExtracao = Directory(
      path.join(
        pastaTemporariaBase.path,
        'imperium_restore_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );

    if (await pastaExtracao.exists()) {
      await pastaExtracao.delete(recursive: true);
    }

    await pastaExtracao.create(recursive: true);

    final warnings = <String>[];

    try {
      final validacao = await _validarArquivoBackup(arquivoBackup);
      _validarMetadados(validacao.metadados);

      if (validacao.versaoBanco > AppDatabase.schemaVersion) {
        throw BackupException(
          'Este backup foi criado com um schema de banco mais novo. Atualize o aplicativo antes de restaurar.',
        );
      }

      final backupSeguranca = await _criarBackupInterno(
        registrarNoBanco: false,
        prefixoArquivo: 'imperium_backup_seguranca',
      );

      await _appDatabase.fecharBanco();

      try {
        await _aplicarBackupNoSistema(
          arquivoBackup: arquivoBackup,
          pastaExtracao: pastaExtracao,
          warnings: warnings,
        );
      } catch (erro) {
        warnings.add('Restauração principal falhou. Tentando rollback.');

        try {
          await _aplicarBackupNoSistema(
            arquivoBackup: File(backupSeguranca.caminhoArquivo),
            pastaExtracao: pastaExtracao,
            warnings: warnings,
          );
        } catch (_) {
          // Se o rollback falhar, ainda tentamos reabrir o banco original.
        }

        await _reabrirBanco();
        rethrow;
      }

      await _reabrirBanco();
      return RestauracaoResumo(avisos: warnings);
    } finally {
      try {
        if (await pastaExtracao.exists()) {
          await pastaExtracao.delete(recursive: true);
        }
      } catch (_) {
        // Limpeza temporária best-effort.
      }
    }
  }

  Future<BackupResumo> _criarBackupInterno({
    required bool registrarNoBanco,
    required String prefixoArquivo,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final agora = DateTime.now();
    final nomeArquivo = '${prefixoArquivo}_${_formatarDataArquivo(agora)}.zip';

    final pastaDocumentos = await getApplicationDocumentsDirectory();
    final pastaBackups = Directory(path.join(pastaDocumentos.path, 'backups'));
    await pastaBackups.create(recursive: true);

    final arquivoBackup = File(path.join(pastaBackups.path, nomeArquivo));
    if (await arquivoBackup.exists()) {
      await arquivoBackup.delete();
    }

    final pastaTemporariaBase = await getTemporaryDirectory();
    final pastaStaging = Directory(
      path.join(
        pastaTemporariaBase.path,
        'imperium_backup_${agora.millisecondsSinceEpoch}',
      ),
    );

    if (await pastaStaging.exists()) {
      await pastaStaging.delete(recursive: true);
    }

    await pastaStaging.create(recursive: true);

    final pastaConteudo = Directory(path.join(pastaStaging.path, 'payload'));
    final pastaArquivos = Directory(path.join(pastaConteudo.path, 'files'));
    final pastaBanco = Directory(path.join(pastaConteudo.path, 'database'));

    await pastaArquivos.create(recursive: true);
    await pastaBanco.create(recursive: true);

    final warnings = <String>[];
    var quantidadeArquivos = 0;
    var tamanhoConteudo = 0;

    try {
      final database = await _appDatabase.database;
      final configuracao = await _configuracaoRepository.obterConfiguracao();
      final arquivos = await _listarArquivosPersistentes(
        database: database,
        configuracao: configuracao,
        pastaDocumentos: pastaDocumentos,
      );

      for (final entrada in arquivos) {
        final arquivoOrigem = File(entrada.caminhoOriginal);

        if (!await arquivoOrigem.exists()) {
          warnings.add('Arquivo ausente ignorado: ${entrada.caminhoOriginal}');
          continue;
        }

        final arquivoDestino = File(
          path.join(pastaArquivos.path, entrada.relativo),
        );
        await arquivoDestino.parent.create(recursive: true);
        final copia = await arquivoOrigem.copy(arquivoDestino.path);
        quantidadeArquivos++;
        tamanhoConteudo += await copia.length();
      }

      final caminhoBanco = await _obterCaminhoBanco();
      final arquivoBancoOrigem = File(caminhoBanco);

      if (!await arquivoBancoOrigem.exists()) {
        throw const BackupException(
          'O banco de dados local não foi encontrado.',
        );
      }

      await _appDatabase.fecharBanco();

      final arquivoBancoDestino = File(
        path.join(pastaBanco.path, 'imperium_detailing.db'),
      );
      await arquivoBancoOrigem.copy(arquivoBancoDestino.path);
      quantidadeArquivos++;
      tamanhoConteudo += await arquivoBancoDestino.length();

      final metadata = <String, Object?>{
        'app': _appNome,
        'formato_backup': 'zip',
        'identificador_formato': _identificadorFormato,
        'data_criacao': agora.toIso8601String(),
        'versao_app': packageInfo.version,
        'build_app': packageInfo.buildNumber,
        'versao_banco': AppDatabase.schemaVersion,
        'quantidade_arquivos': quantidadeArquivos + 1,
        'tamanho_total': tamanhoConteudo,
      };

      final arquivoMetadata = File(
        path.join(pastaConteudo.path, 'metadata.json'),
      );
      await arquivoMetadata.writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
        flush: true,
      );

      final encoder = ZipFileEncoder();
      encoder.create(arquivoBackup.path);
      encoder.addDirectory(pastaConteudo);
      encoder.close();

      final tamanhoZip = await arquivoBackup.length();

      if (registrarNoBanco) {
        await _configuracaoRepository.atualizarMetadadosBackup(
          dataCriacao: agora.toIso8601String(),
          caminhoBackup: arquivoBackup.path,
          tamanhoBytes: tamanhoZip,
        );
      }

      return BackupResumo(
        caminhoArquivo: arquivoBackup.path,
        tamanhoBytes: tamanhoZip,
        dataCriacao: agora,
        versaoApp: packageInfo.version,
        versaoBanco: AppDatabase.schemaVersion,
        quantidadeArquivos: quantidadeArquivos + 1,
        avisos: warnings,
      );
    } finally {
      try {
        await _appDatabase.database;
      } catch (_) {
        // Reabertura best-effort.
      }

      try {
        if (await pastaStaging.exists()) {
          await pastaStaging.delete(recursive: true);
        }
      } catch (_) {
        // Limpeza best-effort.
      }
    }
  }

  Future<void> _aplicarBackupNoSistema({
    required File arquivoBackup,
    required Directory pastaExtracao,
    required List<String> warnings,
  }) async {
    await _extrairZipSeguro(arquivoBackup, pastaExtracao);

    final raizConteudo = await _localizarRaizConteudo(pastaExtracao);
    if (raizConteudo == null) {
      throw const BackupException(
        'O backup é inválido: estrutura interna não encontrada.',
      );
    }

    final metadataArquivo = await _encontrarArquivoPorNome(
      raizConteudo,
      'metadata.json',
    );
    final databaseArquivo = await _encontrarArquivoPorNome(
      raizConteudo,
      'imperium_detailing.db',
    );

    if (metadataArquivo == null || databaseArquivo == null) {
      throw const BackupException(
        'O backup selecionado não contém metadados ou banco válidos.',
      );
    }

    final validacao = await _validarArquivoBackup(arquivoBackup);
    _validarMetadados(validacao.metadados);

    await _restaurarArquivosDoBackup(
      raizConteudo: raizConteudo,
      pastaDocumentos: await getApplicationDocumentsDirectory(),
      warnings: warnings,
    );

    await _atualizarCaminhosNoBanco(
      arquivoBanco: databaseArquivo,
      pastaDocumentos: await getApplicationDocumentsDirectory(),
      warnings: warnings,
    );

    await _substituirBanco(
      origem: databaseArquivo,
      destino: File(await _obterCaminhoBanco()),
    );
  }

  Future<void> _atualizarCaminhosNoBanco({
    required File arquivoBanco,
    required Directory pastaDocumentos,
    required List<String> warnings,
  }) async {
    final database = await openDatabase(
      arquivoBanco.path,
      version: AppDatabase.schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );

    try {
      final mapeamentos = <_MapaBackup>[
        _MapaBackup(
          tabela: 'configuracoes',
          coluna: 'caminho_logo',
          seletor:
              'SELECT id, caminho_logo AS caminho FROM configuracoes WHERE caminho_logo IS NOT NULL AND TRIM(caminho_logo) != ""',
        ),
        _MapaBackup(
          tabela: 'configuracoes',
          coluna: 'caminho_assinatura_empresa',
          seletor:
              'SELECT id, caminho_assinatura_empresa AS caminho FROM configuracoes WHERE caminho_assinatura_empresa IS NOT NULL AND TRIM(caminho_assinatura_empresa) != ""',
        ),
        _MapaBackup(
          tabela: 'fotos_servico',
          coluna: 'caminho_antes',
          seletor:
              'SELECT id, caminho_antes AS caminho FROM fotos_servico WHERE caminho_antes IS NOT NULL AND TRIM(caminho_antes) != ""',
        ),
        _MapaBackup(
          tabela: 'fotos_servico',
          coluna: 'caminho_depois',
          seletor:
              'SELECT id, caminho_depois AS caminho FROM fotos_servico WHERE caminho_depois IS NOT NULL AND TRIM(caminho_depois) != ""',
        ),
        _MapaBackup(
          tabela: 'ordem_servico_fotos',
          coluna: 'caminho',
          seletor:
              'SELECT id, caminho FROM ordem_servico_fotos WHERE caminho IS NOT NULL AND TRIM(caminho) != ""',
        ),
        _MapaBackup(
          tabela: 'ordem_servico_checklist',
          coluna: 'foto_avaria',
          seletor:
              'SELECT id, foto_avaria AS caminho FROM ordem_servico_checklist WHERE foto_avaria IS NOT NULL AND TRIM(foto_avaria) != ""',
        ),
        _MapaBackup(
          tabela: 'ordens_servico',
          coluna: 'assinatura_cliente',
          seletor:
              'SELECT id, assinatura_cliente AS caminho FROM ordens_servico WHERE assinatura_cliente IS NOT NULL AND TRIM(assinatura_cliente) != ""',
        ),
      ];

      for (final mapa in mapeamentos) {
        final linhas = await database.rawQuery(mapa.seletor);

        for (final linha in linhas) {
          final id = (linha['id'] as num?)?.toInt();
          final caminhoOriginal = linha['caminho']?.toString().trim() ?? '';

          if (id == null || caminhoOriginal.isEmpty) {
            continue;
          }

          final relativo = _extrairRelativo(
            caminhoOriginal,
            pastaDocumentos.path,
          );
          if (relativo == null) {
            warnings.add(
              'Caminho fora da pasta do app ignorado: $caminhoOriginal',
            );
            await database.update(
              mapa.tabela,
              {mapa.coluna: mapa.coluna == 'assinatura_cliente' ? null : ''},
              where: 'id = ?',
              whereArgs: [id],
            );
            continue;
          }

          final novoCaminho = path.join(pastaDocumentos.path, relativo);
          final arquivoExiste = File(novoCaminho).existsSync();

          if (!arquivoExiste) {
            warnings.add('Arquivo ausente após restauração: $relativo');
          }

          await database.update(
            mapa.tabela,
            {
              mapa.coluna: arquivoExiste
                  ? novoCaminho
                  : (mapa.coluna == 'assinatura_cliente' ? null : ''),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } finally {
      await database.close();
    }
  }

  Future<void> _restaurarArquivosDoBackup({
    required Directory raizConteudo,
    required Directory pastaDocumentos,
    required List<String> warnings,
  }) async {
    final pastaArquivos = Directory(path.join(raizConteudo.path, 'files'));

    if (!await pastaArquivos.exists()) {
      warnings.add('Nenhuma pasta de arquivos foi encontrada no backup.');
      return;
    }

    await for (final entidade in pastaArquivos.list(recursive: true)) {
      if (entidade is! File) {
        continue;
      }

      final relativo = path.relative(entidade.path, from: pastaArquivos.path);
      final destino = File(path.join(pastaDocumentos.path, relativo));
      await destino.parent.create(recursive: true);
      await entidade.copy(destino.path);
    }
  }

  Future<void> _substituirBanco({
    required File origem,
    required File destino,
  }) async {
    if (!await origem.exists()) {
      throw const BackupException('O banco do backup não foi encontrado.');
    }

    final destinoWal = File('${destino.path}-wal');
    final destinoShm = File('${destino.path}-shm');

    if (await destino.exists()) {
      await destino.delete();
    }

    if (await destinoWal.exists()) {
      await destinoWal.delete();
    }

    if (await destinoShm.exists()) {
      await destinoShm.delete();
    }

    await destino.parent.create(recursive: true);
    await origem.copy(destino.path);
  }

  Future<_ArquivoValidado> _validarArquivoBackup(File arquivoBackup) async {
    final bytes = await arquivoBackup.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final nomes = <String>[];
    for (final arquivo in archive.files) {
      if (arquivo.isFile) {
        nomes.add(arquivo.name);
      }
    }

    if (nomes.isEmpty) {
      throw const BackupException('O arquivo selecionado está vazio.');
    }

    final metadataArquivo = nomes.cast<String?>().firstWhere(
      (nome) => nome != null && nome.endsWith('metadata.json'),
      orElse: () => null,
    );

    if (metadataArquivo == null) {
      throw const BackupException('O backup não contém metadados válidos.');
    }

    final metadataBytes = _extrairArquivoDoZip(archive, metadataArquivo);
    if (metadataBytes == null) {
      throw const BackupException(
        'Não foi possível ler os metadados do backup.',
      );
    }

    final metadata = _lerMetadadosDeBytes(metadataBytes);
    final versaoBanco = (metadata['versao_banco'] as num?)?.toInt() ?? -1;

    return _ArquivoValidado(
      metadados: metadata,
      versaoBanco: versaoBanco,
      arquivos: nomes,
    );
  }

  List<int>? _extrairArquivoDoZip(Archive archive, String nomeArquivo) {
    for (final arquivo in archive.files) {
      if (arquivo.isFile && arquivo.name.endsWith(nomeArquivo)) {
        final content = arquivo.content;

        if (content is List<int>) {
          return content;
        }

        if (content is Uint8List) {
          return content;
        }
      }
    }

    return null;
  }

  Map<String, Object?> _lerMetadadosDeBytes(List<int> bytes) {
    final texto = utf8.decode(bytes);
    final mapa = jsonDecode(texto);

    if (mapa is! Map<String, dynamic>) {
      throw const BackupException('O arquivo de metadados é inválido.');
    }

    return mapa;
  }

  void _validarMetadados(Map<String, Object?> metadata) {
    final app = metadata['app']?.toString().trim() ?? '';
    final formato = metadata['formato_backup']?.toString().trim() ?? '';
    final identificador =
        metadata['identificador_formato']?.toString().trim() ?? '';

    if (app != _appNome) {
      throw const BackupException(
        'Este arquivo não pertence ao Imperium Detailing.',
      );
    }

    if (formato != 'zip' || identificador != _identificadorFormato) {
      throw const BackupException(
        'O arquivo não é um backup válido do aplicativo.',
      );
    }
  }

  Future<void> _extrairZipSeguro(File arquivoZip, Directory destino) async {
    final bytes = await arquivoZip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final raiz = path.normalize(destino.path);

    for (final arquivo in archive.files) {
      if (!arquivo.isFile) {
        continue;
      }

      final caminhoDestino = path.normalize(
        path.join(destino.path, arquivo.name),
      );
      if (!_caminhoDentroDaRaiz(raiz, caminhoDestino)) {
        throw const BackupException(
          'O backup contém caminhos inválidos e não pode ser extraído.',
        );
      }

      final saida = File(caminhoDestino);
      await saida.parent.create(recursive: true);
      await saida.writeAsBytes(arquivo.content as List<int>, flush: true);
    }
  }

  Future<Directory?> _localizarRaizConteudo(Directory raiz) async {
    await for (final entidade in raiz.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entidade is File && path.basename(entidade.path) == 'metadata.json') {
        return entidade.parent;
      }
    }

    return null;
  }

  Future<File?> _encontrarArquivoPorNome(Directory raiz, String nome) async {
    await for (final entidade in raiz.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entidade is File && path.basename(entidade.path) == nome) {
        return entidade;
      }
    }

    return null;
  }

  Future<List<_ArquivoPersistente>> _listarArquivosPersistentes({
    required Database database,
    required Configuracao configuracao,
    required Directory pastaDocumentos,
  }) async {
    final caminhos = <String>{};

    void adicionar(String? caminho) {
      final texto = caminho?.trim() ?? '';
      if (texto.isNotEmpty) {
        caminhos.add(texto);
      }
    }

    adicionar(configuracao.caminhoLogo);
    adicionar(configuracao.caminhoAssinaturaEmpresa);

    final tabelas = await Future.wait<List<Map<String, Object?>>>([
      database.rawQuery(
        'SELECT caminho_antes, caminho_depois FROM fotos_servico',
      ),
      database.rawQuery('SELECT caminho FROM ordem_servico_fotos'),
      database.rawQuery('SELECT foto_avaria FROM ordem_servico_checklist'),
      database.rawQuery('SELECT assinatura_cliente FROM ordens_servico'),
    ]);

    for (final linha in tabelas[0]) {
      adicionar(linha['caminho_antes']?.toString());
      adicionar(linha['caminho_depois']?.toString());
    }

    for (final linha in tabelas[1]) {
      adicionar(linha['caminho']?.toString());
    }

    for (final linha in tabelas[2]) {
      adicionar(linha['foto_avaria']?.toString());
    }

    for (final linha in tabelas[3]) {
      adicionar(linha['assinatura_cliente']?.toString());
    }

    final arquivos = <_ArquivoPersistente>[];
    for (final caminho in caminhos) {
      final relativo = _extrairRelativo(caminho, pastaDocumentos.path);
      if (relativo == null) {
        continue;
      }

      arquivos.add(
        _ArquivoPersistente(caminhoOriginal: caminho, relativo: relativo),
      );
    }

    return arquivos;
  }

  Future<String> _obterCaminhoBanco() async {
    final pastaBanco = await getDatabasesPath();
    return path.join(pastaBanco, 'imperium_detailing.db');
  }

  Future<void> _reabrirBanco() async {
    await _appDatabase.database;
  }

  bool _caminhoDentroDaRaiz(String raiz, String candidato) {
    final raizNormalizada = path.normalize(raiz);
    final candidatoNormalizado = path.normalize(candidato);

    return candidatoNormalizado == raizNormalizada ||
        candidatoNormalizado.startsWith('$raizNormalizada${path.separator}');
  }

  String? _extrairRelativo(String caminho, String pastaDocumentos) {
    final caminhoNormalizado = caminho.replaceAll('\\', '/');
    final documentosNormalizado = pastaDocumentos.replaceAll('\\', '/');

    if (caminhoNormalizado.startsWith('$documentosNormalizado/')) {
      return caminhoNormalizado.substring(documentosNormalizado.length + 1);
    }

    final marcadores = [
      '/fotos_servicos/',
      '/logos/',
      '/assinaturas_empresa/',
      '/assinaturas_ordens_servico/',
      '/ordens_servico/',
    ];

    for (final marcador in marcadores) {
      final indice = caminhoNormalizado.indexOf(marcador);
      if (indice >= 0) {
        return caminhoNormalizado.substring(indice + 1);
      }
    }

    return null;
  }

  String _formatarDataArquivo(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    final segundo = data.second.toString().padLeft(2, '0');

    final buffer = StringBuffer()
      ..write(ano)
      ..write(mes)
      ..write(dia)
      ..write('_')
      ..write(hora)
      ..write(minuto)
      ..write(segundo);

    return buffer.toString();
  }
}

class _ArquivoPersistente {
  const _ArquivoPersistente({
    required this.caminhoOriginal,
    required this.relativo,
  });

  final String caminhoOriginal;
  final String relativo;
}

class _ArquivoValidado {
  const _ArquivoValidado({
    required this.metadados,
    required this.versaoBanco,
    required this.arquivos,
  });

  final Map<String, Object?> metadados;
  final int versaoBanco;
  final List<String> arquivos;
}

class _MapaBackup {
  const _MapaBackup({
    required this.tabela,
    required this.coluna,
    required this.seletor,
  });

  final String tabela;
  final String coluna;
  final String seletor;
}
