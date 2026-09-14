import 'package:flutter/material.dart';

import 'imperium_web_theme.dart';
import 'web_contas_financeiras_page.dart';
import 'web_dashboard_gerencial_page.dart';
import 'web_dre_page.dart';
import 'web_operacional_shell.dart';
import 'web_ponto_page.dart';
import 'web_relatorios_page.dart';

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

  String get _nomeEmpresaAtual {
    for (final empresa in empresas) {
      if ('${empresa['empresa_id']}' == empresaAtualId) {
        final nome = (empresa['nome'] ?? '').toString().trim();
        if (nome.isNotEmpty) return nome;
      }
    }
    return 'Empresa';
  }

  void _abrir(BuildContext context, Widget pagina) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => pagina));
  }

  void _abrirOperacao(BuildContext context) {
    _abrir(
      context,
      WebOperacionalShell(
        usuarioEmail: usuarioEmail,
        empresas: empresas,
        empresaAtualId: empresaAtualId,
        onTrocarEmpresa: onTrocarEmpresa,
        onSair: onSair,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compacto ? 62 : 68,
        titleSpacing: compacto ? 12 : 24,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.auto_awesome_mosaic_outlined,
                color: ImperiumWebTheme.accentStrong,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    compacto ? 'Imperium' : 'Imperium Manager',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (!compacto)
                    Text(
                      _nomeEmpresaAtual,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFAAB3BD),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!compacto)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FilledButton.tonalIcon(
                onPressed: () => _abrirOperacao(context),
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: const Text('Sistema completo'),
              ),
            ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Trocar empresa',
            onSelected: onTrocarEmpresa,
            itemBuilder: (context) => empresas
                .map(
                  (empresa) => PopupMenuItem<String>(
                    value: (empresa['empresa_id'] ?? '').toString(),
                    child: Row(
                      children: [
                        if ('${empresa['empresa_id']}' == empresaAtualId) ...[
                          const Icon(Icons.check_rounded, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            (empresa['nome'] ?? 'Empresa').toString(),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.business_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: usuarioEmail,
            onSelected: (valor) async {
              if (valor == 'sair') await onSair();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                value: 'email',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    usuarioEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'sair',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Sair'),
                  ],
                ),
              ),
            ],
            icon: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person_outline_rounded, size: 18),
            ),
          ),
          SizedBox(width: compacto ? 4 : 14),
        ],
      ),
      body: WebDashboardGerencialPage(
        key: ValueKey('dashboard-premium-$empresaAtualId'),
        onAbrirOperacao: () => _abrirOperacao(context),
        onAbrirContas: () => _abrir(context, const WebContasFinanceirasPage()),
        onAbrirDre: () => _abrir(context, const WebDrePage()),
        onAbrirRelatorios: () => _abrir(context, const WebRelatoriosPage()),
        onAbrirPonto: () => _abrir(context, const WebPontoPage()),
      ),
      floatingActionButton: compacto
          ? FloatingActionButton.extended(
              onPressed: () => _abrirOperacao(context),
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text('Módulos'),
            )
          : null,
    );
  }
}
