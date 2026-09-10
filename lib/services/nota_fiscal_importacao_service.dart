// ignore_for_file: prefer_initializing_formals

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import 'chave_fiscal_service.dart';
import 'nota_fiscal_consulta_publica_service.dart';
import 'nota_fiscal_dfe_backend_service.dart';
import 'nota_fiscal_entrada_xml_service.dart';

class NotaFiscalImportacaoResultado {
  const NotaFiscalImportacaoResultado({
    required this.nota,
    required this.mensagem,
    this.portalAssistidoUrl,
    this.codigo = '',
  });

  final NotaFiscalEntrada nota;
  final String mensagem;
  final Uri? portalAssistidoUrl;
  final String codigo;

  bool get processada => nota.statusImportacao == 'processada';
  bool get exigePortalAssistido => portalAssistidoUrl != null && !processada;
}

class NotaFiscalImportacaoService {
  NotaFiscalImportacaoService({
    NotaFiscalEntradaRepository? repository,
    ChaveFiscalService? chaveService,
    NotaFiscalConsultaPublicaService? consultaPublica,
    NotaFiscalDfeBackendService? dfeBackend,
    NotaFiscalEntradaXmlService? xmlService,
  }) : _repository = repository ?? NotaFiscalEntradaRepository(),
       _chaveService = chaveService,
       _consultaPublica = consultaPublica,
       _dfeBackend = dfeBackend,
       _xmlService = xmlService;

  final NotaFiscalEntradaRepository _repository;
  final ChaveFiscalService? _chaveService;
  final NotaFiscalConsultaPublicaService? _consultaPublica;
  final NotaFiscalDfeBackendService? _dfeBackend;
  final NotaFiscalEntradaXmlService? _xmlService;

  ChaveFiscalService get _chave =>
      _chaveService ?? ChaveFiscalService(repository: _repository);
  NotaFiscalConsultaPublicaService get _publica =>
      _consultaPublica ??
      NotaFiscalConsultaPublicaService(repository: _repository);
  NotaFiscalDfeBackendService get _dfe =>
      _dfeBackend ?? NotaFiscalDfeBackendService(repository: _repository);
  NotaFiscalEntradaXmlService get _xml =>
      _xmlService ?? NotaFiscalEntradaXmlService(repository: _repository);

  Future<NotaFiscalImportacaoResultado> processarConteudo(
    String conteudo, {
    required String origem,
  }) async {
    final capturada = _chave.extrair(conteudo, origem: origem);
    final meta = ChaveFiscalService.metadados(capturada.chave);
    final url = NotaFiscalConsultaPublicaService.extrairUrlConsulta(conteudo);
    final urlOficial =
        url != null &&
            NotaFiscalConsultaPublicaService.urlOficial(
              NotaFiscalConsultaPublicaService.urlSegura(url),
            )
        ? NotaFiscalConsultaPublicaService.urlSegura(url)
        : null;

    var preliminar = await _repository.registrarPreliminar(
      chaveAcesso: capturada.chave,
      origemImportacao: capturada.origem,
      importadaEm: DateTime.now().toIso8601String(),
      consultaUrl: urlOficial?.toString(),
    );
    preliminar = await _repository.atualizarIdentificacaoPreliminar(
      chaveAcesso: capturada.chave,
      modelo: meta.modelo,
      numero: meta.numero,
      serie: meta.serie,
      emitenteCnpjCpf: meta.cnpjEmitente,
    );

    if (meta.modelo == 55) {
      return _processarDfe(preliminar);
    }
    if (meta.modelo == 65 && urlOficial != null) {
      return _processarNfceQr(
        preliminar: preliminar,
        conteudo: conteudo,
        origem: origem,
        url: urlOficial,
      );
    }

    final atualizada = await _registrar(
      nota: preliminar,
      canal: 'manual',
      resultado: 'pendente',
      codigo: meta.modelo == 65 ? 'qr_url_missing' : 'unsupported_model',
      mensagem: meta.modelo == 65
          ? 'NFC-e registrada. Para obter itens e valores, leia o QR Code completo ou importe o XML.'
          : 'Documento registrado, mas o modelo não possui consulta automática configurada.',
      status: 'pendente',
    );
    return NotaFiscalImportacaoResultado(
      nota: atualizada,
      codigo: atualizada.ultimoErroCodigo,
      mensagem: atualizada.ultimoErroMensagem,
    );
  }

