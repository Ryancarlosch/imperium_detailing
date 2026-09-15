import 'package:flutter/material.dart';

import 'usuarios_permissoes_page.dart';

class FuncionariosAcessoNuvemPage extends StatelessWidget {
  const FuncionariosAcessoNuvemPage({super.key, required this.empresaId});

  final String empresaId;

  Future<void> _abrirUsuarios(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const UsuariosPermissoesPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acessos de funcionários')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.groups_2_outlined, size: 54),
                          SizedBox(height: 16),
                          Text(
                            'Funcionários ficam dentro da empresa',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'O administrador cria o usuário do funcionário no '
                            'próprio Imperium, vincula o colaborador e define as '
                            'permissões. O funcionário não cria uma conta de '
                            'empresa, não assina outro plano e não usa o e-mail '
                            'da assinatura para entrar como administrador.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Controle pelo administrador',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Cadastre o funcionário, escolha o usuário interno '
                            'e libere somente as áreas que ele pode acessar. '
                            'Assim cada empresa mantém sua equipe isolada e sob '
                            'controle do administrador.',
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _abrirUsuarios(context),
                              icon: const Icon(Icons.manage_accounts_outlined),
                              label: const Text(
                                'Gerenciar usuários e permissões',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'O acesso em outros aparelhos continuará sendo '
                              'vinculado ao usuário interno da empresa. A conta '
                              'cloud por e-mail e senha permanece exclusiva do '
                              'administrador/proprietário.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
