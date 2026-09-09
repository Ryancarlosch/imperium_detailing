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

  @override
  String toString() => mensagem;
}

typedef DfeBackendInvoker =
    Future<Map<String, dynamic>> Function(String chaveAcesso);
typedef DfeXmlImporter = Future<NotaFiscalEntrada> Function(String xml);

class NotaFiscalDfeBackendService {
  NotaFiscalDfeBackendService({
    NotaFiscalEntradaRepository? repository,
    DfeBackendInvoker? invoker,
    DfeXmlImporter? xmlImporter,
  }) : _repository = repository ?? NotaFiscalEntradaRepository(),
       // Mantemos os nomes públicos `invoker` e `xmlImporter` para os testes
       // e para futuras integrações. Usar initializing formal aqui mudaria
       // esses parâmetros para nomes privados.
       // ignore: prefer_initializing_formals
       _invoker = invoker,
       // ignore: prefer_initializing_formals
       _xmlImporter = xmlImporter;

  final NotaFiscalEntradaRepository _repository;
  final DfeBackendInvoker? _invoker;
  final DfeXmlImporter? _xmlImporter;

  Future<NotaFiscalEntrada> consultarEImportar(String chaveAcesso) async {
    final chave = ChaveFiscalService.normalizar(chaveAcesso);
    final metadados = ChaveFiscalService.metadados(chave);
    if (metadados.modelo != 55) {
      throw const DfeBackendException(
        'unsupported_model',
        'A consulta DF-e estruturada desta etapa é destinada a NF-e modelo 55.',
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
    if (importer != null) return importer(xml);
    return NotaFiscalEntradaXmlService(
      repository: _repository,
    ).importarXml(xml);
  }

  Future<Map<String, dynamic>> _invocarSupabase(String chave) async {
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
        body: {'chave': chave},
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
