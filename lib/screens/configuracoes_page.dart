import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/configuracao.dart';
import '../repositories/configuracao_repository.dart';
import '../services/backup_service.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final ConfiguracaoRepository _repository = ConfiguracaoRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _carregando = true;
  bool _salvando = false;
  bool _processandoBackup = false;

  Configuracao _configuracao = Configuracao.padrao();

  final TextEditingController _nomeFantasiaController = TextEditingController();
  final TextEditingController _razaoSocialController = TextEditingController();
  final TextEditingController _cnpjController = TextEditingController();
  final TextEditingController _inscricaoEstadualController =
      TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _siteController = TextEditingController();
  final TextEditingController _instagramController = TextEditingController();
  final TextEditingController _facebookController = TextEditingController();
  final TextEditingController _enderecoController = TextEditingController();
  final TextEditingController _numeroController = TextEditingController();
  final TextEditingController _complementoController = TextEditingController();
  final TextEditingController _bairroController = TextEditingController();
  final TextEditingController _cidadeController = TextEditingController();
  final TextEditingController _estadoController = TextEditingController();
  final TextEditingController _cepController = TextEditingController();

  final TextEditingController _nomeAplicativoController =
      TextEditingController();
  final TextEditingController _validadeOrcamentoController =
      TextEditingController();
  final TextEditingController _rodapeDocumentosController =
      TextEditingController();
  final TextEditingController _termosOrcamentoController =
      TextEditingController();
  final TextEditingController _termosOrdemServicoController =
      TextEditingController();
  final TextEditingController _observacaoPadraoController =
      TextEditingController();
  final TextEditingController _mensagemAgradecimentoController =
      TextEditingController();
  final TextEditingController _mensagemOrcamentoController =
      TextEditingController();
  final TextEditingController _mensagemConfirmacaoController =
      TextEditingController();
  final TextEditingController _mensagemEntregaController =
      TextEditingController();
  final TextEditingController _mensagemCobrancaController =
      TextEditingController();

  String _temaSelecionado = 'escuro';
  int _corPrincipalSelecionada = 0xFFD6A84B;
  int _corSecundariaSelecionada = 0xFF1A1A1A;

  String? _caminhoLogo;
  String? _caminhoAssinaturaEmpresa;

  final List<_OpcaoCor> _coresDisponiveis = const [
    _OpcaoCor(nome: 'Dourado Imperium', valor: 0xFFD6A84B),
    _OpcaoCor(nome: 'Amarelo', valor: 0xFFFFC107),
    _OpcaoCor(nome: 'Azul', valor: 0xFF2196F3),
    _OpcaoCor(nome: 'Azul escuro', valor: 0xFF1565C0),
    _OpcaoCor(nome: 'Verde', valor: 0xFF4CAF50),
    _OpcaoCor(nome: 'Vermelho', valor: 0xFFE53935),
    _OpcaoCor(nome: 'Roxo', valor: 0xFF9C27B0),
    _OpcaoCor(nome: 'Laranja', valor: 0xFFFF7A00),
    _OpcaoCor(nome: 'Prata', valor: 0xFFBDBDBD),
  ];

  final List<_OpcaoCor> _coresSecundarias = const [
    _OpcaoCor(nome: 'Preto', valor: 0xFF0E0E0E),
    _OpcaoCor(nome: 'Cinza escuro', valor: 0xFF1A1A1A),
    _OpcaoCor(nome: 'Grafite', valor: 0xFF252525),
    _OpcaoCor(nome: 'Azul escuro', valor: 0xFF101820),
    _OpcaoCor(nome: 'Marrom escuro', valor: 0xFF211A14),
  ];

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  bool _arquivoExiste(String? caminho) {
    if (caminho == null || caminho.trim().isEmpty) {
      return false;
    }

    try {
      return File(caminho).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _carregarConfiguracoes() async {
    try {
      final configuracao = await _repository.obterConfiguracao();

      if (!mounted) {
        return;
      }

      var caminhoLogo = configuracao.caminhoLogo;
      var caminhoAssinatura = configuracao.caminhoAssinaturaEmpresa;
      var removeuInvalidos = false;

      if (!_arquivoExiste(caminhoLogo)) {
        caminhoLogo = null;
        removeuInvalidos = true;
      }

      if (!_arquivoExiste(caminhoAssinatura)) {
        caminhoAssinatura = null;
        removeuInvalidos = true;
      }

      final configuracaoAjustada = configuracao.copyWith(
        caminhoLogo: caminhoLogo,
        removerLogo: caminhoLogo == null,
        caminhoAssinaturaEmpresa: caminhoAssinatura,
        removerAssinaturaEmpresa: caminhoAssinatura == null,
      );

      if (removeuInvalidos) {
        await _repository.salvarConfiguracao(configuracaoAjustada);
      }

      setState(() {
        _configuracao = configuracaoAjustada;

        _nomeFantasiaController.text = configuracaoAjustada.nomeFantasia;
        _razaoSocialController.text = configuracaoAjustada.razaoSocial;
        _cnpjController.text = configuracaoAjustada.cnpj;
        _inscricaoEstadualController.text =
            configuracaoAjustada.inscricaoEstadual;
        _telefoneController.text = configuracaoAjustada.telefone;
        _whatsappController.text = configuracaoAjustada.whatsapp;
        _emailController.text = configuracaoAjustada.email;
        _siteController.text = configuracaoAjustada.site;
        _instagramController.text = configuracaoAjustada.instagram;
        _facebookController.text = configuracaoAjustada.facebook;

        _enderecoController.text = configuracaoAjustada.endereco;
        _numeroController.text = configuracaoAjustada.numero;
        _complementoController.text = configuracaoAjustada.complemento;
        _bairroController.text = configuracaoAjustada.bairro;
        _cidadeController.text = configuracaoAjustada.cidade;
        _estadoController.text = configuracaoAjustada.estado;
        _cepController.text = configuracaoAjustada.cep;

        _nomeAplicativoController.text = configuracaoAjustada.nomeAplicativo;
        _validadeOrcamentoController.text = configuracaoAjustada
            .validadeOrcamentoDias
            .toString();
        _rodapeDocumentosController.text =
            configuracaoAjustada.rodapeDocumentos;
        _termosOrcamentoController.text = configuracaoAjustada.termosOrcamento;
        _termosOrdemServicoController.text =
            configuracaoAjustada.termosOrdemServico;
        _observacaoPadraoController.text =
            configuracaoAjustada.observacaoPadrao;
        _mensagemAgradecimentoController.text =
            configuracaoAjustada.mensagemAgradecimento;
        _mensagemOrcamentoController.text =
            configuracaoAjustada.mensagemOrcamento;
        _mensagemConfirmacaoController.text =
            configuracaoAjustada.mensagemConfirmacao;
        _mensagemEntregaController.text = configuracaoAjustada.mensagemEntrega;
        _mensagemCobrancaController.text =
            configuracaoAjustada.mensagemCobranca;

        _temaSelecionado = configuracaoAjustada.tema.isEmpty
            ? 'escuro'
            : configuracaoAjustada.tema;
        _corPrincipalSelecionada = configuracaoAjustada.corPrincipal;
        _corSecundariaSelecionada = configuracaoAjustada.corSecundaria;

        _caminhoLogo = configuracaoAjustada.caminhoLogo;
        _caminhoAssinaturaEmpresa =
            configuracaoAjustada.caminhoAssinaturaEmpresa;

        _carregando = false;
      });

      if (removeuInvalidos) {
        _mostrarMensagem(
          'Arquivos inválidos de logo/assinatura foram removidos automaticamente.',
        );
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem(
        'Não foi possível carregar as configurações: $erro',
        erro: true,
      );
    }
  }

  Future<void> _selecionarLogo() async {
    await _selecionarImagemConfiguracao(
      pastaNome: 'logos',
      prefixoArquivo: 'logo_empresa',
      aoAtualizar: (novo) {
        _caminhoLogo = novo;
      },
      sucesso: 'Logo atualizada com sucesso.',
      erro: 'Não foi possível selecionar a logo.',
    );
  }

  Future<void> _selecionarAssinaturaEmpresa() async {
    await _selecionarImagemConfiguracao(
      pastaNome: 'assinaturas_empresa',
      prefixoArquivo: 'assinatura_empresa',
      aoAtualizar: (novo) {
        _caminhoAssinaturaEmpresa = novo;
      },
      sucesso: 'Assinatura da empresa atualizada com sucesso.',
      erro: 'Não foi possível selecionar a assinatura da empresa.',
    );
  }

  Future<void> _selecionarImagemConfiguracao({
    required String pastaNome,
    required String prefixoArquivo,
    required ValueChanged<String?> aoAtualizar,
    required String sucesso,
    required String erro,
  }) async {
    try {
      final imagem = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (imagem == null) {
        return;
      }

      final diretorio = await getApplicationDocumentsDirectory();
      final pasta = Directory(path.join(diretorio.path, pastaNome));

      if (!await pasta.exists()) {
        await pasta.create(recursive: true);
      }

      final extensao = path.extension(imagem.path);
      final nomeArquivo =
          '${prefixoArquivo}_${DateTime.now().millisecondsSinceEpoch}$extensao';
      final novoCaminho = path.join(pasta.path, nomeArquivo);
      final arquivoCopiado = await File(imagem.path).copy(novoCaminho);

      if (!mounted) {
        return;
      }

      setState(() {
        aoAtualizar(arquivoCopiado.path);
      });

      await _salvarConfiguracoes(silencioso: true);
      _mostrarMensagem(sucesso);
    } catch (ex) {
      _mostrarMensagem('$erro $ex', erro: true);
    }
  }

  Future<void> _removerLogo() async {
    await _removerImagemConfiguracao(
      titulo: 'Remover logo',
      mensagem: 'Deseja remover a logo cadastrada?',
      caminhoAtual: _caminhoLogo,
      aoAtualizar: () {
        _caminhoLogo = null;
      },
      sucesso: 'Logo removida com sucesso.',
    );
  }

  Future<void> _removerAssinaturaEmpresa() async {
    await _removerImagemConfiguracao(
      titulo: 'Remover assinatura',
      mensagem: 'Deseja remover a assinatura da empresa?',
      caminhoAtual: _caminhoAssinaturaEmpresa,
      aoAtualizar: () {
        _caminhoAssinaturaEmpresa = null;
      },
      sucesso: 'Assinatura da empresa removida com sucesso.',
    );
  }

  Future<void> _removerImagemConfiguracao({
    required String titulo,
    required String mensagem,
    required String? caminhoAtual,
    required VoidCallback aoAtualizar,
    required String sucesso,
  }) async {
    if (caminhoAtual == null || caminhoAtual.trim().isEmpty) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(titulo),
          content: Text(mensagem),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
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
      // Continua removendo a referência mesmo em falha de exclusão física.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      aoAtualizar();
    });

    await _salvarConfiguracoes(silencioso: true);
    _mostrarMensagem(sucesso);
  }

  Future<void> _salvarConfiguracoes({bool silencioso = false}) async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final validade =
        int.tryParse(_validadeOrcamentoController.text.trim()) ?? 15;

    setState(() {
      _salvando = true;
    });

    try {
      final configuracaoAtualizada = _configuracao.copyWith(
        nomeFantasia: _nomeFantasiaController.text,
        razaoSocial: _razaoSocialController.text,
        cnpj: _cnpjController.text,
        inscricaoEstadual: _inscricaoEstadualController.text,
        telefone: _telefoneController.text,
        whatsapp: _whatsappController.text,
        email: _emailController.text,
        site: _siteController.text,
        instagram: _instagramController.text,
        facebook: _facebookController.text,
        endereco: _enderecoController.text,
        numero: _numeroController.text,
        complemento: _complementoController.text,
        bairro: _bairroController.text,
        cidade: _cidadeController.text,
        estado: _estadoController.text.toUpperCase(),
        cep: _cepController.text,
        caminhoLogo: _arquivoExiste(_caminhoLogo) ? _caminhoLogo : null,
        removerLogo: !_arquivoExiste(_caminhoLogo),
        caminhoAssinaturaEmpresa: _arquivoExiste(_caminhoAssinaturaEmpresa)
            ? _caminhoAssinaturaEmpresa
            : null,
        removerAssinaturaEmpresa: !_arquivoExiste(_caminhoAssinaturaEmpresa),
        nomeAplicativo: _nomeAplicativoController.text,
        corPrincipal: _corPrincipalSelecionada,
        corSecundaria: _corSecundariaSelecionada,
        tema: _temaSelecionado,
        validadeOrcamentoDias: validade,
        rodapeDocumentos: _rodapeDocumentosController.text,
        termosOrcamento: _termosOrcamentoController.text,
        termosOrdemServico: _termosOrdemServicoController.text,
        observacaoPadrao: _observacaoPadraoController.text,
        mensagemAgradecimento: _mensagemAgradecimentoController.text,
        mensagemOrcamento: _mensagemOrcamentoController.text,
        mensagemConfirmacao: _mensagemConfirmacaoController.text,
        mensagemEntrega: _mensagemEntregaController.text,
        mensagemCobranca: _mensagemCobrancaController.text,
      );

      await _repository.salvarConfiguracao(configuracaoAtualizada);

      if (!mounted) {
        return;
      }

      setState(() {
        _configuracao = configuracaoAtualizada;
        _salvando = false;
      });

      if (!silencioso) {
        _mostrarMensagem('Configurações salvas com sucesso.');
      }
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _salvando = false;
      });

      _mostrarMensagem('Não foi possível salvar: $erro', erro: true);
    }
  }

  Future<void> _restaurarPadrao() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Restaurar configurações'),
          content: const Text(
            'Todos os dados configuráveis serão restaurados para o padrão. Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
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

      _mostrarMensagem('Configurações restauradas.');
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
      });

      _mostrarMensagem('Não foi possível restaurar: $erro', erro: true);
    }
  }

  Future<void> _criarBackup() async {
    if (_processandoBackup) {
      return;
    }

    setState(() {
      _processandoBackup = true;
    });

    try {
      final resumo = await BackupService.instance.criarBackup();
      final configuracaoAtualizada = _configuracao.copyWith(
        ultimoBackupEm: resumo.dataCriacao.toIso8601String(),
        ultimoBackupCaminho: resumo.caminhoArquivo,
        ultimoBackupTamanhoBytes: resumo.tamanhoBytes,
      );

      await _repository.salvarConfiguracao(configuracaoAtualizada);

      if (!mounted) {
        return;
      }

      setState(() {
        _configuracao = configuracaoAtualizada;
      });

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(resumo.caminhoArquivo)],
          text:
              'Backup do Imperium Detailing criado em ${_formatarDataIso(resumo.dataCriacao.toIso8601String())}.',
        ),
      );

      final mensagem = resumo.avisos.isEmpty
          ? 'Backup criado com sucesso.'
          : 'Backup criado com sucesso, com ${resumo.avisos.length} aviso(s) de arquivos ausentes.';

      _mostrarMensagem(mensagem);
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem('Não foi possível criar o backup: $erro', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          _processandoBackup = false;
        });
      }
    }
  }

  Future<void> _restaurarBackup() async {
    if (_processandoBackup) {
      return;
    }

    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
      dialogTitle: 'Selecionar backup do Imperium Detailing',
    );

    final caminhoArquivo = resultado?.files.single.path;
    if (caminhoArquivo == null || caminhoArquivo.trim().isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Restaurar backup'),
          content: const Text(
            'Os dados atuais serão substituídos pelo conteúdo do backup selecionado. '
            'O aplicativo criará uma cópia de segurança antes de aplicar a restauração.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
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
      _processandoBackup = true;
    });

    try {
      final resumo = await BackupService.instance.restaurarBackup(
        caminhoArquivo,
      );
      await _carregarConfiguracoes();

      if (!mounted) {
        return;
      }

      final mensagem = resumo.avisos.isEmpty
          ? 'Backup restaurado com sucesso. Reinicie o aplicativo se algo ainda não atualizar.'
          : 'Backup restaurado com sucesso. Reinicie o aplicativo se algo ainda não atualizar. '
                'Alguns arquivos não foram encontrados no backup.';

      _mostrarMensagem(mensagem);
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem(
        'Não foi possível restaurar o backup: $erro',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _processandoBackup = false;
        });
      }
    }
  }

  String _formatarDataIso(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Nunca';
    }

    final data = DateTime.tryParse(valor);
    if (data == null) {
      return valor;
    }

    return DateFormat('dd/MM/yyyy HH:mm').format(data.toLocal());
  }

  String _formatarTamanhoBackup(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }

    const unidades = ['B', 'KB', 'MB', 'GB'];
    var valor = bytes.toDouble();
    var indice = 0;

    while (valor >= 1024 && indice < unidades.length - 1) {
      valor /= 1024;
      indice++;
    }

    return '${valor.toStringAsFixed(valor >= 10 || indice == 0 ? 0 : 1)} ${unidades[indice]}';
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro
              ? const Color(0xFFB00020)
              : const Color(0xFF1B5E20),
        ),
      );
  }

  String? _validarCampoObrigatorio(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Preencha este campo';
    }

    return null;
  }

  String? _validarEmail(String? valor) {
    final email = valor?.trim() ?? '';

    if (email.isEmpty) {
      return null;
    }

    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (!regex.hasMatch(email)) {
      return 'Informe um e-mail válido';
    }

    return null;
  }

  String? _validarValidade(String? valor) {
    final numero = int.tryParse(valor?.trim() ?? '');

    if (numero == null || numero <= 0) {
      return 'Informe uma quantidade válida';
    }

    return null;
  }

  String? _validarTelefone(String? valor) {
    final texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    final numeros = texto.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length == 10 || numeros.length == 11) {
      return null;
    }

    if (numeros.startsWith('55') &&
        (numeros.length == 12 || numeros.length == 13)) {
      return null;
    }

    return 'Informe telefone com DDD';
  }

  String? _validarWhatsApp(String? valor) {
    final texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    final numeros = texto.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length == 10 || numeros.length == 11) {
      return null;
    }

    if (numeros.startsWith('55') &&
        (numeros.length == 12 || numeros.length == 13)) {
      return null;
    }

    return 'Informe WhatsApp válido com DDD';
  }

  String? _validarCep(String? valor) {
    final texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    final numeros = texto.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length != 8) {
      return 'CEP deve ter 8 dígitos';
    }

    return null;
  }

  String? _validarCnpj(String? valor) {
    final texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    final cnpj = texto.replaceAll(RegExp(r'[^0-9]'), '');

    if (cnpj.length != 14) {
      return 'CNPJ deve ter 14 dígitos';
    }

    if (RegExp(r'^(\d)\1{13}$').hasMatch(cnpj)) {
      return 'CNPJ inválido';
    }

    final digito1 = _calcularDigitoCnpj(cnpj.substring(0, 12));
    final digito2 = _calcularDigitoCnpj(
      cnpj.substring(0, 12) + digito1.toString(),
    );

    if (cnpj != '${cnpj.substring(0, 12)}$digito1$digito2') {
      return 'CNPJ inválido';
    }

    return null;
  }

  int _calcularDigitoCnpj(String base) {
    final pesos = base.length == 12
        ? <int>[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        : <int>[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

    var soma = 0;

    for (var i = 0; i < base.length; i++) {
      soma += int.parse(base[i]) * pesos[i];
    }

    final resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações da Empresa'),
        actions: [
          IconButton(
            onPressed: _salvando ? null : _restaurarPadrao,
            tooltip: 'Restaurar padrão',
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0D0D0D), Color(0xFF151515)],
                ),
              ),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
                  children: [
                    _CabecalhoConfiguracoes(
                      nomeEmpresa: _nomeFantasiaController.text.trim().isEmpty
                          ? 'Imperium Detailing'
                          : _nomeFantasiaController.text.trim(),
                      caminhoLogo: _caminhoLogo,
                      caminhoAssinaturaEmpresa: _caminhoAssinaturaEmpresa,
                      onSelecionarLogo: _selecionarLogo,
                      onRemoverLogo: _removerLogo,
                      onSelecionarAssinaturaEmpresa:
                          _selecionarAssinaturaEmpresa,
                      onRemoverAssinaturaEmpresa: _removerAssinaturaEmpresa,
                    ),
                    const SizedBox(height: 16),
                    _SecaoConfiguracao(
                      titulo: 'Dados da empresa',
                      subtitulo:
                          'Nome da empresa, nome fantasia, documentos e canais públicos.',
                      icone: Icons.business_outlined,
                      inicialmenteAberta: true,
                      children: [
                        _campoTexto(
                          controller: _razaoSocialController,
                          label: 'Nome da empresa (razão social)',
                          icone: Icons.apartment_outlined,
                          obrigatorio: true,
                        ),
                        _campoTexto(
                          controller: _nomeFantasiaController,
                          label: 'Nome fantasia',
                          icone: Icons.store_outlined,
                          obrigatorio: true,
                        ),
                        _campoTexto(
                          controller: _cnpjController,
                          label: 'CNPJ',
                          icone: Icons.badge_outlined,
                          keyboardType: TextInputType.number,
                          validator: _validarCnpj,
                        ),
                        _campoTexto(
                          controller: _inscricaoEstadualController,
                          label: 'Inscrição Estadual',
                          icone: Icons.numbers_outlined,
                        ),
                        _campoTexto(
                          controller: _telefoneController,
                          label: 'Telefone',
                          icone: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          validator: _validarTelefone,
                        ),
                        _campoTexto(
                          controller: _whatsappController,
                          label: 'WhatsApp',
                          icone: Icons.chat_outlined,
                          keyboardType: TextInputType.phone,
                          validator: _validarWhatsApp,
                        ),
                        _campoTexto(
                          controller: _emailController,
                          label: 'E-mail',
                          icone: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _validarEmail,
                        ),
                        _campoTexto(
                          controller: _siteController,
                          label: 'Site',
                          icone: Icons.language_outlined,
                          keyboardType: TextInputType.url,
                        ),
                        _campoTexto(
                          controller: _instagramController,
                          label: 'Instagram',
                          icone: Icons.alternate_email,
                        ),
                        _campoTexto(
                          controller: _facebookController,
                          label: 'Facebook',
                          icone: Icons.facebook,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SecaoConfiguracao(
                      titulo: 'Endereço',
                      subtitulo: 'Endereço completo da empresa.',
                      icone: Icons.location_on_outlined,
                      children: [
                        _campoTexto(
                          controller: _enderecoController,
                          label: 'Rua ou avenida',
                          icone: Icons.signpost_outlined,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _campoTexto(
                                controller: _numeroController,
                                label: 'Número',
                                icone: Icons.pin_outlined,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _campoTexto(
                                controller: _complementoController,
                                label: 'Complemento',
                                icone: Icons.home_work_outlined,
                              ),
                            ),
                          ],
                        ),
                        _campoTexto(
                          controller: _bairroController,
                          label: 'Bairro',
                          icone: Icons.location_city_outlined,
                        ),
                        _campoTexto(
                          controller: _cidadeController,
                          label: 'Cidade',
                          icone: Icons.location_city,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _campoTexto(
                                controller: _estadoController,
                                label: 'Estado',
                                icone: Icons.map_outlined,
                                maxLength: 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: _campoTexto(
                                controller: _cepController,
                                label: 'CEP',
                                icone: Icons.markunread_mailbox_outlined,
                                keyboardType: TextInputType.number,
                                validator: _validarCep,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SecaoConfiguracao(
                      titulo: 'Aparência',
                      subtitulo: 'Personalize nome, tema e cores do sistema.',
                      icone: Icons.palette_outlined,
                      children: [
                        _campoTexto(
                          controller: _nomeAplicativoController,
                          label: 'Nome do aplicativo',
                          icone: Icons.apps_outlined,
                          obrigatorio: true,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _temaSelecionado,
                          decoration: const InputDecoration(
                            labelText: 'Tema',
                            prefixIcon: Icon(Icons.brightness_6_outlined),
                          ),
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
                          onChanged: (valor) {
                            if (valor == null) {
                              return;
                            }

                            setState(() {
                              _temaSelecionado = valor;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        _seletorCor(
                          titulo: 'Cor principal',
                          valorSelecionado: _corPrincipalSelecionada,
                          opcoes: _coresDisponiveis,
                          onChanged: (valor) {
                            setState(() {
                              _corPrincipalSelecionada = valor;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        _seletorCor(
                          titulo: 'Cor secundária',
                          valorSelecionado: _corSecundariaSelecionada,
                          opcoes: _coresSecundarias,
                          onChanged: (valor) {
                            setState(() {
                              _corSecundariaSelecionada = valor;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Color(_corSecundariaSelecionada),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Color(
                                _corPrincipalSelecionada,
                              ).withValues(alpha: 0.7),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_outlined,
                                color: Color(_corPrincipalSelecionada),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Prévia das cores selecionadas',
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                          'Textos usados nos orçamentos, recibos e ordens de serviço.',
                      icone: Icons.description_outlined,
                      children: [
                        _campoTexto(
                          controller: _validadeOrcamentoController,
                          label: 'Validade padrão do orçamento em dias',
                          icone: Icons.event_available_outlined,
                          keyboardType: TextInputType.number,
                          validator: _validarValidade,
                        ),
                        _campoTexto(
                          controller: _rodapeDocumentosController,
                          label: 'Rodapé padrão dos PDFs',
                          icone: Icons.vertical_align_bottom,
                          maxLines: 3,
                        ),
                        _campoTexto(
                          controller: _termosOrcamentoController,
                          label: 'Termos do orçamento',
                          icone: Icons.rule_outlined,
                          maxLines: 5,
                        ),
                        _campoTexto(
                          controller: _termosOrdemServicoController,
                          label: 'Termos da Ordem de Serviço',
                          icone: Icons.assignment_outlined,
                          maxLines: 5,
                        ),
                        _campoTexto(
                          controller: _observacaoPadraoController,
                          label: 'Observação padrão',
                          icone: Icons.notes_outlined,
                          maxLines: 4,
                        ),
                        _campoTexto(
                          controller: _mensagemAgradecimentoController,
                          label: 'Mensagem de agradecimento',
                          icone: Icons.favorite_border,
                          maxLines: 3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SecaoConfiguracao(
                      titulo: 'Mensagens do WhatsApp',
                      subtitulo: 'Modelos padrão para envio aos clientes.',
                      icone: Icons.chat_outlined,
                      children: [
                        _campoTexto(
                          controller: _mensagemOrcamentoController,
                          label: 'Mensagem de orçamento',
                          icone: Icons.request_quote_outlined,
                          maxLines: 4,
                        ),
                        _campoTexto(
                          controller: _mensagemConfirmacaoController,
                          label: 'Confirmação de agendamento',
                          icone: Icons.event_available,
                          maxLines: 4,
                        ),
                        _campoTexto(
                          controller: _mensagemEntregaController,
                          label: 'Veículo pronto para entrega',
                          icone: Icons.directions_car_outlined,
                          maxLines: 4,
                        ),
                        _campoTexto(
                          controller: _mensagemCobrancaController,
                          label: 'Mensagem de cobrança',
                          icone: Icons.payments_outlined,
                          maxLines: 4,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SecaoConfiguracao(
                      titulo: 'Backup e restauração',
                      subtitulo:
                          'Crie um backup local compartilhável ou restaure um arquivo válido com segurança.',
                      icone: Icons.backup_outlined,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFFD6A84B,
                              ).withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Text(
                            'Os dados atuais serão substituídos na restauração. O aplicativo cria automaticamente uma cópia de segurança antes de aplicar o backup selecionado.',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: _processandoBackup
                                  ? null
                                  : _criarBackup,
                              icon: _processandoBackup
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF101010),
                                      ),
                                    )
                                  : const Icon(Icons.backup_outlined),
                              label: Text(
                                _processandoBackup
                                    ? 'Processando...'
                                    : 'Criar backup',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFD6A84B),
                                foregroundColor: const Color(0xFF101010),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _processandoBackup
                                  ? null
                                  : _restaurarBackup,
                              icon: const Icon(Icons.restore_outlined),
                              label: const Text('Restaurar backup'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _BackupInfoCard(
                                titulo: 'Último backup',
                                valor: _configuracao.possuiUltimoBackup
                                    ? _formatarDataIso(
                                        _configuracao.ultimoBackupEm,
                                      )
                                    : 'Nenhum backup registrado',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _BackupInfoCard(
                                titulo: 'Tamanho',
                                valor: _configuracao.possuiUltimoBackup
                                    ? _formatarTamanhoBackup(
                                        _configuracao.ultimoBackupTamanhoBytes,
                                      )
                                    : '—',
                              ),
                            ),
                          ],
                        ),
                        if (_configuracao.ultimoBackupCaminho != null &&
                            _configuracao.ultimoBackupCaminho!
                                .trim()
                                .isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            _configuracao.ultimoBackupCaminho!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _salvando ? null : _salvarConfiguracoes,
                      icon: _salvando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _salvando ? 'Salvando...' : 'Salvar configurações',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD6A84B),
                        foregroundColor: const Color(0xFF101010),
                        minimumSize: const Size.fromHeight(54),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _carregando
          ? null
          : FloatingActionButton.extended(
              onPressed: _salvando ? null : _salvarConfiguracoes,
              backgroundColor: const Color(0xFFD6A84B),
              foregroundColor: const Color(0xFF101010),
              icon: const Icon(Icons.save_outlined),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        textCapitalization: maxLines > 1
            ? TextCapitalization.sentences
            : TextCapitalization.words,
        validator: validator ?? (obrigatorio ? _validarCampoObrigatorio : null),
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
    var opcaoAtual = opcoes.first;

    for (final opcao in opcoes) {
      if (opcao.valor == valorSelecionado) {
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
              color: Color(opcaoAtual.valor),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
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
                  border: Border.all(color: Colors.white30),
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
    _facebookController.dispose();

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

class _CabecalhoConfiguracoes extends StatelessWidget {
  const _CabecalhoConfiguracoes({
    required this.nomeEmpresa,
    required this.caminhoLogo,
    required this.caminhoAssinaturaEmpresa,
    required this.onSelecionarLogo,
    required this.onRemoverLogo,
    required this.onSelecionarAssinaturaEmpresa,
    required this.onRemoverAssinaturaEmpresa,
  });

  final String nomeEmpresa;
  final String? caminhoLogo;
  final String? caminhoAssinaturaEmpresa;
  final VoidCallback onSelecionarLogo;
  final VoidCallback onRemoverLogo;
  final VoidCallback onSelecionarAssinaturaEmpresa;
  final VoidCallback onRemoverAssinaturaEmpresa;

  @override
  Widget build(BuildContext context) {
    final possuiLogo =
        caminhoLogo != null &&
        caminhoLogo!.trim().isNotEmpty &&
        File(caminhoLogo!).existsSync();

    final possuiAssinatura =
        caminhoAssinaturaEmpresa != null &&
        caminhoAssinaturaEmpresa!.trim().isNotEmpty &&
        File(caminhoAssinaturaEmpresa!).existsSync();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 78,
                height: 78,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFD6A84B).withValues(alpha: 0.5),
                  ),
                ),
                child: possuiLogo
                    ? Image.file(File(caminhoLogo!), fit: BoxFit.cover)
                    : const Icon(
                        Icons.business_outlined,
                        size: 38,
                        color: Color(0xFFD6A84B),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nomeEmpresa,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Painel administrativo da empresa',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onSelecionarLogo,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(possuiLogo ? 'Substituir logo' : 'Escolher logo'),
              ),
              if (possuiLogo)
                OutlinedButton.icon(
                  onPressed: onRemoverLogo,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remover logo'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1D1D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFD6A84B).withValues(alpha: 0.30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assinatura da empresa',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101010),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: possuiAssinatura
                      ? Image.file(
                          File(caminhoAssinaturaEmpresa!),
                          fit: BoxFit.contain,
                        )
                      : const Text(
                          'Nenhuma assinatura selecionada',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onSelecionarAssinaturaEmpresa,
                      icon: const Icon(Icons.draw_outlined, size: 18),
                      label: Text(
                        possuiAssinatura
                            ? 'Substituir assinatura'
                            : 'Selecionar assinatura',
                      ),
                    ),
                    if (possuiAssinatura)
                      OutlinedButton.icon(
                        onPressed: onRemoverAssinaturaEmpresa,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remover assinatura'),
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

class _SecaoConfiguracao extends StatelessWidget {
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
      color: const Color(0xFF171717),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.25),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: inicialmenteAberta,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icone, color: const Color(0xFFD6A84B)),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitulo,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        children: children,
      ),
    );
  }
}

class _OpcaoCor {
  const _OpcaoCor({required this.nome, required this.valor});

  final String nome;
  final int valor;
}

class _BackupInfoCard extends StatelessWidget {
  const _BackupInfoCard({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD6A84B).withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
