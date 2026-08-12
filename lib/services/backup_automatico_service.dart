import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';
import 'google_drive_backup_service.dart';

class BackupAutomaticoConfiguracao {
  const BackupAutomaticoConfiguracao({
    required this.ativo,
    required this.intervaloHoras,
    required this.manterCopias,
    this.ultimoSucessoEm,
    this.ultimaTentativaEm,
    this.ultimoArquivo,
    this.ultimoErro,
  });

  final bool ativo;
  final int intervaloHoras;
  final int manterCopias;
  final String? ultimoSucessoEm;
  final String? ultimaTentativaEm;
  final String? ultimoArquivo;
  final String? ultimoErro;

  factory BackupAutomaticoConfiguracao.padrao() {
    return const BackupAutomaticoConfiguracao(
      ativo: true,
      intervaloHoras: 24,
      manterCopias: 7,
    );
  }

  factory BackupAutomaticoConfiguracao.fromMap(Map<String, dynamic> map) {
    return BackupAutomaticoConfiguracao(
      ativo: map['ativo'] != false,
      intervaloHoras: _intSeguro(
        map['intervalo_horas'],
        padrao: 24,
        minimo: 6,
        maximo: 24 * 30,
      ),
      manterCopias: _intSeguro(
        map['manter_copias'],
        padrao: 7,
        minimo: 1,
        maximo: 30,
      ),
      ultimoSucessoEm: _textoNulo(map['ultimo_sucesso_em']),
      ultimaTentativaEm: _textoNulo(map['ultima_tentativa_em']),
      ultimoArquivo: _textoNulo(map['ultimo_arquivo']),
      ultimoErro: _textoNulo(map['ultimo_erro']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ativo': ativo,
      'intervalo_horas': intervaloHoras,
      'manter_copias': manterCopias,
      'ultimo_sucesso_em': ultimoSucessoEm,
      'ultima_tentativa_em': ultimaTentativaEm,
      'ultimo_arquivo': ultimoArquivo,
      'ultimo_erro': ultimoErro,
    };
  }

  BackupAutomaticoConfiguracao copyWith({
    bool? ativo,
    int? intervaloHoras,
    int? manterCopias,
    String? ultimoSucessoEm,
    bool removerUltimoSucesso = false,
    String? ultimaTentativaEm,
    bool removerUltimaTentativa = false,
    String? ultimoArquivo,
    bool removerUltimoArquivo = false,
    String? ultimoErro,
    bool removerUltimoErro = false,
  }) {
    return BackupAutomaticoConfiguracao(
      ativo: ativo ?? this.ativo,
      intervaloHoras: intervaloHoras ?? this.intervaloHoras,
      manterCopias: manterCopias ?? this.manterCopias,
      ultimoSucessoEm: removerUltimoSucesso
          ? null
          : ultimoSucessoEm ?? this.ultimoSucessoEm,
      ultimaTentativaEm: removerUltimaTentativa
          ? null
          : ultimaTentativaEm ?? this.ultimaTentativaEm,
      ultimoArquivo: removerUltimoArquivo
          ? null
          : ultimoArquivo ?? this.ultimoArquivo,
      ultimoErro: removerUltimoErro ? null : ultimoErro ?? this.ultimoErro,
    );
  }

  static int _intSeguro(
    dynamic valor, {
    required int padrao,
    required int minimo,
    required int maximo,
  }) {
    final numero = valor is num
        ? valor.toInt()
        : int.tryParse(valor?.toString().trim() ?? '');

    if (numero == null) return padrao;
    return numero.clamp(minimo, maximo);
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}

class BackupAutomaticoResultado {
  const BackupAutomaticoResultado({
    required this.executado,
    required this.sucesso,
    required this.mensagem,
    this.resumo,
    this.drive,
  });

  final bool executado;
  final bool sucesso;
  final String mensagem;
  final BackupResumo? resumo;
  final GoogleDriveUploadResultado? drive;
}

class BackupAutomaticoService {
  BackupAutomaticoService._();

  static final BackupAutomaticoService instance = BackupAutomaticoService._();

  static const String _nomeConfiguracao = 'imperium_backup_automatico.json';
  static const String _prefixoAutomatico = 'imperium_backup_auto_';

  bool _executando = false;

  Future<BackupAutomaticoConfiguracao> carregarConfiguracao() async {
    final arquivo = await _arquivoConfiguracao();

    if (!await arquivo.exists()) {
      final padrao = BackupAutomaticoConfiguracao.padrao();
      await _salvarInterno(padrao);
      return padrao;
    }

    try {
      final conteudo = await arquivo.readAsString();
      final mapa = jsonDecode(conteudo);

      if (mapa is! Map) {
        throw const FormatException('Configuração inválida.');
      }

      return BackupAutomaticoConfiguracao.fromMap(
        Map<String, dynamic>.from(mapa),
      );
    } catch (_) {
      final padrao = BackupAutomaticoConfiguracao.padrao();
      await _salvarInterno(padrao);
      return padrao;
    }
  }

  Future<BackupAutomaticoConfiguracao> salvarConfiguracao(
    BackupAutomaticoConfiguracao configuracao,
  ) async {
    final segura = configuracao.copyWith(
      intervaloHoras: configuracao.intervaloHoras.clamp(6, 24 * 30),
      manterCopias: configuracao.manterCopias.clamp(1, 30),
    );

    await _salvarInterno(segura);
    return segura;
  }

  Future<BackupAutomaticoResultado> verificarEExecutar({
    bool forcar = false,
  }) async {
    if (_executando) {
      return const BackupAutomaticoResultado(
        executado: false,
        sucesso: true,
        mensagem: 'Já existe um backup automático em andamento.',
      );
    }

    _executando = true;

    try {
      var configuracao = await carregarConfiguracao();

      if (!configuracao.ativo && !forcar) {
        return const BackupAutomaticoResultado(
          executado: false,
          sucesso: true,
          mensagem: 'Backup automático desativado.',
        );
      }

      if (!forcar && !_estaVencido(configuracao)) {
        return const BackupAutomaticoResultado(
          executado: false,
          sucesso: true,
          mensagem: 'Backup automático ainda está em dia.',
        );
      }

      final tentativa = DateTime.now();

      configuracao = configuracao.copyWith(
        ultimaTentativaEm: tentativa.toIso8601String(),
        removerUltimoErro: true,
      );
      await _salvarInterno(configuracao);

      try {
        final resumo = await BackupService.instance.criarBackupAutomatico();

        await _limparCopiasAntigas(
          resumo.caminhoArquivo,
          manter: configuracao.manterCopias,
        );

        GoogleDriveUploadResultado? drive;

        try {
          drive = await GoogleDriveBackupService.instance.enviarSeConectado(
            resumo.caminhoArquivo,
            manterCopias: configuracao.manterCopias,
          );
        } catch (erroDrive) {
          await GoogleDriveBackupService.instance.registrarFalha(erroDrive);
        }

        final atualizada = configuracao.copyWith(
          ultimoSucessoEm: resumo.dataCriacao.toIso8601String(),
          ultimaTentativaEm: tentativa.toIso8601String(),
          ultimoArquivo: resumo.caminhoArquivo,
          removerUltimoErro: true,
        );

        await _salvarInterno(atualizada);

        final mensagem = drive?.executado == true && drive?.sucesso == true
            ? 'Backup automático local e no Google Drive criado com sucesso.'
            : 'Backup automático local criado com sucesso.';

        return BackupAutomaticoResultado(
          executado: true,
          sucesso: true,
          mensagem: mensagem,
          resumo: resumo,
          drive: drive,
        );
      } catch (erro) {
        final mensagem = _textoErro(erro);

        await _salvarInterno(
          configuracao.copyWith(
            ultimaTentativaEm: tentativa.toIso8601String(),
            ultimoErro: mensagem,
          ),
        );

        return BackupAutomaticoResultado(
          executado: true,
          sucesso: false,
          mensagem: mensagem,
        );
      }
    } catch (erro) {
      return BackupAutomaticoResultado(
        executado: false,
        sucesso: false,
        mensagem: _textoErro(erro),
      );
    } finally {
      _executando = false;
    }
  }

  bool _estaVencido(BackupAutomaticoConfiguracao configuracao) {
    final ultimoTexto = configuracao.ultimoSucessoEm?.trim() ?? '';
    final ultimo = DateTime.tryParse(ultimoTexto);

    if (ultimo == null) {
      return true;
    }

    final limite = ultimo.add(Duration(hours: configuracao.intervaloHoras));
    return !DateTime.now().isBefore(limite);
  }

  Future<void> _limparCopiasAntigas(
    String caminhoBackupAtual, {
    required int manter,
  }) async {
    try {
      final pasta = File(caminhoBackupAtual).parent;

      if (!await pasta.exists()) {
        return;
      }

      final arquivos = <File>[];

      await for (final entidade in pasta.list(followLinks: false)) {
        if (entidade is! File) continue;

        final nome = entidade.uri.pathSegments.isEmpty
            ? ''
            : entidade.uri.pathSegments.last;

        if (nome.startsWith(_prefixoAutomatico) &&
            nome.toLowerCase().endsWith('.zip')) {
          arquivos.add(entidade);
        }
      }

      final comData = <({File arquivo, DateTime data})>[];

      for (final arquivo in arquivos) {
        DateTime data;

        try {
          data = (await arquivo.stat()).modified;
        } catch (_) {
          data = DateTime.fromMillisecondsSinceEpoch(0);
        }

        comData.add((arquivo: arquivo, data: data));
      }

      comData.sort((a, b) => b.data.compareTo(a.data));

      for (var i = manter; i < comData.length; i++) {
        try {
          await comData[i].arquivo.delete();
        } catch (_) {
          // Limpeza best-effort.
        }
      }
    } catch (_) {
      // Retenção não pode transformar um backup válido em falha.
    }
  }

  Future<File> _arquivoConfiguracao() async {
    final documentos = await getApplicationDocumentsDirectory();

    return File(
      '${documentos.path}${Platform.pathSeparator}$_nomeConfiguracao',
    );
  }

  Future<void> _salvarInterno(BackupAutomaticoConfiguracao configuracao) async {
    final arquivo = await _arquivoConfiguracao();
    await arquivo.parent.create(recursive: true);

    final temporario = File('${arquivo.path}.tmp');

    await temporario.writeAsString(
      const JsonEncoder.withIndent('  ').convert(configuracao.toMap()),
      flush: true,
    );

    if (await arquivo.exists()) {
      await arquivo.delete();
    }

    await temporario.rename(arquivo.path);
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'BackupException: ',
      'Bad state: ',
      'Invalid argument(s): ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Falha desconhecida no backup automático.' : texto;
  }
}
