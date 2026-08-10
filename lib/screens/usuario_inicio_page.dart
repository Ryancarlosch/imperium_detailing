import 'package:flutter/material.dart';

import '../repositories/usuario_repository.dart';
import 'agenda_page.dart';
import 'clientes_page.dart';
import 'configuracoes_page.dart';
import 'custo_servicos_page.dart';
import 'dre_page.dart';
import 'estoque_page.dart';
import 'financeiro_page.dart';
import 'meu_ponto_page.dart';
import 'orcamentos_page.dart';
import 'ordens_servico_page.dart';
import 'pagamentos_funcionarios_page.dart';

class UsuarioInicioPage
    extends StatelessWidget {
  const UsuarioInicioPage({
    super.key,
    required this.sessao,
    required this.onLogout,
  });

  final Map<String, dynamic> sessao;
  final VoidCallback onLogout;

  bool _pode(String modulo) {
    if ((sessao['perfil'] ?? '').toString() ==
        UsuarioRepository
            .perfilAdministrador) {
      return true;
    }

    final bruto = sessao['permissoes'];

    if (bruto is Map) {
      return bruto[modulo] == true;
    }

    return false;
  }

  int? get _colaboradorId {
    final valor = sessao['colaborador_id'];

    if (valor is int) return valor;
    if (valor is num) return valor.toInt();

    return int.tryParse(
      valor?.toString() ?? '',
    );
  }

  Future<void> _abrir(
    BuildContext context,
    Widget pagina,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => pagina,
      ),
    );
  }

  List<_ModuloUsuario> _modulos(
    BuildContext context,
  ) {
    final itens = <_ModuloUsuario>[];

    void adicionar(
      String modulo,
      String titulo,
      IconData icone,
      Widget pagina,
    ) {
      if (_pode(modulo)) {
        itens.add(
          _ModuloUsuario(
            titulo: titulo,
            icone: icone,
            onTap: () =>
                _abrir(context, pagina),
          ),
        );
      }
    }

    if (_pode('ponto') &&
        _colaboradorId != null) {
      itens.add(
        _ModuloUsuario(
          titulo: 'Meu ponto',
          icone:
              Icons.fingerprint_rounded,
          onTap: () => _abrir(
            context,
            MeuPontoPage(
              colaboradorId:
                  _colaboradorId!,
              nome: (sessao[
                              'colaborador_nome'] ??
                          sessao['nome'] ??
                          'Funcionário')
                      .toString(),
            ),
          ),
        ),
      );
    }

    adicionar(
      'clientes',
      'Clientes',
      Icons.people_outline_rounded,
      const ClientesPage(),
    );

    adicionar(
      'agenda',
      'Agenda',
      Icons.calendar_month_outlined,
      const AgendaPage(),
    );

    adicionar(
      'orcamentos',
      'Orçamentos',
      Icons.request_quote_outlined,
      const OrcamentosPage(),
    );

    adicionar(
      'ordens_servico',
      'Ordens de Serviço',
      Icons.car_repair_outlined,
      const OrdensServicoPage(
        statusInicial: 'Todos',
      ),
    );

    adicionar(
      'estoque',
      'Estoque',
      Icons.inventory_2_outlined,
      const EstoquePage(),
    );

    adicionar(
      'financeiro',
      'Financeiro',
      Icons.account_balance_wallet_outlined,
      const FinanceiroPage(),
    );

    adicionar(
      'dre',
      'DRE',
      Icons.analytics_outlined,
      const DrePage(),
    );

    adicionar(
      'precificacao',
      'Precificação',
      Icons.price_check_outlined,
      const CustoServicosPage(),
    );

    adicionar(
      'funcionarios',
      'Funcionários',
      Icons.badge_outlined,
      const PagamentosFuncionariosPage(),
    );

    adicionar(
      'configuracoes',
      'Configurações',
      Icons.settings_outlined,
      const ConfiguracoesPage(),
    );

    return itens;
  }

  @override
  Widget build(BuildContext context) {
    final modulos = _modulos(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Imperium'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: onLogout,
            icon: const Icon(
              Icons.logout_rounded,
            ),
          ),
        ],
      ),
      body: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding:
                  const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    child: Icon(
                      Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          (sessao['nome'] ??
                                  'Usuário')
                              .toString(),
                          style:
                              const TextStyle(
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (sessao['perfil'] ?? '')
                              .toString(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (modulos.isEmpty)
            const Card(
              child: Padding(
                padding:
                    EdgeInsets.all(18),
                child: Text(
                  'Nenhum módulo foi liberado para este usuário.',
                  textAlign:
                      TextAlign.center,
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(),
              itemCount: modulos.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.45,
              ),
              itemBuilder: (_, index) {
                final item =
                    modulos[index];

                return Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(12),
                    onTap: item.onTap,
                    child: Padding(
                      padding:
                          const EdgeInsets.all(14),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icone,
                            size: 30,
                          ),
                          const SizedBox(
                            height: 9,
                          ),
                          Text(
                            item.titulo,
                            textAlign:
                                TextAlign.center,
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ModuloUsuario {
  const _ModuloUsuario({
    required this.titulo,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final IconData icone;
  final VoidCallback onTap;
}