  Future<NotaFiscalImportacaoResultado> reprocessar(
    NotaFiscalEntrada nota,
  ) async {
    if (nota.processada) {
      return NotaFiscalImportacaoResultado(
        nota: nota,
        mensagem:
            'A nota já está processada. Use XML para atualizar dados fiscais sem duplicar a chave.',
      );
    }
    if (nota.modelo == 55) return _processarDfe(nota);
    if (nota.modelo == 65 && nota.possuiConsultaPublica) {
      final uri = Uri.tryParse(nota.consultaUrl!);
      if (uri != null && NotaFiscalConsultaPublicaService.urlOficial(uri)) {
        return _processarNfceQr(
          preliminar: nota,
          conteudo: uri.toString(),
          origem: nota.origemImportacao,
          url: uri,
        );
      }
    }

    final atualizada = await _registrar(
      nota: nota,
      canal: 'manual',
      resultado: 'pendente',
      codigo: 'source_missing',
      mensagem:
          'Não há uma fonte automática armazenada para reprocessar. Importe o XML ou leia novamente o QR Code.',
      status: 'pendente',
    );
    return NotaFiscalImportacaoResultado(
      nota: atualizada,
      codigo: 'source_missing',
      mensagem: atualizada.ultimoErroMensagem,
    );
  }

  Future<NotaFiscalEntrada> importarXml(String xml) async {
    final parsed = _xml.parsear(xml);
    try {
      final nota = await _xml.importarXml(xml);
      await _repository.registrarTentativa(
        chaveAcesso: nota.chaveAcesso,
        modelo: nota.modelo,
        canal: 'xml',
        resultado: 'sucesso',
        codigo: 'xml_imported',
        mensagem: 'XML fiscal validado e importado.',
        statusImportacao: 'processada',
      );
      return (await _repository.buscarPorId(nota.id!)) ?? nota;
    } catch (error) {
      await _repository.registrarTentativa(
        chaveAcesso: parsed.nota.chaveAcesso,
        modelo: parsed.nota.modelo,
        canal: 'xml',
        resultado: 'erro',
        codigo: 'xml_import_error',
        mensagem: error.toString(),
      );
      rethrow;
    }
  }

  Future<NotaFiscalEntrada> registrarPortalAssistidoSucesso({
    required NotaFiscalEntrada nota,
    required Uri url,
  }) async {
    await _repository.registrarTentativa(
      chaveAcesso: nota.chaveAcesso,
      modelo: nota.modelo,
      canal: 'portal_assistido',
      resultado: 'sucesso',
      codigo: 'portal_imported',
      mensagem: 'Dados exibidos no portal fiscal foram importados.',
      url: url.toString(),
      statusImportacao: 'processada',
    );
    return (await _repository.buscarPorId(nota.id!)) ?? nota;
  }

  Future<void> registrarPortalAssistidoFalha({
    required String chaveAcesso,
    required int? modelo,
    required Uri url,
    required String codigo,
    required String mensagem,
  }) async {
    await _repository.registrarTentativa(
      chaveAcesso: chaveAcesso,
      modelo: modelo,
      canal: 'portal_assistido',
      resultado: 'pendente',
      codigo: codigo,
      mensagem: mensagem,
      url: url.toString(),
      statusImportacao: 'pendente',
    );
  }

