import 'package:flutter/material.dart';

import 'web_operacional_shell.dart';

class WebWorkspaceShell extends StatelessWidget {
  const WebWorkspaceShell({
    super.key,
    required this.usuarioEmail,
    required this.empresas,
    required this.empresaAtualId,
    required this.onTrocarEmpresa,
    required this.onSair,
  });

  final String usuarioEmail;
  final List<Map<String, dynamic>> empresas;
  final String empresaAtualId;
  final Future<void> Function(String empresaId) onTrocarEmpresa;
  final Future<void> Function() onSair;

  @override
  Widget build(BuildContext context) {
    return WebOperacionalShell(
      key: ValueKey('workspace-$empresaAtualId'),
      usuarioEmail: usuarioEmail,
      empresas: empresas,
      empresaAtualId: empresaAtualId,
      onTrocarEmpresa: onTrocarEmpresa,
      onSair: onSair,
    );
  }
}
