import 'package:flutter/material.dart';

import 'web_estoque_movimentacoes_page.dart';
import 'web_estoque_produtos_page.dart';

class WebEstoqueGestaoPage extends StatelessWidget {
  const WebEstoqueGestaoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            child: TabBar(
              tabs: [
                Tab(
                  icon: Icon(Icons.swap_vert_rounded),
                  text: 'Saldo e movimentações',
                ),
                Tab(
                  icon: Icon(Icons.inventory_2_outlined),
                  text: 'Cadastro de produtos',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                WebEstoqueMovimentacoesPage(),
                WebEstoqueProdutosPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
