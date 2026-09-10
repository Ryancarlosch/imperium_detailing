import 'package:flutter/material.dart';

import '../repositories/usuario_repository.dart';

class MeuPerfilPage extends StatefulWidget {
  const MeuPerfilPage({super.key, required this.sessao});

  final Map<String, dynamic> sessao;

  @override
  State<MeuPerfilPage> createState() => _MeuPerfilPageState();
}

class _MeuPerfilPageState extends State<MeuPerfilPage> {
  final UsuarioRepository _repository = UsuarioRepository();

  bool _salvando = false;

  Future<void> _alterarPin() async {
    final atual = TextEditingController();
    final novo = TextEditingController();
    final confirmar = TextEditingController();

    var ocultarAtual = true;
    var ocultarNovo = true;
    var ocultarConfirmacao = true;

    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Alterar meu PIN'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: atual,
                    obscureText: ocultarAtual,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: 'PIN atual',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setDialogState(() => ocultarAtual = !ocultarAtual),
                        icon: Icon(
                          ocultarAtual
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: novo,
                    obscureText: ocultarNovo,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: 'Novo PIN',
                      helperText: 'Use de 4 a 8 números.',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setDialogState(() => ocultarNovo = !ocultarNovo),
                        icon: Icon(
                          ocultarNovo
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmar,
                    obscureText: ocultarConfirmacao,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: 'Confirmar novo PIN',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => ocultarConfirmacao = !ocultarConfirmacao,
                        ),
                        icon: Icon(
                          ocultarConfirmacao
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (novo.text.trim() != confirmar.text.trim()) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('A confirmação do novo PIN não confere.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Alterar PIN'),
              ),
            ],
          );
        },
      ),
    );

    if (resultado != true) {
      atual.dispose();
      novo.dispose();
      confirmar.dispose();
      return;
    }

    setState(() => _salvando = true);

    try {
      final usuarioId = _int(widget.sessao['id']);
      await _repository.alterarPinComPinAtual(
        usuarioId: usuarioId,
        pinAtual: atual.text,
        novoPin: novo.text,
      );

      if (mounted) {
        _mensagem('PIN alterado com segurança.');
      }
    } catch (erro) {
      if (mounted) {
        _mensagem(_textoErro(erro), erro: true);
      }
    } finally {
      atual.dispose();
      novo.dispose();
      confirmar.dispose();
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  int _int(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num) {
      return valor.toInt();
    }
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();
    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'Invalid argument(s): ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }
    return texto;
  }

  void _mensagem(String texto, {bool erro = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final permissoesBrutas = widget.sessao['permissoes'];
    final permissoes = permissoesBrutas is Map
        ? Map<String, dynamic>.from(permissoesBrutas)
        : const <String, dynamic>{};

    final liberados = UsuarioRepository.modulos
        .where((modulo) => permissoes[modulo] == true)
        .map((modulo) => UsuarioRepository.nomesModulos[modulo] ?? modulo)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil e segurança')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (widget.sessao['nome'] ?? 'Usuário').toString(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('@${widget.sessao['login'] ?? ''}'),
                  Text((widget.sessao['perfil'] ?? '').toString()),
                  if ((widget.sessao['colaborador_nome'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty)
                    Text('Funcionário: ${widget.sessao['colaborador_nome']}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('Alterar meu PIN'),
              subtitle: const Text(
                'O PIN atual é conferido antes da troca e o novo PIN continua armazenado somente como hash.',
              ),
              trailing: _salvando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _salvando ? null : _alterarPin,
            ),
          ),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Módulos liberados',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (liberados.isEmpty)
                    const Text(
                      'Nenhum módulo adicional liberado.',
                      style: TextStyle(color: Colors.white60),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: liberados
                          .map(
                            (item) => Chip(
                              avatar: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(item),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Após várias tentativas consecutivas de PIN incorreto, o login é temporariamente bloqueado. O administrador pode liberar o acesso pela tela Usuários e permissões.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
