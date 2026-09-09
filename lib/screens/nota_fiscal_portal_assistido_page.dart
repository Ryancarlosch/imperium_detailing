import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/nota_fiscal_consulta_publica_service.dart';

class NotaFiscalPortalAssistidoPage extends StatefulWidget {
  const NotaFiscalPortalAssistidoPage({
    super.key,
    required this.url,
    required this.chaveAcesso,
    required this.origem,
    this.repository,
  });

  final Uri url;
  final String chaveAcesso;
  final String origem;
  final NotaFiscalEntradaRepository? repository;

  @override
  State<NotaFiscalPortalAssistidoPage> createState() =>
      _NotaFiscalPortalAssistidoPageState();
}

class _NotaFiscalPortalAssistidoPageState
    extends State<NotaFiscalPortalAssistidoPage> {
  late final WebViewController _controller;
  late final NotaFiscalConsultaPublicaService _consultaService;

  int _progresso = 0;
  bool _importando = false;
  String _status =
      'Se o portal pedir CAPTCHA, resolva normalmente. Depois toque em "Importar dados exibidos".';

  @override
  void initState() {
    super.initState();
    final repository = widget.repository ?? NotaFiscalEntradaRepository();
    _consultaService = NotaFiscalConsultaPublicaService(repository: repository);

    final inicial = NotaFiscalConsultaPublicaService.urlSegura(widget.url);
    if (!NotaFiscalConsultaPublicaService.urlOficial(inicial)) {
      throw ArgumentError(
        'A URL fiscal não pertence a um domínio oficial gov.br.',
      );
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progresso = value);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _progresso = 0;
                _status =
                    'Aguarde o portal carregar. Resolva o CAPTCHA se ele aparecer.';
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _progresso = 100;
                _status =
                    'Quando fornecedor, produtos e valores estiverem visíveis, toque em "Importar dados exibidos".';
              });
            }
          },
          onNavigationRequest: (request) {
            // reCAPTCHA e outros componentes do portal podem usar iframes de
            // domínios externos. Restringimos apenas a navegação principal;
            // subframes continuam livres para o CAPTCHA funcionar normalmente.
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            if (uri == null ||
                !NotaFiscalConsultaPublicaService.urlOficial(uri)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(inicial);
  }

  Future<void> _importar() async {
    if (_importando) return;
    setState(() {
      _importando = true;
      _status = 'Lendo os dados que o portal liberou...';
    });

    try {
      final atual = await _controller.currentUrl();
      final uriAtual = atual == null ? null : Uri.tryParse(atual);
      if (uriAtual == null ||
          !NotaFiscalConsultaPublicaService.urlOficial(uriAtual)) {
        throw const ConsultaPublicaFiscalException(
          'A página atual não é um portal fiscal oficial.',
        );
      }

      final resultado = await _controller.runJavaScriptReturningResult(r'''
        (() => {
          let html = document.documentElement?.outerHTML || '';
          // Alguns portais estaduais exibem o DANFE em iframe do mesmo domínio.
          // Capturamos esses frames quando o navegador permite. Frames externos
          // (por exemplo, reCAPTCHA) são ignorados pela política de mesma origem.
          for (let i = 0; i < window.frames.length; i++) {
            try {
              const doc = window.frames[i].document;
              if (doc && doc.documentElement) {
                html += '\n' + doc.documentElement.outerHTML;
              }
            } catch (_) {}
          }
          return html;
        })()
      ''');
      final html = _normalizarResultadoJavaScript(resultado);
      if (html.trim().isEmpty) {
        throw const ConsultaPublicaFiscalException(
          'O portal não disponibilizou o conteúdo da página para leitura.',
        );
      }

      final nota = await _consultaService.importarHtmlLiberado(
        html,
        chaveAcesso: widget.chaveAcesso,
        origemImportacao: widget.origem,
      );

      if (!mounted) return;
      Navigator.of(context).pop<NotaFiscalEntrada>(nota);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importando = false;
        _status = '$error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: Colors.red[700]),
      );
    }
  }

  Future<void> _voltar() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  Future<void> _avancar() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
  }

  static String _normalizarResultadoJavaScript(Object resultado) {
    if (resultado is! String) return resultado.toString();
    final texto = resultado.trim();
    if (texto.length >= 2 && texto.startsWith('"') && texto.endsWith('"')) {
      try {
        final decoded = jsonDecode(texto);
        if (decoded is String) return decoded;
      } catch (_) {
        // Algumas plataformas já retornam a String sem JSON encoding.
      }
    }
    return texto;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consulta fiscal assistida'),
        actions: [
          IconButton(
            tooltip: 'Voltar no portal',
            onPressed: _voltar,
            icon: const Icon(Icons.arrow_back),
          ),
          IconButton(
            tooltip: 'Avançar no portal',
            onPressed: _avancar,
            icon: const Icon(Icons.arrow_forward),
          ),
          IconButton(
            tooltip: 'Recarregar',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progresso < 100)
            LinearProgressIndicator(value: _progresso / 100),
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _importando ? null : _importar,
                    icon: _importando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_done_outlined),
                    label: Text(
                      _importando ? 'Importando...' : 'Importar dados exibidos',
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
