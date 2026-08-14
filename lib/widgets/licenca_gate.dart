import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/usuario_repository.dart';
import '../screens/dashboard_page.dart';
import '../screens/supabase_conta_page.dart';
import '../screens/usuario_inicio_page.dart';
import '../services/licenca_service.dart';

class LicencaGate extends StatefulWidget {
  const LicencaGate({super.key, required this.sessao, required this.onLogout});

  final Map<String, dynamic> sessao;
  final Future<void> Function() onLogout;

  @override
  State<LicencaGate> createState() => _LicencaGateState();
}

class _LicencaGateState extends State<LicencaGate> {
  final LicencaService _service = const LicencaService();
  final DateFormat _data = DateFormat('dd/MM/yyyy');

  bool _carregando = true;
  bool _usouCacheOffline = false;
  LicencaStatus? _status;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    if (mounted) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }

    try {
      final resultado = await _service.consultarComCacheOffline();

      if (!mounted) return;

      setState(() {
        _status = resultado.status;
        _usouCacheOffline = resultado.usouCacheOffline;
        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _status = null;
        _usouCacheOffline = false;
        _erro = _textoErro(erro);
        _carregando = false;
      });
    }
  }

  Future<void> _abrirContaNuvem() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const SupabaseContaPage()));

    if (!mounted) return;
    await _verificar();
  }

  String _textoErro(Object erro) {
    var texto = erro.toString().trim();

    for (final prefixo in const [
      'Bad state: ',
      'StateError: ',
      'PostgrestException: ',
      'AuthException: ',
      'Exception: ',
    ]) {
      if (texto.startsWith(prefixo)) {
        texto = texto.substring(prefixo.length).trim();
      }
    }

    return texto.isEmpty ? 'Não foi possível validar a licença.' : texto;
  }

  Widget _conteudoLiberado() {
    final perfil = (widget.sessao['perfil'] ?? '').toString().trim();

    if (perfil == UsuarioRepository.perfilFuncionario) {
      return UsuarioInicioPage(
        sessao: widget.sessao,
        onLogout: () {
          widget.onLogout();
        },
      );
    }

    return DashboardPage(
      sessao: widget.sessao,
      onLogout: () {
        widget.onLogout();
      },
    );
  }

  Widget _cartaoStatus(LicencaStatus status) {
    final validoAte = status.validoAte;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status.empresaNome.isEmpty ? 'Empresa' : status.empresaNome,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Plano: ${status.plano}'),
            Text('Status: ${status.statusEfetivo}'),
            if (validoAte != null)
              Text('Válido até: ${_data.format(validoAte)}'),
            if (status.diasRestantes != null)
              Text('Dias restantes: ${status.diasRestantes}'),
            if (_usouCacheOffline) ...[
              const SizedBox(height: 8),
              const Text(
                'Modo offline: usando a última validação da licença. '
                'O aplicativo precisa se conectar à nuvem dentro de 72 horas.',
                style: TextStyle(color: Colors.orangeAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Validando licença...'),
            ],
          ),
        ),
      );
    }

    final status = _status;

    if (status != null && status.acessoLiberado) {
      return _conteudoLiberado();
    }

    final motivo = status?.motivo.trim();
    final mensagem = motivo != null && motivo.isNotEmpty
        ? motivo
        : (_erro ?? 'A licença desta empresa precisa ser validada.');

    return Scaffold(
      appBar: AppBar(title: const Text('Acesso ao Imperium')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.lock_clock_outlined, size: 68),
          const SizedBox(height: 18),
          const Text(
            'Acesso temporariamente indisponível',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(mensagem, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          if (status != null) _cartaoStatus(status),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _verificar,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Validar novamente'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _abrirContaNuvem,
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('Conta na nuvem'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              widget.onLogout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sair'),
          ),
        ],
      ),
    );
  }
}
