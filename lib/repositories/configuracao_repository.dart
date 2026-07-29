import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/configuracao.dart';


class ConfiguracaoRepository {
  final AppDatabase _appDatabase = AppDatabase.instance;

  Future<Configuracao> obterConfiguracao() async {
    final database = await _appDatabase.database;

    final resultado = await database.query(
      'configuracoes',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (resultado.isNotEmpty) {
      return Configuracao.fromMap(
        resultado.first,
      );
    }

    final configuracaoPadrao =
    Configuracao.padrao();

    await salvarConfiguracao(
      configuracaoPadrao,
    );

    return configuracaoPadrao;
  }

  Future<void> salvarConfiguracao(
      Configuracao configuracao,
      ) async {
    final database = await _appDatabase.database;

    await database.insert(
      'configuracoes',
      configuracao.toMapParaSalvar(),
      conflictAlgorithm:
      ConflictAlgorithm.replace,
    );
  }

  Future<void> atualizarDadosEmpresa({
    required String nomeFantasia,
    required String razaoSocial,
    required String cnpj,
    required String inscricaoEstadual,
    required String telefone,
    required String whatsapp,
    required String email,
    required String site,
    required String instagram,
    required String endereco,
    required String numero,
    required String complemento,
    required String bairro,
    required String cidade,
    required String estado,
    required String cep,
  }) async {
    final configuracao =
    await obterConfiguracao();

    final atualizada = configuracao.copyWith(
      nomeFantasia: nomeFantasia,
      razaoSocial: razaoSocial,
      cnpj: cnpj,
      inscricaoEstadual:
      inscricaoEstadual,
      telefone: telefone,
      whatsapp: whatsapp,
      email: email,
      site: site,
      instagram: instagram,
      endereco: endereco,
      numero: numero,
      complemento: complemento,
      bairro: bairro,
      cidade: cidade,
      estado: estado,
      cep: cep,
    );

    await salvarConfiguracao(atualizada);
  }

  Future<void> atualizarLogo(
      String? caminhoLogo,
      ) async {
    final configuracao =
    await obterConfiguracao();

    final atualizada = caminhoLogo == null ||
        caminhoLogo.trim().isEmpty
        ? configuracao.copyWith(
      removerLogo: true,
    )
        : configuracao.copyWith(
      caminhoLogo: caminhoLogo,
    );

    await salvarConfiguracao(atualizada);
  }

  Future<void> atualizarAparencia({
    required String nomeAplicativo,
    required int corPrincipal,
    required int corSecundaria,
    required String tema,
  }) async {
    final configuracao =
    await obterConfiguracao();

    final atualizada = configuracao.copyWith(
      nomeAplicativo: nomeAplicativo,
      corPrincipal: corPrincipal,
      corSecundaria: corSecundaria,
      tema: tema,
    );

    await salvarConfiguracao(atualizada);
  }

  Future<void> atualizarDocumentos({
    required int validadeOrcamentoDias,
    required String rodapeDocumentos,
    required String termosOrcamento,
    required String termosOrdemServico,
    required String observacaoPadrao,
    required String mensagemAgradecimento,
  }) async {
    final configuracao =
    await obterConfiguracao();

    final atualizada = configuracao.copyWith(
      validadeOrcamentoDias:
      validadeOrcamentoDias,
      rodapeDocumentos:
      rodapeDocumentos,
      termosOrcamento:
      termosOrcamento,
      termosOrdemServico:
      termosOrdemServico,
      observacaoPadrao:
      observacaoPadrao,
      mensagemAgradecimento:
      mensagemAgradecimento,
    );

    await salvarConfiguracao(atualizada);
  }

  Future<void> atualizarMensagensWhatsApp({
    required String mensagemOrcamento,
    required String mensagemConfirmacao,
    required String mensagemEntrega,
    required String mensagemCobranca,
  }) async {
    final configuracao =
    await obterConfiguracao();

    final atualizada = configuracao.copyWith(
      mensagemOrcamento:
      mensagemOrcamento,
      mensagemConfirmacao:
      mensagemConfirmacao,
      mensagemEntrega:
      mensagemEntrega,
      mensagemCobranca:
      mensagemCobranca,
    );

    await salvarConfiguracao(atualizada);
  }

  Future<void> restaurarPadrao() async {
    final configuracaoPadrao =
    Configuracao.padrao();

    await salvarConfiguracao(
      configuracaoPadrao,
    );
  }
}