import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../services/web_configuracao_arquivo_service.dart';
import '../services/web_configuracao_empresa_service.dart';
import 'imperium_web_theme.dart';

class WebConfiguracoesEmpresaPage extends StatefulWidget {
  const WebConfiguracoesEmpresaPage({super.key});

  @override
  State<WebConfiguracoesEmpresaPage> createState() =>
      _WebConfiguracoesEmpresaPageState();
}

class _WebConfiguracoesEmpresaPageState
    extends State<WebConfiguracoesEmpresaPage> {
  final _service = WebConfiguracaoEmpresaService.instance;
  final _arquivoService = WebConfiguracaoArquivoService.instance;

  bool _carregando = true;
  bool _salvando = false;
  bool _processandoArquivo = false;
  String? _erro;
  Map<String, dynamic> _atual = const {};
  Map<String, WebConfiguracaoArquivo> _arquivos = const {};
  Uint8List? _logoBytes;
  Uint8List? _assinaturaBytes;

  final _nomeFantasia = TextEditingController();
  final _razaoSocial = TextEditingController();
  final _cnpj = TextEditingController();
  final _ie = TextEditingController();
  final _telefone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _site = TextEditingController();
  final _instagram = TextEditingController();
  final _facebook = TextEditingController();
  final _endereco = TextEditingController();
  final _numero = TextEditingController();
  final _complemento = TextEditingController();
  final _bairro = TextEditingController();
  final _cidade = TextEditingController();
  final _estado = TextEditingController();
  final _cep = TextEditingController();
  final _nomeAplicativo = TextEditingController();
  String _tema = 'escuro';
  int _corPrincipal = 0xFFD6A84B;
  int _corSecundaria = 0xFF1A1A1A;
  final _validadeOrcamento = TextEditingController();
  final _rodapeDocumentos = TextEditingController();
  final _termosOrcamento = TextEditingController();
  final _termosOs = TextEditingController();
  final _observacaoPadrao = TextEditingController();
  final _mensagemAgradecimento = TextEditingController();
  final _mensagemOrcamento = TextEditingController();
  final _mensagemConfirmacao = TextEditingController();
  final _mensagemEntrega = TextEditingController();
  final _mensagemCobranca = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final controller in [
      _nomeFantasia,
      _razaoSocial,
      _cnpj,
      _ie,
      _telefone,
      _whatsapp,
      _email,
      _site,
      _instagram,
      _facebook,
      _endereco,
      _numero,
      _complemento,
      _bairro,
      _cidade,
      _estado,
      _cep,
      _nomeAplicativo,
      _validadeOrcamento,
      _rodapeDocumentos,
      _termosOrcamento,
      _termosOs,
      _observacaoPadrao,
      _mensagemAgradecimento,
      _mensagemOrcamento,
      _mensagemConfirmacao,
      _mensagemEntrega,
      _mensagemCobranca,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final atual = await _service.carregar();
      if (!mounted) return;
      _atual = atual;
      _preencher(atual);
      try {
        await _carregarArquivos();
      } catch (_) {
        // Configurações textuais continuam disponíveis mesmo se o Storage
        // estiver temporariamente indisponível.
      }
    } catch (e) {
      if (!mounted) return;
      _erro = _textoErro(e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _preencher(Map<String, dynamic> item) {
    _nomeFantasia.text = _texto(item['nome_fantasia']);
    _razaoSocial.text = _texto(item['razao_social']);
    _cnpj.text = _texto(item['cnpj']);
    _ie.text = _texto(item['inscricao_estadual']);
    _telefone.text = _texto(item['telefone']);
    _whatsapp.text = _texto(item['whatsapp']);
    _email.text = _texto(item['email']);
    _site.text = _texto(item['site']);
    _instagram.text = _texto(item['instagram']);
    _facebook.text = _texto(item['facebook']);
    _endereco.text = _texto(item['endereco']);
    _numero.text = _texto(item['numero']);
    _complemento.text = _texto(item['complemento']);
    _bairro.text = _texto(item['bairro']);
    _cidade.text = _texto(item['cidade']);
    _estado.text = _texto(item['estado']);
    _cep.text = _texto(item['cep']);
    _nomeAplicativo.text = _texto(
      item['nome_aplicativo'],
      padrao: 'Imperium Detailing',
    );
    _tema = _texto(item['tema'], padrao: 'escuro') == 'claro'
        ? 'claro'
        : 'escuro';
    _corPrincipal = _inteiro(
      item['cor_principal'],
      padrao: 0xFFD6A84B,
    );
    _corSecundaria = _inteiro(
      item['cor_secundaria'],
      padrao: 0xFF1A1A1A,
    );
    _validadeOrcamento.text = _texto(
      item['validade_orcamento_dias'],
      padrao: '15',
    );
    _rodapeDocumentos.text = _texto(item['rodape_documentos']);
    _termosOrcamento.text = _texto(item['termos_orcamento']);
    _termosOs.text = _texto(item['termos_ordem_servico']);
    _observacaoPadrao.text = _texto(item['observacao_padrao']);
    _mensagemAgradecimento.text = _texto(item['mensagem_agradecimento']);
    _mensagemOrcamento.text = _texto(item['mensagem_orcamento']);
    _mensagemConfirmacao.text = _texto(item['mensagem_confirmacao']);
    _mensagemEntrega.text = _texto(item['mensagem_entrega']);
    _mensagemCobranca.text = _texto(item['mensagem_cobranca']);
  }

  Future<void> _carregarArquivos() async {
    final arquivos = await _arquivoService.listarAtivos();
    final imagens = await Future.wait<Uint8List?>([
      _arquivoService.baixar(arquivos['logo']),
      _arquivoService.baixar(arquivos['assinatura_empresa']),
    ]);
    if (!mounted) return;
    setState(() {
      _arquivos = arquivos;
      _logoBytes = imagens[0];
      _assinaturaBytes = imagens[1];
    });
  }

  Future<void> _selecionarImagem(String tipo) async {
    if (_processandoArquivo) return;

    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
      dialogTitle: tipo == 'logo'
          ? 'Selecionar logo da empresa'
          : 'Selecionar assinatura da empresa',
    );
    if (resultado == null || resultado.files.isEmpty) return;

    final arquivo = resultado.files.single;
    final bytes = arquivo.bytes;
    if (bytes == null || bytes.isEmpty) {
      _snack('Não foi possível ler o arquivo selecionado.', erro: true);
      return;
    }

    await _salvarArquivoVisual(
      tipo: tipo,
      bytes: bytes,
      nomeOriginal: arquivo.name,
    );
  }

  Future<void> _salvarArquivoVisual({
    required String tipo,
    required Uint8List bytes,
    required String nomeOriginal,
  }) async {
    if (_processandoArquivo) return;
    setState(() => _processandoArquivo = true);

    try {
      await _arquivoService.salvar(
        tipo: tipo,
        bytes: bytes,
        nomeOriginal: nomeOriginal,
        mime: '',
      );
      await _carregarArquivos();
      _snack(
        tipo == 'logo'
            ? 'Logo salva no Cloud.'
            : 'Assinatura da empresa salva no Cloud.',
      );
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _processandoArquivo = false);
    }
  }

  Future<void> _desenharAssinatura() async {
    if (_processandoArquivo) return;

    final controller = SignatureController(
      penStrokeWidth: 3.5,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );

    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assinatura da empresa'),
        content: SizedBox(
          width: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Desenhe com o mouse ou toque. A assinatura será salva em PNG no Storage privado da empresa.',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26),
                ),
                clipBehavior: Clip.antiAlias,
                child: Signature(
                  controller: controller,
                  backgroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: controller.clear,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Limpar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (controller.isEmpty) return;
              final png = await controller.toPngBytes();
              if (png != null && dialogContext.mounted) {
                Navigator.pop(dialogContext, png);
              }
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar assinatura'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (bytes == null || bytes.isEmpty) return;

    await _salvarArquivoVisual(
      tipo: 'assinatura_empresa',
      bytes: bytes,
      nomeOriginal:
          'assinatura_empresa_${DateTime.now().millisecondsSinceEpoch}.png',
    );
  }

  Future<void> _removerArquivo(String tipo) async {
    if (_processandoArquivo) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tipo == 'logo' ? 'Remover logo' : 'Remover assinatura'),
        content: Text(
          tipo == 'logo'
              ? 'Deseja remover a logo ativa da empresa?'
              : 'Deseja remover a assinatura ativa da empresa?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _processandoArquivo = true);
    try {
      await _arquivoService.remover(tipo);
      await _carregarArquivos();
      _snack(tipo == 'logo' ? 'Logo removida.' : 'Assinatura removida.');
    } catch (e) {
      _snack(_textoErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _processandoArquivo = false);
    }
  }

  Widget _arquivoVisualCard({
    required String titulo,
    required String subtitulo,
    required Uint8List? bytes,
    required WebConfiguracaoArquivo? arquivo,
    required IconData fallbackIcon,
    required List<Widget> actions,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 118,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? Icon(fallbackIcon, size: 38, color: Colors.white54)
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitulo,
                    style: const TextStyle(
                      color: Color(0xFF89939E),
                      fontSize: 12,
                    ),
                  ),
                  if (arquivo != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${arquivo.nomeOriginal} · '
                      '${(arquivo.tamanho / 1024).toStringAsFixed(1)} KB',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvar() async {
    if (_salvando) return;

    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      final salvo = await _service.salvar(
        atual: _atual,
        valores: <String, dynamic>{
          'nome_fantasia': _nomeFantasia.text,
          'razao_social': _razaoSocial.text,
          'cnpj': _cnpj.text,
          'inscricao_estadual': _ie.text,
          'telefone': _telefone.text,
          'whatsapp': _whatsapp.text,
          'email': _email.text,
          'site': _site.text,
          'instagram': _instagram.text,
          'facebook': _facebook.text,
          'endereco': _endereco.text,
          'numero': _numero.text,
          'complemento': _complemento.text,
          'bairro': _bairro.text,
          'cidade': _cidade.text,
          'estado': _estado.text,
          'cep': _cep.text,
          'nome_aplicativo': _nomeAplicativo.text,
          'tema': _tema,
          'cor_principal': _corPrincipal,
          'cor_secundaria': _corSecundaria,
          'validade_orcamento_dias': _validadeOrcamento.text,
          'rodape_documentos': _rodapeDocumentos.text,
          'termos_orcamento': _termosOrcamento.text,
          'termos_ordem_servico': _termosOs.text,
          'observacao_padrao': _observacaoPadrao.text,
          'mensagem_agradecimento': _mensagemAgradecimento.text,
          'mensagem_orcamento': _mensagemOrcamento.text,
          'mensagem_confirmacao': _mensagemConfirmacao.text,
          'mensagem_entrega': _mensagemEntrega.text,
          'mensagem_cobranca': _mensagemCobranca.text,
        },
      );
      if (!mounted) return;
      _atual = salvo;
      _preencher(salvo);
      _snack('Configurações salvas e disponíveis para sincronização.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = _textoErro(e));
      _snack(_textoErro(e), erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _secao({
    required String titulo,
    required String subtitulo,
    required List<Widget> children,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              subtitulo,
              style: const TextStyle(color: Color(0xFF89939E), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _linha(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700 || fields.length == 1) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i < fields.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              Expanded(child: fields[i]),
              if (i < fields.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  InputDecoration _dec(String label, IconData icon) {
    return InputDecoration(labelText: label, prefixIcon: Icon(icon));
  }

  Widget _seletorCor({
    required String titulo,
    required int selecionada,
    required List<(String, int)> opcoes,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opcao in opcoes)
              ChoiceChip(
                selected: selecionada == opcao.$2,
                onSelected: (_) => onChanged(opcao.$2),
                avatar: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Color(opcao.$2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                label: Text(opcao.$1),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            compacto ? 16 : 24,
            compacto ? 18 : 24,
            compacto ? 16 : 24,
            40,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configurações da empresa',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Dados usados no Web, Android, documentos e mensagens.',
                        style: TextStyle(color: Color(0xFFAAB3BD)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                OutlinedButton.icon(
                  onPressed: _salvando ? null : _carregar,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Atualizar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar'),
                ),
              ],
            ),
            if (_erro != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(_erro!),
              ),
            ],
            const SizedBox(height: 20),
            _secao(
              titulo: 'Empresa',
              subtitulo:
                  'Identificação e contatos oficiais usados nos documentos e comunicações.',
              children: [
                _linha([
                  TextField(
                    controller: _nomeFantasia,
                    decoration: _dec('Nome fantasia', Icons.store_outlined),
                  ),
                  TextField(
                    controller: _razaoSocial,
                    decoration: _dec(
                      'Razão social',
                      Icons.business_center_outlined,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _linha([
                  TextField(
                    controller: _cnpj,
                    decoration: _dec('CNPJ/CPF', Icons.badge_outlined),
                  ),
                  TextField(
                    controller: _ie,
                    decoration: _dec(
                      'Inscrição estadual',
                      Icons.confirmation_number_outlined,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _linha([
                  TextField(
                    controller: _telefone,
                    decoration: _dec('Telefone', Icons.phone_outlined),
                  ),
                  TextField(
                    controller: _whatsapp,
                    decoration: _dec('WhatsApp', Icons.chat_outlined),
                  ),
                  TextField(
                    controller: _email,
                    decoration: _dec('E-mail', Icons.alternate_email_rounded),
                  ),
                ]),
                const SizedBox(height: 10),
                _linha([
                  TextField(
                    controller: _site,
                    decoration: _dec('Site', Icons.language_outlined),
                  ),
                  TextField(
                    controller: _instagram,
                    decoration: _dec('Instagram', Icons.camera_alt_outlined),
                  ),
                  TextField(
                    controller: _facebook,
                    decoration: _dec('Facebook', Icons.public_outlined),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 14),
            _secao(
              titulo: 'Endereço',
              subtitulo: 'Usado em documentos e identificação da empresa.',
              children: [
                _linha([
                  TextField(
                    controller: _endereco,
                    decoration: _dec('Endereço', Icons.location_on_outlined),
                  ),
                  TextField(
                    controller: _numero,
                    decoration: _dec('Número', Icons.numbers_outlined),
                  ),
                  TextField(
                    controller: _complemento,
                    decoration: _dec('Complemento', Icons.apartment_outlined),
                  ),
                ]),
                const SizedBox(height: 10),
                _linha([
                  TextField(
                    controller: _bairro,
                    decoration: _dec('Bairro', Icons.map_outlined),
                  ),
                  TextField(
                    controller: _cidade,
                    decoration: _dec('Cidade', Icons.location_city_outlined),
                  ),
                  TextField(
                    controller: _estado,
                    decoration: _dec('Estado', Icons.flag_outlined),
                  ),
                  TextField(
                    controller: _cep,
                    decoration: _dec('CEP', Icons.local_post_office_outlined),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 14),
            _secao(
              titulo: 'Identidade visual',
              subtitulo:
                  'Nome, tema e cores compartilhados com o aplicativo Android.',
              children: [
                _linha([
                  TextField(
                    controller: _nomeAplicativo,
                    decoration: _dec(
                      'Nome do aplicativo',
                      Icons.apps_outlined,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _tema,
                    decoration: _dec('Tema', Icons.contrast_outlined),
                    items: const [
                      DropdownMenuItem(
                        value: 'escuro',
                        child: Text('Tema escuro'),
                      ),
                      DropdownMenuItem(
                        value: 'claro',
                        child: Text('Tema claro'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _tema = value);
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                _seletorCor(
                  titulo: 'Cor principal',
                  selecionada: _corPrincipal,
                  opcoes: const [
                    ('Dourado Imperium', 0xFFD6A84B),
                    ('Amarelo', 0xFFFFC107),
                    ('Azul', 0xFF2196F3),
                    ('Azul escuro', 0xFF1565C0),
                    ('Verde', 0xFF4CAF50),
                    ('Vermelho', 0xFFE53935),
                    ('Roxo', 0xFF9C27B0),
                    ('Laranja', 0xFFFF7A00),
                    ('Prata', 0xFFBDBDBD),
                  ],
                  onChanged: (valor) {
                    setState(() => _corPrincipal = valor);
                  },
                ),
                const SizedBox(height: 16),
                _seletorCor(
                  titulo: 'Cor secundária',
                  selecionada: _corSecundaria,
                  opcoes: const [
                    ('Preto', 0xFF0E0E0E),
                    ('Cinza escuro', 0xFF1A1A1A),
                    ('Grafite', 0xFF252525),
                    ('Azul escuro', 0xFF101820),
                    ('Marrom escuro', 0xFF211A14),
                  ],
                  onChanged: (valor) {
                    setState(() => _corSecundaria = valor);
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Color(_corSecundaria),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Color(_corPrincipal).withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Color(_corPrincipal),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _nomeAplicativo.text.trim().isEmpty
                              ? 'Imperium Detailing'
                              : _nomeAplicativo.text.trim(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        _tema == 'claro' ? 'Claro' : 'Escuro',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A identidade é salva no Cloud e aplicada pelo Android no próximo ciclo de sincronização. A interface Web mantém o tema administrativo próprio por enquanto.',
                  style: TextStyle(color: Color(0xFF89939E), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _secao(
              titulo: 'Logo e assinatura',
              subtitulo:
                  'Arquivos privados compartilhados entre Web, Android e documentos da empresa.',
              children: [
                _arquivoVisualCard(
                  titulo: 'Logo da empresa',
                  subtitulo:
                      'Usada na identidade e nos documentos que suportam a logo sincronizada.',
                  bytes: _logoBytes,
                  arquivo: _arquivos['logo'],
                  fallbackIcon: Icons.image_outlined,
                  actions: [
                    OutlinedButton.icon(
                      onPressed: _processandoArquivo
                          ? null
                          : () => _selecionarImagem('logo'),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _logoBytes == null ? 'Enviar logo' : 'Substituir',
                      ),
                    ),
                    if (_logoBytes != null)
                      TextButton.icon(
                        onPressed: _processandoArquivo
                            ? null
                            : () => _removerArquivo('logo'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Remover'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _arquivoVisualCard(
                  titulo: 'Assinatura da empresa',
                  subtitulo:
                      'Pode ser desenhada no navegador ou importada como imagem.',
                  bytes: _assinaturaBytes,
                  arquivo: _arquivos['assinatura_empresa'],
                  fallbackIcon: Icons.draw_outlined,
                  actions: [
                    FilledButton.tonalIcon(
                      onPressed:
                          _processandoArquivo ? null : _desenharAssinatura,
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(
                        _assinaturaBytes == null ? 'Desenhar' : 'Redesenhar',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _processandoArquivo
                          ? null
                          : () => _selecionarImagem('assinatura_empresa'),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Importar imagem'),
                    ),
                    if (_assinaturaBytes != null)
                      TextButton.icon(
                        onPressed: _processandoArquivo
                            ? null
                            : () => _removerArquivo('assinatura_empresa'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Remover'),
                      ),
                  ],
                ),
                if (_processandoArquivo) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _secao(
              titulo: 'Documentos e operação',
              subtitulo:
                  'Regras e textos padrão compartilhados com orçamentos e ordens de serviço.',
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _validadeOrcamento,
                    keyboardType: TextInputType.number,
                    decoration: _dec(
                      'Validade do orçamento (dias)',
                      Icons.event_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _rodapeDocumentos,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _dec(
                    'Rodapé dos documentos',
                    Icons.subject_outlined,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _termosOrcamento,
                  minLines: 3,
                  maxLines: 6,
                  decoration: _dec(
                    'Termos do orçamento',
                    Icons.description_outlined,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _termosOs,
                  minLines: 3,
                  maxLines: 6,
                  decoration: _dec(
                    'Termos da ordem de serviço',
                    Icons.receipt_long_outlined,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _observacaoPadrao,
                  minLines: 2,
                  maxLines: 5,
                  decoration: _dec('Observação padrão', Icons.notes_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _secao(
              titulo: 'Mensagens',
              subtitulo:
                  'Modelos usados em contatos com o cliente. Alterações feitas aqui chegam ao Mobile pelo sync.',
              children: [
                for (final item in <(String, TextEditingController)>[
                  ('Agradecimento pós-serviço', _mensagemAgradecimento),
                  ('Envio de orçamento', _mensagemOrcamento),
                  ('Confirmação', _mensagemConfirmacao),
                  ('Entrega', _mensagemEntrega),
                  ('Cobrança', _mensagemCobranca),
                ]) ...[
                  TextField(
                    controller: item.$2,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(labelText: item.$1),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              color: ImperiumWebTheme.accentStrong.withValues(alpha: 0.06),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sync_rounded,
                      color: ImperiumWebTheme.accentStrong,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Estas configurações ficam no Cloud. O Android compara versões no próximo ciclo de sincronização e aplica a versão remota quando não houver alteração local concorrente.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _snack(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? Colors.red.shade700 : null,
        ),
      );
  }

  static String _texto(dynamic value, {String padrao = ''}) {
    final texto = (value ?? '').toString().trim();
    return texto.isEmpty ? padrao : texto;
  }

  static int _inteiro(dynamic value, {required int padrao}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? padrao;
  }

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}
