import 'package:flutter/material.dart';

import 'imperium_web_theme.dart';
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

  void _abrirPonto(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WebPontoPage()));
  }

  void _abrirDre(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WebDrePage()));
  }

  void _abrirRelatorios(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WebRelatoriosPage()));
  }

  void _abrirModulos(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Módulos gerenciais'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModuloTile(
                icon: Icons.badge_outlined,
                titulo: 'Ponto e funcionários',
                subtitulo:
                    'Equipe, batidas, ajustes administrativos, jornada e hora extra.',
                onTap: () {
                  Navigator.pop(dialogContext);
                  _abrirPonto(context);
                },
              ),
              const SizedBox(height: 10),
              _ModuloTile(
                icon: Icons.query_stats_rounded,
                titulo: 'DRE gerencial',
                subtitulo:
                    'Competência e caixa com descontos, taxas, custos FIFO e resultado gerencial.',
                onTap: () {
                  Navigator.pop(dialogContext);
                  _abrirDre(context);
                },
              ),
              const SizedBox(height: 10),
              _ModuloTile(
                icon: Icons.analytics_outlined,
                titulo: 'Relatórios gerenciais',
                subtitulo:
                    'Vendas líquidas, recebimentos, ticket médio, executores e comparativo competência × caixa.',
                onTap: () {
                  Navigator.pop(dialogContext);
                  _abrirRelatorios(context);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 760;

    return Stack(
      children: [
        WebOperacionalShell(
          key: ValueKey('workspace-$empresaAtualId'),
          usuarioEmail: usuarioEmail,
          empresas: empresas,
          empresaAtualId: empresaAtualId,
          onTrocarEmpresa: onTrocarEmpresa,
          onSair: onSair,
        ),
        Positioned(
          right: compacto ? 14 : 24,
          bottom: compacto ? 14 : 24,
          child: SafeArea(
            child: compacto
                ? FloatingActionButton.small(
                    tooltip: 'Módulos gerenciais',
                    onPressed: () => _abrirModulos(context),
                    child: const Icon(Icons.apps_rounded),
                  )
                : FloatingActionButton.extended(
                    onPressed: () => _abrirModulos(context),
                    icon: const Icon(Icons.apps_rounded),
                    label: const Text('Módulos'),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ModuloTile extends StatelessWidget {
  const _ModuloTile({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: ImperiumWebTheme.accentStrong),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFAAB3BD),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
