// ignore_for_file: prefer_initializing_formals

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import 'chave_fiscal_service.dart';
import 'nota_fiscal_entrada_xml_service.dart';
import 'supabase_bootstrap.dart';

class DfeBackendException implements Exception {
  const DfeBackendException(this.codigo, this.mensagem);

  final String codigo;
  final String mensagem;

  bool get pendente => const {
    'provider_not_configured',
    'document_not_found',
    'document_not_complete',
    'provider_access_denied',
    'supabase_unavailable',
    'authentication_required',
  }.contains(codigo);

  @override
  String toString() => mensagem;
}

class DfeBackendStatus {
  const DfeBackendStatus({
    required this.disponivel,
    required this.autenticado,
    required this.provedor,
    required this.provedorConfigurado,
    required this.cnpjConfigurado,
    required this.manifestacaoAutomatica,
    required this.mensagem,
  });

  final bool disponivel;
  final bool autenticado;
  final String provedor;
  final bool provedorConfigurado;
  final bool cnpjConfigurado;
  final bool manifestacaoAutomatica;
  final String mensagem;

  factory DfeBackendStatus.fromMap(Map<String, dynamic> map) {
    return DfeBackendStatus(
      disponivel: map['ok'] == true,
      autenticado: map['authenticated'] == true,
      provedor: (map['provider'] ?? '').toString(),
      provedorConfigurado: map['provider_configured'] == true,
      cnpjConfigurado: map['cnpj_configured'] == true,
      manifestacaoAutomatica: map['auto_manifestacao'] == true,
      mensagem: (map['message'] ?? '').toString(),
    );
  }
}

typedef DfeBackendInvoker =
    Future<Map<String, dynamic>> Function(String chaveAcesso);
typedef DfeStatusInvoker = Future<Map<String, dynamic>> Function();
typedef DfeXmlImporter = Future<NotaFiscalEntrada> Function(String xml);

class NotaFiscalDfeBackendService {
  NotaFiscalDfeBackendService({
    NotaFiscalEntradaRepository? repository,
    DfeBackendInvoker? invoker,
    DfeStatusInvoker? statusInvoker,
    DfeXmlImporter? xmlImporter,
  }) : _repository = repository ?? NotaFiscalEntradaRepository(),
       _invoker = invoker,
       _statusInvoker = statusInvoker,
       _xmlImporter = xmlImporter;

  final NotaFiscalEntradaRepository _repository;
  final DfeBackendInvoker? _invoker;
  final DfeStatusInvoker? _statusInvoker;
  final DfeXmlImporter? _xmlImporter;

  Future<DfeBackendStatus> diagnosticar() async {
    try {
      final resposta = await (_statusInvoker ?? _invocarStatusSupabase)();
      return DfeBackendStatus.fromMap(resposta);
    } on DfeBackendException catch (error) {
      return DfeBackendStatus(
        disponivel: false,
        autenticado: false,
        provedor: '',
        provedorConfigurado: false,
        cnpjConfigurado: false,
        manifestacaoAutomatica: false,
        mensagem: error.mensagem,
      );
    }
  }

  Future<NotaFiscalEntrada> consultarEImportar(String chaveAcesso) async {
    final chave = ChaveFiscalService.normalizar(chaveAcesso);
    final metadados = ChaveFiscalService.metadados(chave);
    if (metadados.modelo != 55) {
      throw const DfeBackendException(
        'unsupported_model',
        'A consulta DF-e estruturada é destinada a NF-e modelo 55.',
      );
    }

    final resposta = await (_invoker ?? _invocarSupabase)(chave);
    if (resposta['ok'] != true) {
      throw DfeBackendException(
        (resposta['code'] ?? 'backend_error').toString(),
        (resposta['message'] ?? 'O backend fiscal não retornou a NF-e.')
            .toString(),
      );
    }

    final xml = (resposta['xml'] ?? '').toString().trim();
    if (xml.isEmpty) {
      throw const DfeBackendException(
        'empty_xml',
        'O backend fiscal respondeu sem o XML da NF-e.',
      );
    }

    final importer = _xmlImporter;
    final nota = importer != null
        ? await importer(xml)
        : await NotaFiscalEntradaXmlService(
            repository: _repository,
          ).importarXml(xml);

    if (nota.chaveAcesso != chave) {
      throw const DfeBackendException(
        'key_mismatch',
        'O XML devolvido pelo backend não corresponde à chave solicitada.',
      );
    }
    return nota;
  }

  Future<Map<String, dynamic>> _invocarStatusSupabase() =>
      _invocarFunction({'acao': 'status'});

  Future<Map<String, dynamic>> _invocarSupabase(String chave) =>
      _invocarFunction({'chave': chave});

  Future<Map<String, dynamic>> _invocarFunction(
    Map<String, dynamic> body,
  ) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw const DfeBackendException(
        'supabase_unavailable',
        'A conexão em nuvem do Imperium não está disponível.',
      );
    }

    final sessao = client.auth.currentSession;
    if (sessao == null) {
      throw const DfeBackendException(
        'authentication_required',
        'Entre na sua conta do Imperium para usar a consulta DF-e.',
      );
    }

    try {
      final response = await client.functions.invoke(
        'imperium-fiscal-dfe',
        body: body,
        headers: {'Authorization': 'Bearer ${sessao.accessToken}'},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const DfeBackendException(
        'invalid_backend_payload',
        'O backend fiscal retornou uma resposta inesperada.',
      );
    } on FunctionsHttpException catch (error) {
      final details = error.details;
      if (details is Map) {
        final map = Map<String, dynamic>.from(details);
        throw DfeBackendException(
          (map['code'] ?? 'backend_http_error').toString(),
          (map['message'] ?? 'A consulta DF-e não pôde ser concluída.')
              .toString(),
        );
      }
      throw DfeBackendException(
        'backend_http_error',
        'A consulta DF-e respondeu HTTP ${error.status}.',
      );
    } on FunctionsRelayException catch (error) {
      throw DfeBackendException(
        'backend_relay_error',
        'Falha na comunicação com o backend fiscal: ${error.reasonPhrase ?? error.toString()}',
      );
    } on FunctionsFetchException catch (error) {
      throw DfeBackendException(
        'backend_network_error',
        'Não foi possível acessar o backend fiscal: ${error.reasonPhrase ?? error.toString()}',
      );
    }
  }
}