  Future<NotaFiscalImportacaoResultado> _processarDfe(
    NotaFiscalEntrada preliminar,
  ) async {
    try {
      final nota = await _dfe.consultarEImportar(preliminar.chaveAcesso);
      await _repository.registrarTentativa(
        chaveAcesso: nota.chaveAcesso,
        modelo: 55,
        canal: 'dfe',
        resultado: 'sucesso',
        codigo: 'dfe_imported',
        mensagem: 'XML completo da NF-e recebido pelo backend DF-e.',
        statusImportacao: 'processada',
      );
      final atualizada = (await _repository.buscarPorId(nota.id!)) ?? nota;
      return NotaFiscalImportacaoResultado(
        nota: atualizada,
        codigo: 'dfe_imported',
        mensagem: 'NF-e importada pelo backend DF-e.',
      );
    } on DfeBackendException catch (error) {
      final atualizada = await _registrar(
        nota: preliminar,
        canal: 'dfe',
        resultado: error.pendente ? 'pendente' : 'erro',
        codigo: error.codigo,
        mensagem: error.mensagem,
        status: error.pendente ? 'pendente' : 'erro',
      );
      return NotaFiscalImportacaoResultado(
        nota: atualizada,
        codigo: error.codigo,
        mensagem: error.mensagem,
      );
    } catch (error) {
      final atualizada = await _registrar(
        nota: preliminar,
        canal: 'dfe',
        resultado: 'erro',
        codigo: 'dfe_unexpected_error',
        mensagem: error.toString(),
        status: 'erro',
      );
      return NotaFiscalImportacaoResultado(
        nota: atualizada,
        codigo: 'dfe_unexpected_error',
        mensagem: atualizada.ultimoErroMensagem,
      );
    }
  }

  Future<NotaFiscalImportacaoResultado> _processarNfceQr({
    required NotaFiscalEntrada preliminar,
    required String conteudo,
    required String origem,
    required Uri url,
  }) async {
    try {
      final nota = await _publica.consultarEImportar(conteudo, origem: origem);
      await _repository.registrarTentativa(
        chaveAcesso: nota.chaveAcesso,
        modelo: 65,
        canal: 'qr_direto',
        resultado: 'sucesso',
        codigo: 'qr_imported',
        mensagem: 'NFC-e importada pela consulta pública.',
        url: url.toString(),
        statusImportacao: 'processada',
      );
      final atualizada = (await _repository.buscarPorId(nota.id!)) ?? nota;
      return NotaFiscalImportacaoResultado(
        nota: atualizada,
        codigo: 'qr_imported',
        mensagem: 'NFC-e importada pela consulta pública.',
      );
    } on ConsultaPublicaFiscalException catch (error) {
      final atualizada = await _registrar(
        nota: preliminar,
        canal: 'qr_direto',
        resultado: 'pendente',
        codigo: error.codigo,
        mensagem: error.mensagem,
        status: 'pendente',
        url: url.toString(),
      );
      return NotaFiscalImportacaoResultado(
        nota: atualizada,
        portalAssistidoUrl: url,
        codigo: error.codigo,
        mensagem: error.mensagem,
      );
    } catch (error) {
      final atualizada = await _registrar(
        nota: preliminar,
        canal: 'qr_direto',
        resultado: 'pendente',
        codigo: 'public_query_error',
        mensagem: error.toString(),
        status: 'pendente',
        url: url.toString(),
      );
      return NotaFiscalImportacaoResultado(
        nota: atualizada,
        portalAssistidoUrl: url,
        codigo: 'public_query_error',
        mensagem: atualizada.ultimoErroMensagem,
      );
    }
  }

  Future<NotaFiscalEntrada> _registrar({
    required NotaFiscalEntrada nota,
    required String canal,
    required String resultado,
    required String codigo,
    required String mensagem,
    required String status,
    String? url,
  }) async {
    return await _repository.registrarTentativa(
          chaveAcesso: nota.chaveAcesso,
          modelo: nota.modelo,
          canal: canal,
          resultado: resultado,
          codigo: codigo,
          mensagem: mensagem,
          url: url,
          statusImportacao: status,
        ) ??
        nota;
  }
}
