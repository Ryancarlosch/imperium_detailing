import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const String _arquivoMarcadorPrimeiroUso =
    'imperium_primeiro_uso_assistente.flag';

Future<void> mostrarAssistentePrimeiroUso(
  BuildContext context, {
  bool forcarExibicao = false,
}) async {
  if (!forcarExibicao && !await _deveExibirAssistente()) {
    return;
  }

  if (!forcarExibicao) {
    await _registrarExibicao();
  }

  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AssistentePrimeiroUsoDialog(),
  );
}

Future<bool> _deveExibirAssistente() async {
  try {
    final diretorio = await getApplicationDocumentsDirectory();
    final arquivo = File(
      path.join(diretorio.path, _arquivoMarcadorPrimeiroUso),
    );

    return !await arquivo.exists();
  } catch (_) {
    return true;
  }
}

Future<void> _registrarExibicao() async {
  try {
    final diretorio = await getApplicationDocumentsDirectory();
    final arquivo = File(
      path.join(diretorio.path, _arquivoMarcadorPrimeiroUso),
    );

    if (!await arquivo.exists()) {
      await arquivo.create(recursive: true);
    }

    await arquivo.writeAsString(DateTime.now().toIso8601String(), flush: true);
  } catch (_) {
    // Se o marcador falhar, o assistente pode reaparecer na próxima execução.
  }
}

class _AssistentePrimeiroUsoDialog extends StatefulWidget {
  const _AssistentePrimeiroUsoDialog();

  @override
  State<_AssistentePrimeiroUsoDialog> createState() =>
      _AssistentePrimeiroUsoDialogState();
}

class _AssistentePrimeiroUsoDialogState
    extends State<_AssistentePrimeiroUsoDialog> {
  static const List<_AssistentePasso> _passos = [
    _AssistentePasso(
      titulo: 'Configurações da empresa',
      descricao:
          'Preencha os dados cadastrais, assinatura e aparência antes de começar a operar.',
      icone: Icons.business_outlined,
    ),
    _AssistentePasso(
      titulo: 'Serviços',
      descricao:
          'Cadastre os serviços executados para usá-los em orçamentos e ordens de serviço.',
      icone: Icons.handyman_outlined,
    ),
    _AssistentePasso(
      titulo: 'Clientes',
      descricao:
          'Registre os clientes para manter o histórico e agilizar novos atendimentos.',
      icone: Icons.person_outline,
    ),
    _AssistentePasso(
      titulo: 'Veículos',
      descricao:
          'Vincule os veículos aos clientes para organizar o atendimento e as fotos.',
      icone: Icons.directions_car_outlined,
    ),
    _AssistentePasso(
      titulo: 'Agendamento',
      descricao:
          'Use a agenda para planejar a entrada dos veículos e acompanhar os compromissos.',
      icone: Icons.event_available_outlined,
    ),
    _AssistentePasso(
      titulo: 'Ordem de Serviço',
      descricao:
          'Abra a OS, lance itens, finalize o atendimento e gere o PDF com assinatura.',
      icone: Icons.assignment_outlined,
    ),
  ];

  int _indiceAtual = 0;

  void _fechar() {
    Navigator.of(context).pop();
  }

  void _avancar() {
    if (_indiceAtual >= _passos.length - 1) {
      _fechar();
      return;
    }

    setState(() {
      _indiceAtual += 1;
    });
  }

  void _voltar() {
    if (_indiceAtual == 0) {
      _fechar();
      return;
    }

    setState(() {
      _indiceAtual -= 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final passoAtual = _passos[_indiceAtual];

    return AlertDialog(
      title: const Text('Primeiros passos'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use esta sequência para configurar o sistema uma única vez e começar a trabalhar.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: (_indiceAtual + 1) / _passos.length,
              minHeight: 6,
              borderRadius: BorderRadius.circular(99),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _PassoAssistenteCard(
                key: ValueKey(_indiceAtual),
                passo: passoAtual,
                indiceAtual: _indiceAtual + 1,
                totalPassos: _passos.length,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_passos.length, (index) {
                final selecionado = index == _indiceAtual;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: selecionado ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: selecionado
                        ? const Color(0xFFD6A84B)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _fechar, child: const Text('Fechar')),
        OutlinedButton(
          onPressed: _indiceAtual == 0 ? null : _voltar,
          child: const Text('Anterior'),
        ),
        FilledButton(
          onPressed: _avancar,
          child: Text(
            _indiceAtual == _passos.length - 1 ? 'Concluir' : 'Próximo',
          ),
        ),
      ],
    );
  }
}

class _PassoAssistenteCard extends StatelessWidget {
  const _PassoAssistenteCard({
    super.key,
    required this.passo,
    required this.indiceAtual,
    required this.totalPassos,
  });

  final _AssistentePasso passo;
  final int indiceAtual;
  final int totalPassos;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(passo.icone, color: const Color(0xFFD6A84B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$indiceAtual de $totalPassos',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      passo.titulo,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            passo.descricao,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _AssistentePasso {
  const _AssistentePasso({
    required this.titulo,
    required this.descricao,
    required this.icone,
  });

  final String titulo;
  final String descricao;
  final IconData icone;
}
