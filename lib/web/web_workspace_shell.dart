import 'package:flutter/material.dart';

import '../screens/licenca_status_page.dart';
import 'imperium_web_theme.dart';
import 'web_dashboard_gerencial_page.dart';
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

  String get _nomeEmpresaAtual {
    for (final empresa in empresas) {
      if ('${empresa['empresa_id']}' == empresaAtualId) {
        final nome = (empresa['nome'] ?? '').toString().trim();
        if (nome.isNotEmpty) return nome;
      }
    }
    return 'Empresa';
  }

  Future<void> _abrirPlano(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LicencaStatusPage(empresaId: empresaAtualId),
      ),
    );
  }

  Future<void> _abrirSistemaCompleto(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => WebOperacionalShell(
          key: ValueKey('sistema-completo-$empresaAtualId'),
          usuarioEmail: usuarioEmail,
          empresas: empresas,
          empresaAtualId: empresaAtualId,
          onTrocarEmpresa: (id) async {
            await onTrocarEmpresa(id);
            if (routeContext.mounted && Navigator.canPop(routeContext)) {
              Navigator.of(routeContext).pop();
            }
          },
          onSair: () async {
            await onSair();
            if (routeContext.mounted && Navigator.canPop(routeContext)) {
              Navigator.of(routeContext).pop();
            }
          },
        ),
      ),
    );
  }

  Future<void> _trocarEmpresa(String id) async {
    if (id.isEmpty || id == empresaAtualId) return;
    await onTrocarEmpresa(id);
  }

  Widget _atalhoSistemaCompleto(
    BuildContext context, {
    required bool compacto,
  }) {
    final tamanho = compacto ? 36.0 : 40.0;

    return Tooltip(
      message: 'Abrir sistema completo',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('abrir-sistema-completo-marca'),
          onTap: () => _abrirSistemaCompleto(context),
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            width: tamanho,
            height: tamanho,
            decoration: BoxDecoration(
              color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ImperiumWebTheme.border),
            ),
            child: const Icon(
              Icons.auto_awesome_mosaic_outlined,
              color: ImperiumWebTheme.accentStrong,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.sizeOf(context).width;
    final compacto = largura < 760;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compacto ? 64 : 72,
        titleSpacing: compacto ? 12 : 24,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _atalhoSistemaCompleto(context, compacto: compacto),
            const SizedBox(width: 11),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    compacto ? 'Imperium' : 'Imperium Manager',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compacto ? 16 : 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (!compacto)
                    Text(
                      _nomeEmpresaAtual,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9AA5B1),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Trocar empresa',
            onSelected: _trocarEmpresa,
            itemBuilder: (context) => empresas.map((empresa) {
              final id = (empresa['empresa_id'] ?? '').toString();
              final atual = id == empresaAtualId;
              return PopupMenuItem<String>(
                value: id,
                enabled: id.isNotEmpty && !atual,
                child: Row(
                  children: [
                    Icon(
                      atual
                          ? Icons.check_circle_rounded
                          : Icons.business_outlined,
                      size: 18,
                      color: atual ? ImperiumWebTheme.accentStrong : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        (empresa['nome'] ?? 'Empresa').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            icon: const Icon(Icons.domain_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: usuarioEmail,
            onSelected: (valor) async {
              if (valor == 'plano') {
                await _abrirPlano(context);
              } else if (valor == 'sair') {
                await onSair();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                value: 'conta',
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Conta conectada',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        usuarioEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'plano',
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Plano e assinatura'),
                  ],
                ),
              ),
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
          SizedBox(width: compacto ? 4 : 12),
        ],
      ),
      body: WebDashboardGerencialPage(
        key: ValueKey('dashboard-premium-$empresaAtualId'),
      ),
    );
  }
}
