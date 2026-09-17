import 'operacional_cloud_v2_service.dart';

/// Fachada estável para conflitos do núcleo operacional.
///
/// A proteção usada em produção já vive em [OperacionalCloudV2Service] e é
/// chamada pelo [SyncMotorService] antes do upload de Clientes, Veículos e
/// Agenda. Esta classe evita manter um segundo detector concorrente para a
/// mesma tabela de conflitos.
class OperacionalConflitoService {
  OperacionalConflitoService._({OperacionalCloudV2Service? delegate})
    : _delegate = delegate ?? OperacionalCloudV2Service.instance;

  static final OperacionalConflitoService instance =
      OperacionalConflitoService._();

  final OperacionalCloudV2Service _delegate;

  Future<void> garantirEstruturaLocal() => _delegate.garantirEstruturaLocal();

  /// Executa a mesma reconciliação usada pelo fluxo real de sincronização.
  Future<bool> prepararUpload(String empresaId) =>
      _delegate.prepararUpload(empresaId);

  /// Reconciliará o módulo e devolve quantos conflitos continuam pendentes.
  Future<int> detectar(String empresaId) async {
    final tenant = empresaId.trim();
    if (tenant.isEmpty) return 0;

    await _delegate.prepararUpload(tenant);
    final conflitos = await _delegate.listarConflitosPendentes(
      empresaId: tenant,
    );
    return conflitos.length;
  }

  Future<bool> possuiConflitosPendentes(String empresaId) =>
      _delegate.possuiConflitosPendentes(empresaId);

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    required String empresaId,
  }) => _delegate.listarConflitosPendentes(empresaId: empresaId);

  Future<Map<String, Object?>> diagnosticar(String empresaId) =>
      _delegate.diagnosticar(empresaId);

  Future<void> resolverUsandoLocal(int conflitoId) =>
      _delegate.resolverUsandoLocal(conflitoId);

  Future<void> resolverUsandoNuvem(int conflitoId) =>
      _delegate.resolverUsandoNuvem(conflitoId);
}
