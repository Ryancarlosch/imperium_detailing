import 'package:flutter/material.dart';

import 'imperium_web_theme.dart';
import 'web_estoque_config_page.dart';
import 'web_estoque_movimentacoes_page.dart';
import 'web_estoque_produtos_page.dart';

class WebEstoqueGestaoPage extends StatelessWidget {
  const WebEstoqueGestaoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: ImperiumWebTheme.surfaceSoft,
              border: Border(
                bottom: BorderSide(color: ImperiumWebTheme.border),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ImperiumWebTheme.contentMaxWidth,
                ),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(
                        icon: Icon(Icons.swap_vert_rounded),
                        text: 'Saldo e movimentações',
                      ),
                      Tab(
                        icon: Icon(Icons.inventory_2_outlined),
                        text: 'Cadastro de produtos',
                      ),
                      Tab(
                        icon: Icon(Icons.settings_outlined),
                        text: 'Configurações',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                WebEstoqueMovimentacoesPage(),
                WebEstoqueProdutosPage(),
                WebEstoqueConfigPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
