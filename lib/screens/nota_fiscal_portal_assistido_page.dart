import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import '../services/nota_fiscal_consulta_publica_service.dart';
import '../services/nota_fiscal_importacao_service.dart';

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
  late final NotaFiscalImportacaoService _importacaoService;

  int _progresso = 0;
  bool _importando = false;
  bool _importarAoCarregar = false;
  final Set<String> _framesTentados = <String>{};
  final Set<String> _subframesObservados = <String>{};
  String _ultimoDiagnostico = '';
  String _status =
      'Se o portal pedir CAPTCHA, resolva normalmente. Depois toque em "Importar dados exibidos".';

  @override
  void initState() {
    super.initState();
    final repository = widget.repository ?? NotaFiscalEntradaRepository();
    _consultaService = NotaFiscalConsultaPublicaService(repository: repository);
    _importacaoService = NotaFiscalImportacaoService(repository: repository);

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
            if (!mounted) return;
            final importarAgora = _importarAoCarregar;
            setState(() {
              _progresso = 100;
              _status = importarAgora
                  ? 'O conteúdo fiscal foi aberto em tela própria. Importando automaticamente...'
                  : 'Quando fornecedor, produtos e valores estiverem visíveis, toque em "Importar dados exibidos".';
            });
            if (importarAgora) {
              _importarAoCarregar = false;
              Future<void>.delayed(
                const Duration(milliseconds: 350),
                _importar,
              );
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (!request.isMainFrame) {
              if (uri != null &&
                  NotaFiscalConsultaPublicaService.urlOficial(uri)) {
                _subframesObservados.add(uri.toString());
              }
              return NavigationDecision.navigate;
            }
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

      final snapshot = await _capturarSnapshotEstavel();
      if (snapshot.html.trim().isEmpty && snapshot.texto.trim().isEmpty) {
        throw const ConsultaPublicaFiscalException(
          'O portal não disponibilizou o conteúdo da página para leitura.',
        );
      }

      var nota = await _consultaService.importarHtmlLiberado(
        snapshot.html,
        chaveAcesso: widget.chaveAcesso,
        origemImportacao: widget.origem,
        textoVisivel: snapshot.texto,
        consultaUrl: uriAtual.toString(),
      );
      nota = await _importacaoService.registrarPortalAssistidoSucesso(
        nota: nota,
        url: uriAtual,
      );

      if (!mounted) return;
      Navigator.of(context).pop<NotaFiscalEntrada>(nota);
    } on ConsultaPublicaFiscalException catch (error) {
      final atualTexto = await _controller.currentUrl();
      final atual = Uri.tryParse(atualTexto ?? '') ?? widget.url;
      await _importacaoService.registrarPortalAssistidoFalha(
        chaveAcesso: widget.chaveAcesso,
        modelo: 65,
        url: atual,
        codigo: error.codigo,
        mensagem: error.mensagem,
      );
      final falhaDeConteudo =
          error.mensagem.contains('não entregou os itens') ||
          error.mensagem.contains('nome do fornecedor');
      if (falhaDeConteudo) {
        final abriuFrame = await _abrirFrameFiscalSeNecessario();
        if (abriuFrame) return;
      }
      final diagnostico = await _montarDiagnosticoPortal(error.mensagem);
      if (!mounted) return;
      setState(() {
        _importando = false;
        _ultimoDiagnostico = diagnostico;
        _status = falhaDeConteudo
            ? '${error.mensagem}\nDiagnóstico disponível abaixo.'
            : error.mensagem;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.mensagem),
          backgroundColor: Colors.red[700],
        ),
      );
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

  Future<_PortalSnapshot> _capturarSnapshotEstavel() async {
    final snapshots = <_PortalSnapshot>[];
    for (var tentativa = 0; tentativa < 3; tentativa++) {
      if (tentativa > 0) {
        await Future<void>.delayed(Duration(milliseconds: 450 * tentativa));
      }
      snapshots.add(await _capturarSnapshotPortal());
    }
    snapshots.sort((a, b) {
      final tamanhoA = a.html.length + a.texto.length;
      final tamanhoB = b.html.length + b.texto.length;
      return tamanhoB.compareTo(tamanhoA);
    });
    return snapshots.first;
  }

  Future<_PortalSnapshot> _capturarSnapshotPortal() async {
    final resultado = await _controller.runJavaScriptReturningResult(r'''
      (() => {
        const partesHtml = [];
        const partesTexto = [];
        const frames = [];
        const visitados = new Set();

        function visivel(el) {
          try {
            const estilo = getComputedStyle(el);
            if (estilo.display === 'none' || estilo.visibility === 'hidden') return false;
            const rect = el.getBoundingClientRect();
            return rect.width > 0 || rect.height > 0;
          } catch (_) {
            return true;
          }
        }

        function coletarShadow(root) {
          if (!root || !root.querySelectorAll) return;
          for (const el of root.querySelectorAll('*')) {
            try {
              if (el.shadowRoot) {
                const txt = el.shadowRoot.textContent || '';
                if (txt.trim()) partesTexto.push(txt);
                coletarShadow(el.shadowRoot);
              }
            } catch (_) {}
          }
        }

        function coletarValores(doc) {
          try {
            for (const el of doc.querySelectorAll('input,textarea,select,[aria-label],[title]')) {
              if (!visivel(el)) continue;
              const rotulo = el.getAttribute('aria-label') || el.getAttribute('title') || '';
              const valor = el.value || el.textContent || '';
              const txt = `${rotulo} ${valor}`.trim();
              if (txt) partesTexto.push(txt);
            }
          } catch (_) {}
        }

        function coletarTextoVisual(doc) {
          try {
            const folhas = [...doc.querySelectorAll('body *')]
              .filter(el => visivel(el) && el.children.length === 0)
              .map(el => ({
                texto: (el.innerText || el.textContent || '').trim(),
                rect: el.getBoundingClientRect(),
              }))
              .filter(x => x.texto.length > 0)
              .sort((a, b) => {
                const dy = a.rect.top - b.rect.top;
                return Math.abs(dy) > 4 ? dy : a.rect.left - b.rect.left;
              });
            if (folhas.length) partesTexto.push(folhas.map(x => x.texto).join('\n'));
          } catch (_) {}
        }

        function coletarDocumento(doc, profundidade = 0) {
          if (!doc || profundidade > 4) return;
          try {
            const chave = `${doc.URL || ''}|${profundidade}`;
            if (visitados.has(chave)) return;
            visitados.add(chave);

            if (doc.documentElement) {
              partesHtml.push(doc.documentElement.outerHTML || '');
              partesTexto.push(doc.documentElement.innerText || '');
              partesTexto.push(doc.documentElement.textContent || '');
            }
            if (doc.body) {
              partesTexto.push(doc.body.innerText || '');
              partesTexto.push(doc.body.textContent || '');
            }
            coletarValores(doc);
            coletarTextoVisual(doc);
            coletarShadow(doc);

            for (const el of doc.querySelectorAll('iframe,frame,object,embed')) {
              try {
                const src = el.src || el.data || el.getAttribute('src') || el.getAttribute('data') || '';
                if (src) {
                  try { frames.push(new URL(src, doc.baseURI).href); }
                  catch (_) { frames.push(src); }
                }
                const srcdoc = el.getAttribute && el.getAttribute('srcdoc');
                if (srcdoc && srcdoc.trim()) partesHtml.push(srcdoc);
              } catch (_) {}
              try {
                coletarDocumento(el.contentDocument || el.contentWindow?.document, profundidade + 1);
              } catch (_) {
                // Frame cross-origin: não tentamos contornar a política do navegador.
              }
            }
          } catch (_) {}
        }

        coletarDocumento(document);
        return JSON.stringify({
          html: partesHtml.join('\n'),
          texto: partesTexto.join('\n'),
          frames: [...new Set(frames)]
        });
      })()
    ''');

    final normalizado = _normalizarResultadoJavaScript(resultado);
    try {
      final json = jsonDecode(normalizado);
      if (json is Map<String, dynamic>) {
        final frames = (json['frames'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList();
        return _PortalSnapshot(
          html: json['html']?.toString() ?? '',
          texto: json['texto']?.toString() ?? '',
          frames: frames,
        );
      }
    } catch (_) {
      // Algumas plataformas já retornam a String desserializada.
    }
    return _PortalSnapshot(html: normalizado, texto: normalizado);
  }

  Future<bool> _abrirFrameFiscalSeNecessario() async {
    final snapshot = await _capturarSnapshotPortal();
    final atualTexto = await _controller.currentUrl();
    final atual = atualTexto == null ? null : Uri.tryParse(atualTexto);

    final candidatos = <Uri>[];
    final base = atual ?? widget.url;
    final origens = <String>{...snapshot.frames, ..._subframesObservados};
    for (final frame in origens) {
      final uri = NotaFiscalConsultaPublicaService.resolverUrlPortal(
        base,
        frame,
      );
      if (uri == null) continue;
      if (atual != null && uri.toString() == atual.toString()) continue;
      if (_framesTentados.contains(uri.toString())) continue;
      candidatos.add(uri);
    }

    if (candidatos.isEmpty) return false;

    candidatos.sort((a, b) {
      int peso(Uri uri) {
        final texto = uri.toString().toLowerCase();
        var valor = 0;
        if (texto.contains('nfce')) valor += 5;
        if (texto.contains('danfe')) valor += 4;
        if (texto.contains('consulta')) valor += 3;
        if (texto.contains('sat')) valor += 2;
        if (texto.contains('sef')) valor += 1;
        return valor;
      }

      return peso(b).compareTo(peso(a));
    });

    final escolhido = candidatos.first;
    _framesTentados.add(escolhido.toString());
    if (!mounted) return false;
    setState(() {
      _importando = false;
      _importarAoCarregar = true;
      _status =
          'Os itens estão em um quadro interno do portal. Abrindo o DANFE em tela própria para importar...';
    });
    await _controller.loadRequest(escolhido);
    return true;
  }

  Future<String> _montarDiagnosticoPortal(String erro) async {
    final snapshot = await _capturarSnapshotPortal();
    final atual = await _controller.currentUrl() ?? widget.url.toString();
    final frames = <String>{
      ...snapshot.frames,
      ..._subframesObservados,
    }.toList();
    final linhasTexto = snapshot.texto
        .replaceAll('\r', '')
        .split('\n')
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .take(12)
        .join(' | ');
    return [
      'Erro: $erro',
      'URL: $atual',
      'HTML capturado: ${snapshot.html.length} caracteres',
      'Texto capturado: ${snapshot.texto.length} caracteres',
      'Frames encontrados: ${frames.length}',
      if (frames.isNotEmpty) 'Frames: ${frames.take(8).join(' ; ')}',
      if (linhasTexto.isNotEmpty) 'Amostra: $linhasTexto',
    ].join('\n');
  }

  Future<void> _copiarDiagnostico() async {
    if (_ultimoDiagnostico.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _ultimoDiagnostico));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnóstico fiscal copiado.')),
    );
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
                  if (_ultimoDiagnostico.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: _copiarDiagnostico,
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Copiar diagnóstico fiscal'),
                    ),
                    const SizedBox(height: 8),
                  ],
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

class _PortalSnapshot {
  const _PortalSnapshot({
    required this.html,
    required this.texto,
    this.frames = const <String>[],
  });

  final String html;
  final String texto;
  final List<String> frames;
}
