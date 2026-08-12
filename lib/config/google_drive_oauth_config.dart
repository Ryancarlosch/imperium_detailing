class GoogleDriveOAuthConfig {
  const GoogleDriveOAuthConfig._();

  /// Client ID do tipo "Aplicativo da Web" criado no Google Cloud.
  ///
  /// O app compila normalmente enquanto este valor estiver vazio/placeholder.
  /// Depois da configuração no Google Cloud, substitua somente esta constante.
  static const String serverClientId =
      '451359395067-bchshovlm2fo2ihe5ir1ecpmg1e2abem.apps.googleusercontent.com';

  static bool get configurado {
    final valor = serverClientId.trim();

    return valor.isNotEmpty &&
        valor.endsWith('.apps.googleusercontent.com') &&
        !valor.startsWith('COLE_AQUI_');
  }
}
