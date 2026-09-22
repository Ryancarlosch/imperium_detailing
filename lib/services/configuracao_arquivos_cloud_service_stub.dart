class ConfiguracaoArquivosCloudService {
  ConfiguracaoArquivosCloudService._();

  static final ConfiguracaoArquivosCloudService instance =
      ConfiguracaoArquivosCloudService._();

  static const String bucket = 'imperium-configuracoes-arquivos';

  Future<void> garantirEstruturaLocal() async {}

  Future<void> sincronizar(String empresaId) async {}

  Future<bool> possuiConflitosPendentes(String empresaId) async => false;

  Future<List<Map<String, Object?>>> listarConflitosPendentes({
    required String empresaId,
  }) async {
    return const <Map<String, Object?>>[];
  }

  Future<Map<String, Object?>> diagnosticar(String empresaId) async {
    return <String, Object?>{
      'empresa_id': empresaId,
      'bucket': bucket,
      'arquivos_mapeados': 0,
      'mapas': const <Map<String, Object?>>[],
      'conflitos_pendentes': 0,
      'plataforma': 'web',
      'gerenciado_diretamente_pelo_storage': true,
    };
  }

  Future<void> resolverUsandoNuvem(int conflitoId) async {
    throw UnsupportedError(
      'Resolução local de arquivo não se aplica ao navegador.',
    );
  }

  Future<void> resolverUsandoLocal(int conflitoId) async {
    throw UnsupportedError(
      'Resolução local de arquivo não se aplica ao navegador.',
    );
  }
}
