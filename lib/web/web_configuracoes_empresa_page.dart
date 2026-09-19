import 'package:flutter/material.dart';

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

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  Map<String, dynamic> _atual = const {};

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

  static String _textoErro(Object erro) {
    return erro
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}
