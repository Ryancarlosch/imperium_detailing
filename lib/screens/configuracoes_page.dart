import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/configuracao.dart';
import '../repositories/configuracao_repository.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() =>
      _ConfiguracoesPageState();
}

class _ConfiguracoesPageState
    extends State<ConfiguracoesPage> {
  final ConfiguracaoRepository _repository =
  ConfiguracaoRepository();

  final ImagePicker _imagePicker = ImagePicker();

  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  bool _carregando = true;
  bool _salvando = false;

  Configuracao _configuracao =
  Configuracao.padrao();

  final TextEditingController
  _nomeFantasiaController =
  TextEditingController();

  final TextEditingController
  _razaoSocialController =
  TextEditingController();

  final TextEditingController _cnpjController =
  TextEditingController();

  final TextEditingController
  _inscricaoEstadualController =
  TextEditingController();

  final TextEditingController
  _telefoneController =
  TextEditingController();

  final TextEditingController
  _whatsappController =
  TextEditingController();

  final TextEditingController _emailController =
  TextEditingController();

  final TextEditingController _siteController =
  TextEditingController();

  final TextEditingController
  _instagramController =
  TextEditingController();

  final TextEditingController
  _enderecoController =
  TextEditingController();

  final TextEditingController _numeroController =
  TextEditingController();

  final TextEditingController
  _complementoController =
  TextEditingController();

  final TextEditingController _bairroController =
  TextEditingController();

  final TextEditingController _cidadeController =
  TextEditingController();

  final TextEditingController _estadoController =
  TextEditingController();

  final TextEditingController _cepController =
  TextEditingController();

  final TextEditingController
  _nomeAplicativoController =
  TextEditingController();

  final TextEditingController
  _validadeOrcamentoController =
  TextEditingController();

  final TextEditingController
  _rodapeDocumentosController =
  TextEditingController();

  final TextEditingController
  _termosOrcamentoController =
  TextEditingController();

  final TextEditingController
  _termosOrdemServicoController =
  TextEditingController();

  final TextEditingController
  _observacaoPadraoController =
  TextEditingController();

  final TextEditingController
  _mensagemAgradecimentoController =
  TextEditingController();

  final TextEditingController
  _mensagemOrcamentoController =
  TextEditingController();

  final TextEditingController
  _mensagemConfirmacaoController =
  TextEditingController();

  final TextEditingController
  _mensagemEntregaController =
  TextEditingController();

  final TextEditingController
  _mensagemCobrancaController =
  TextEditingController();

  String _temaSelecionado = 'escuro';

  int _corPrincipalSelecionada =
  0xFFD6A84B;

  int _corSecundariaSelecionada =
  0xFF1A1A1A;

  String? _caminhoLogo;

  final List<_OpcaoCor> _coresDisponiveis = const [
    _OpcaoCor(
      nome: 'Dourado Imperium',
      valor: 0xFFD6A84B,
    ),
    _OpcaoCor(
      nome: 'Amarelo',
      valor: 0xFFFFC107,
    ),
    _OpcaoCor(
      nome: 'Azul',
      valor: 0xFF2196F3,
    ),
    _OpcaoCor(
      nome: 'Azul escuro',
      valor: 0xFF1565C0,
    ),
    _OpcaoCor(
      nome: 'Verde',
      valor: 0xFF4CAF50,
    ),
    _OpcaoCor(
      nome: 'Vermelho',
      valor: 0xFFE53935,
    ),
    _OpcaoCor(
      nome: 'Roxo',
      valor: 0xFF9C27B0,
    ),
    _OpcaoCor(
      nome: 'Laranja',
      valor: 0xFFFF7A00,
    ),
    _OpcaoCor(
      nome: 'Prata',
      valor: 0xFFBDBDBD,
    ),
  ];

  final List<_OpcaoCor> _coresSecundarias =
  const [
    _OpcaoCor(
      nome: 'Preto',
      valor: 0xFF0E0E0E,
    ),
    _OpcaoCor(
      nome: 'Cinza escuro',
      valor: 0xFF1A1A1A,
    ),
    _OpcaoCor(
      nome: 'Grafite',
      valor: 0xFF252525,
    ),
    _OpcaoCor(
      nome: 'Azul escuro',
      valor: 0xFF101820,
    ),
    _OpcaoCor(
      nome: 'Marrom escuro',
      valor: 0xFF211A14,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      final configuracao =
      await _repository.obterConfiguracao();

      if (!mounted) {
        return;
      }

      setState(() {
        _configuracao = configuracao;

        _nomeFantasiaController.text =
            configuracao.nomeFantasia;

        _razaoSocialController.text =
            configuracao.razaoSocial;

        _cnpjController.text =
            configuracao.cnpj;

        _inscricaoEstadualController.text =
            configuracao.inscricaoEstadual;

        _telefoneController.text =
            configuracao.telefone;

        _whatsappController.text =
            configuracao.whatsapp;

        _emailController.text =
            configuracao.email;

        _siteController.text =
            configuracao.site;

        _instagramController.text =
            configuracao.instagram;

        _enderecoController.text =
            configuracao.endereco;

        _numeroController.text =
            configuracao.numero;

        _complementoController.text =
            configuracao.complemento;

        _bairroController.text =
            configuracao.bairro;

        _cidadeController.text =
            configuracao.cidade;

        _estadoController.text =
            configuracao.estado;

        _cepController.text =
            configuracao.cep;

        _nomeAplicativoController.text =
            configuracao.nomeAplicativo;

        _validadeOrcamentoController.text =
            configuracao.validadeOrcamentoDias
                .toString();

        _rodapeDocumentosController.text =
            configuracao.rodapeDocumentos;

        _termosOrcamentoController.text =
            configuracao.termosOrcamento;

        _termosOrdemServicoController.text =
            configuracao.termosOrdemServico;

        _observacaoPadraoController.text =
            configuracao.observacaoPadrao;

        _mensagemAgradecimentoController.text =
            configuracao.mensagemAgradecimento;

        _mensagemOrcamentoController.text =
            configuracao.mensagemOrcamento;

        _mensagemConfirmacaoController.text =
            configuracao.mensagemConfirmacao;

        _mensagemEntregaController.text =
            configuracao.mensagemEntrega;

        _mensagemCobrancaController.text =
            configuracao.mensagemCobranca;

        _temaSelecionado =
        configuracao.tema.isEmpty
            ? 'escuro'
            : configuracao.tema;

        _corPrincipalSelecionada =
            configuracao.corPrincipal;

        _corSecundariaSelecionada =
            configuracao.corSecundaria;

        _caminhoLogo =
            configuracao.caminhoLogo;

        _carregando = false;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar as configurações: '
            '$erro',
        erro: true,
      );
    }
  }

  Future<void> _selecionarLogo() async {
    try {
      final imagem = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (imagem == null) {
        return;
      }

      final diretorioAplicativo =
      await getApplicationDocumentsDirectory();

      final pastaLogos = Directory(
        path.join(
          diretorioAplicativo.path,
          'logos',
        ),
      );

      if (!await pastaLogos.exists()) {
        await pastaLogos.create(
          recursive: true,
        );
      }

      final extensao = path.extension(
        imagem.path,
      );

      final nomeArquivo =
          'logo_empresa_${DateTime.now().millisecondsSinceEpoch}'
          '$extensao';

      final novoCaminho = path.join(
        pastaLogos.path,
        nomeArquivo,
      );

      final arquivoCopiado = await File(
        imagem.path,
      ).copy(novoCaminho);

      if (!mounted) {
        return;
      }

      setState(() {
        _caminhoLogo =
            arquivoCopiado.path;
      });
    } catch (erro) {
      _mostrarMensagem(
        'Não foi possível selecionar a logo: $erro',
        erro: true,
      );
    }
  }

  Future<void> _removerLogo() async {
    final caminhoAtual = _caminhoLogo;

    if (caminhoAtual == null ||
        caminhoAtual.trim().isEmpty) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover logo'),
          content: const Text(
            'Deseja remover a logo cadastrada?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    try {
      final arquivo = File(caminhoAtual);

      if (await arquivo.exists()) {
        await arquivo.delete();
      }
    } catch (_) {
      // Mesmo que o arquivo não possa ser apagado,
      // a referência será removida.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _caminhoLogo = null;
    });
  }

  Future<void> _salvarConfiguracoes() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final validade =
        int.tryParse(
          _validadeOrcamentoController.text
              .trim(),
        ) ??
            15;

    setState(() {
      _salvando = true;
    });

    try {
      final configuracaoAtualizada =
      _configuracao.copyWith(
        nomeFantasia:
        _nomeFantasiaController.text,
        razaoSocial:
        _razaoSocialController.text,
        cnpj: _cnpjController.text,
        inscricaoEstadual:
        _inscricaoEstadualController.text,
        telefone:
        _telefoneController.text,
        whatsapp:
        _whatsappController.text,
        email: _emailController.text,
        site: _siteController.text,
        instagram:
        _instagramController.text,
        endereco:
        _enderecoController.text,
        numero: _numeroController.text,
        complemento:
        _complementoController.text,
        bairro: _bairroController.text,
        cidade: _cidadeController.text,
        estado: _estadoController.text,
        cep: _cepController.text,
        caminhoLogo: _caminhoLogo,
        removerLogo: _caminhoLogo == null,
        nomeAplicativo:
        _nomeAplicativoController.text,
        corPrincipal:
        _corPrincipalSelecionada,
        corSecundaria:
        _corSecundariaSelecionada,
        tema: _temaSelecionado,
        validadeOrcamentoDias: validade,
        rodapeDocumentos:
        _rodapeDocumentosController.text,
        termosOrcamento:
        _termosOrcamentoController.text,
        termosOrdemServico:
        _termosOrdemServicoController.text,
        observacaoPadrao:
        _observacaoPadraoController.text,
        mensagemAgradecimento:
        _mensagemAgradecimentoController
            .text,
        mensagemOrcamento:
        _mensagemOrcamentoController.text,
        mensagemConfirmacao:
        _mensagemConfirmacaoController
            .text,
        mensagemEntrega:
        _mensagemEntregaController.text,
        mensagemCobranca:
        _mensagemCobrancaController.text,
      );

      await _repository.salvarConfiguracao(
        configuracaoAtualizada,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _configuracao =
            configuracaoAtualizada;
        _salvando = false;
      });

      _mostrarMensagem(
        'Configurações salvas com sucesso.',
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem(
        'Não foi possível salvar: $erro',
        erro: true,
      );
    }
  }

  Future<void> _restaurarPadrao() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Restaurar configurações',
          ),
          content: const Text(
            'Todos os dados configuráveis serão '
                'restaurados para o padrão. Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Restaurar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      await _repository.restaurarPadrao();
      await _carregarConfiguracoes();

      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Configurações restauradas.',
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível restaurar: $erro',
        erro: true,
      );
    }
  }

  void _mostrarMensagem(
      String mensagem, {
        bool erro = false,
      }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro
              ? Colors.red.shade700
              : Colors.green.shade700,
        ),
      );
  }

  String? _validarCampoObrigatorio(
      String? valor,
      ) {
    if (valor == null ||
        valor.trim().isEmpty) {
      return 'Preencha este campo';
    }

    return null;
  }

  String? _validarEmail(
      String? valor,
      ) {
    final email = valor?.trim() ?? '';

    if (email.isEmpty) {
      return null;
    }

    if (!email.contains('@') ||
        !email.contains('.')) {
      return 'Informe um e-mail válido';
    }

    return null;
  }

  String? _validarValidade(
      String? valor,
      ) {
    final numero = int.tryParse(
      valor?.trim() ?? '',
    );

    if (numero == null ||
        numero <= 0) {
      return 'Informe uma quantidade válida';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        actions: [
          IconButton(
            onPressed: _salvando
                ? null
                : _restaurarPadrao,
            tooltip: 'Restaurar padrão',
            icon: const Icon(
              Icons.restart_alt_rounded,
            ),
          ),
        ],
      ),
      body: _carregando
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : Form(
        key: _formKey,
        child: ListView(
          padding:
          const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            110,
          ),
          children: [
            _CabecalhoConfiguracoes(
              nomeEmpresa:
              _nomeFantasiaController
                  .text
                  .trim()
                  .isEmpty
                  ? 'Imperium Detailing'
                  : _nomeFantasiaController
                  .text
                  .trim(),
              caminhoLogo: _caminhoLogo,
              corPrincipal: Color(
                _corPrincipalSelecionada,
              ),
              onSelecionarLogo:
              _selecionarLogo,
              onRemoverLogo:
              _removerLogo,
            ),
            const SizedBox(height: 18),
            _SecaoConfiguracao(
              titulo: 'Dados da empresa',
              subtitulo:
              'Informações usadas nos PDFs e documentos.',
              icone:
              Icons.business_outlined,
              inicialmenteAberta: true,
              children: [
                _campoTexto(
                  controller:
                  _nomeFantasiaController,
                  label: 'Nome fantasia',
                  icone:
                  Icons.store_outlined,
                  obrigatorio: true,
                ),
                _campoTexto(
                  controller:
                  _razaoSocialController,
                  label: 'Razão social',
                  icone:
                  Icons.apartment_outlined,
                ),
                _campoTexto(
                  controller:
                  _cnpjController,
                  label: 'CNPJ',
                  icone:
                  Icons.badge_outlined,
                  keyboardType:
                  TextInputType.number,
                ),
                _campoTexto(
                  controller:
                  _inscricaoEstadualController,
                  label:
                  'Inscrição Estadual',
                  icone:
                  Icons.numbers_outlined,
                ),
                _campoTexto(
                  controller:
                  _telefoneController,
                  label: 'Telefone',
                  icone:
                  Icons.phone_outlined,
                  keyboardType:
                  TextInputType.phone,
                ),
                _campoTexto(
                  controller:
                  _whatsappController,
                  label: 'WhatsApp',
                  icone:
                  Icons.chat_outlined,
                  keyboardType:
                  TextInputType.phone,
                ),
                _campoTexto(
                  controller:
                  _emailController,
                  label: 'E-mail',
                  icone:
                  Icons.email_outlined,
                  keyboardType:
                  TextInputType
                      .emailAddress,
                  validator:
                  _validarEmail,
                ),
                _campoTexto(
                  controller:
                  _siteController,
                  label: 'Site',
                  icone:
                  Icons.language_outlined,
                  keyboardType:
                  TextInputType.url,
                ),
                _campoTexto(
                  controller:
                  _instagramController,
                  label: 'Instagram',
                  icone:
                  Icons.alternate_email,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SecaoConfiguracao(
              titulo: 'Endereço',
              subtitulo:
              'Endereço completo da empresa.',
              icone:
              Icons.location_on_outlined,
              children: [
                _campoTexto(
                  controller:
                  _enderecoController,
                  label:
                  'Rua ou avenida',
                  icone:
                  Icons.signpost_outlined,
                ),
                Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _campoTexto(
                        controller:
                        _numeroController,
                        label: 'Número',
                        icone:
                        Icons.pin_outlined,
                        keyboardType:
                        TextInputType
                            .number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _campoTexto(
                        controller:
                        _complementoController,
                        label: 'Complemento',
                        icone:
                        Icons.home_work_outlined,
                      ),
                    ),
                  ],
                ),
                _campoTexto(
                  controller:
                  _bairroController,
                  label: 'Bairro',
                  icone:
                  Icons.location_city_outlined,
                ),
                _campoTexto(
                  controller:
                  _cidadeController,
                  label: 'Cidade',
                  icone:
                  Icons.location_city,
                ),
                Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _campoTexto(
                        controller:
                        _estadoController,
                        label: 'Estado',
                        icone:
                        Icons.map_outlined,
                        maxLength: 2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _campoTexto(
                        controller:
                        _cepController,
                        label: 'CEP',
                        icone:
                        Icons.markunread_mailbox_outlined,
                        keyboardType:
                        TextInputType
                            .number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SecaoConfiguracao(
              titulo: 'Aparência',
              subtitulo:
              'Personalize o nome, tema e cores.',
              icone:
              Icons.palette_outlined,
              children: [
                _campoTexto(
                  controller:
                  _nomeAplicativoController,
                  label:
                  'Nome do aplicativo',
                  icone:
                  Icons.apps_outlined,
                  obrigatorio: true,
                ),
                DropdownButtonFormField<
                    String>(
                  initialValue:
                  _temaSelecionado,
                  decoration:
                  const InputDecoration(
                    labelText: 'Tema',
                    prefixIcon: Icon(
                      Icons
                          .brightness_6_outlined,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'escuro',
                      child: Text(
                        'Tema escuro',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'claro',
                      child: Text(
                        'Tema claro',
                      ),
                    ),
                  ],
                  onChanged: (valor) {
                    if (valor == null) {
                      return;
                    }

                    setState(() {
                      _temaSelecionado =
                          valor;
                    });
                  },
                ),
                const SizedBox(height: 14),
                _seletorCor(
                  titulo: 'Cor principal',
                  valorSelecionado:
                  _corPrincipalSelecionada,
                  opcoes:
                  _coresDisponiveis,
                  onChanged: (valor) {
                    setState(() {
                      _corPrincipalSelecionada =
                          valor;
                    });
                  },
                ),
                const SizedBox(height: 14),
                _seletorCor(
                  titulo: 'Cor secundária',
                  valorSelecionado:
                  _corSecundariaSelecionada,
                  opcoes:
                  _coresSecundarias,
                  onChanged: (valor) {
                    setState(() {
                      _corSecundariaSelecionada =
                          valor;
                    });
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                  const EdgeInsets.all(
                    16,
                  ),
                  decoration:
                  BoxDecoration(
                    color: Color(
                      _corSecundariaSelecionada,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      16,
                    ),
                    border: Border.all(
                      color: Color(
                        _corPrincipalSelecionada,
                      ).withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons
                            .auto_awesome_outlined,
                        color: Color(
                          _corPrincipalSelecionada,
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      const Expanded(
                        child: Text(
                          'Prévia das cores selecionadas',
                          style:
                          TextStyle(
                            fontWeight:
                            FontWeight
                                .bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SecaoConfiguracao(
              titulo: 'Documentos',
              subtitulo:
              'Textos usados nos orçamentos, recibos e Ordens de Serviço.',
              icone:
              Icons.description_outlined,
              children: [
                _campoTexto(
                  controller:
                  _validadeOrcamentoController,
                  label:
                  'Validade padrão do orçamento em dias',
                  icone:
                  Icons.event_available_outlined,
                  keyboardType:
                  TextInputType.number,
                  validator:
                  _validarValidade,
                ),
                _campoTexto(
                  controller:
                  _rodapeDocumentosController,
                  label:
                  'Rodapé dos documentos',
                  icone:
                  Icons.vertical_align_bottom,
                  maxLines: 3,
                ),
                _campoTexto(
                  controller:
                  _termosOrcamentoController,
                  label:
                  'Termos do orçamento',
                  icone:
                  Icons.rule_outlined,
                  maxLines: 5,
                ),
                _campoTexto(
                  controller:
                  _termosOrdemServicoController,
                  label:
                  'Termos da Ordem de Serviço',
                  icone:
                  Icons.assignment_outlined,
                  maxLines: 5,
                ),
                _campoTexto(
                  controller:
                  _observacaoPadraoController,
                  label:
                  'Observação padrão',
                  icone:
                  Icons.notes_outlined,
                  maxLines: 4,
                ),
                _campoTexto(
                  controller:
                  _mensagemAgradecimentoController,
                  label:
                  'Mensagem de agradecimento',
                  icone:
                  Icons.favorite_border,
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SecaoConfiguracao(
              titulo: 'Mensagens do WhatsApp',
              subtitulo:
              'Mensagens padrão que poderão ser enviadas aos clientes.',
              icone:
              Icons.chat_outlined,
              children: [
                _campoTexto(
                  controller:
                  _mensagemOrcamentoController,
                  label:
                  'Mensagem de orçamento',
                  icone:
                  Icons.request_quote_outlined,
                  maxLines: 4,
                ),
                _campoTexto(
                  controller:
                  _mensagemConfirmacaoController,
                  label:
                  'Confirmação de agendamento',
                  icone:
                  Icons.event_available,
                  maxLines: 4,
                ),
                _campoTexto(
                  controller:
                  _mensagemEntregaController,
                  label:
                  'Veículo pronto para entrega',
                  icone:
                  Icons.directions_car_outlined,
                  maxLines: 4,
                ),
                _campoTexto(
                  controller:
                  _mensagemCobrancaController,
                  label:
                  'Mensagem de cobrança',
                  icone:
                  Icons.payments_outlined,
                  maxLines: 4,
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _salvando
                  ? null
                  : _salvarConfiguracoes,
              icon: _salvando
                  ? const SizedBox(
                width: 21,
                height: 21,
                child:
                CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
                  : const Icon(
                Icons.save_outlined,
              ),
              label: Text(
                _salvando
                    ? 'Salvando...'
                    : 'Salvar configurações',
              ),
              style:
              FilledButton.styleFrom(
                minimumSize:
                const Size.fromHeight(
                  54,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _carregando
          ? null
          : FloatingActionButton.extended(
        onPressed: _salvando
            ? null
            : _salvarConfiguracoes,
        icon: const Icon(
          Icons.save_outlined,
        ),
        label: const Text('Salvar'),
      ),
    );
  }

  Widget _campoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icone,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    bool obrigatorio = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 14,
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        textCapitalization:
        TextCapitalization.sentences,
        validator: validator ??
            (obrigatorio
                ? _validarCampoObrigatorio
                : null),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icone),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  Widget _seletorCor({
    required String titulo,
    required int valorSelecionado,
    required List<_OpcaoCor> opcoes,
    required ValueChanged<int> onChanged,
  }) {
    _OpcaoCor opcaoAtual =
        opcoes.first;

    for (final opcao in opcoes) {
      if (opcao.valor ==
          valorSelecionado) {
        opcaoAtual = opcao;
        break;
      }
    }

    return DropdownButtonFormField<int>(
      initialValue: opcaoAtual.valor,
      decoration: InputDecoration(
        labelText: titulo,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Color(
                opcaoAtual.valor,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white30,
              ),
            ),
          ),
        ),
      ),
      items: opcoes.map((opcao) {
        return DropdownMenuItem<int>(
          value: opcao.valor,
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Color(opcao.valor),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white30,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(opcao.nome),
            ],
          ),
        );
      }).toList(),
      onChanged: (valor) {
        if (valor != null) {
          onChanged(valor);
        }
      },
    );
  }

  @override
  void dispose() {
    _nomeFantasiaController.dispose();
    _razaoSocialController.dispose();
    _cnpjController.dispose();
    _inscricaoEstadualController.dispose();
    _telefoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _siteController.dispose();
    _instagramController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _cepController.dispose();
    _nomeAplicativoController.dispose();
    _validadeOrcamentoController.dispose();
    _rodapeDocumentosController.dispose();
    _termosOrcamentoController.dispose();
    _termosOrdemServicoController.dispose();
    _observacaoPadraoController.dispose();
    _mensagemAgradecimentoController.dispose();
    _mensagemOrcamentoController.dispose();
    _mensagemConfirmacaoController.dispose();
    _mensagemEntregaController.dispose();
    _mensagemCobrancaController.dispose();

    super.dispose();
  }
}

class _CabecalhoConfiguracoes
    extends StatelessWidget {
  const _CabecalhoConfiguracoes({
    required this.nomeEmpresa,
    required this.caminhoLogo,
    required this.corPrincipal,
    required this.onSelecionarLogo,
    required this.onRemoverLogo,
  });

  final String nomeEmpresa;
  final String? caminhoLogo;
  final Color corPrincipal;
  final VoidCallback onSelecionarLogo;
  final VoidCallback onRemoverLogo;

  @override
  Widget build(BuildContext context) {
    final possuiLogo = caminhoLogo != null &&
        caminhoLogo!.trim().isNotEmpty &&
        File(caminhoLogo!).existsSync();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: corPrincipal.withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 78,
            height: 78,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: corPrincipal.withValues(
                alpha: 0.12,
              ),
              borderRadius:
              BorderRadius.circular(18),
              border: Border.all(
                color: corPrincipal.withValues(
                  alpha: 0.5,
                ),
              ),
            ),
            child: possuiLogo
                ? Image.file(
              File(caminhoLogo!),
              fit: BoxFit.cover,
            )
                : Icon(
              Icons.business_outlined,
              size: 38,
              color: corPrincipal,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  nomeEmpresa,
                  maxLines: 2,
                  overflow:
                  TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Identidade da empresa',
                  style: TextStyle(
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                      onSelecionarLogo,
                      icon: const Icon(
                        Icons.image_outlined,
                        size: 18,
                      ),
                      label: Text(
                        possuiLogo
                            ? 'Trocar'
                            : 'Adicionar logo',
                      ),
                    ),
                    if (possuiLogo)
                      IconButton(
                        onPressed: onRemoverLogo,
                        tooltip: 'Remover logo',
                        icon: const Icon(
                          Icons.delete_outline,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecaoConfiguracao
    extends StatelessWidget {
  const _SecaoConfiguracao({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.children,
    this.inicialmenteAberta = false,
  });

  final String titulo;
  final String subtitulo;
  final IconData icone;
  final List<Widget> children;
  final bool inicialmenteAberta;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded:
        inicialmenteAberta,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFD6A84B)
                .withValues(alpha: 0.12),
            borderRadius:
            BorderRadius.circular(13),
          ),
          child: Icon(
            icone,
            color: const Color(0xFFD6A84B),
          ),
        ),
        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitulo,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
          ),
        ),
        childrenPadding:
        const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          4,
        ),
        children: children,
      ),
    );
  }
}

class _OpcaoCor {
  const _OpcaoCor({
    required this.nome,
    required this.valor,
  });

  final String nome;
  final int valor;
}