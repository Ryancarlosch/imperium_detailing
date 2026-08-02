class Configuracao {
  final int id;

  final String nomeFantasia;
  final String razaoSocial;
  final String cnpj;
  final String inscricaoEstadual;

  final String telefone;
  final String whatsapp;
  final String email;
  final String site;
  final String instagram;
  final String facebook;

  final String endereco;
  final String numero;
  final String complemento;
  final String bairro;
  final String cidade;
  final String estado;
  final String cep;

  final String? caminhoLogo;
  final String? caminhoAssinaturaEmpresa;

  final String nomeAplicativo;
  final int corPrincipal;
  final int corSecundaria;
  final String tema;

  final int validadeOrcamentoDias;
  final String rodapeDocumentos;
  final String termosOrcamento;
  final String termosOrdemServico;
  final String observacaoPadrao;
  final String mensagemAgradecimento;

  final String mensagemOrcamento;
  final String mensagemConfirmacao;
  final String mensagemEntrega;
  final String mensagemCobranca;

  final String atualizadoEm;

  const Configuracao({
    this.id = 1,
    this.nomeFantasia = 'Imperium Detailing',
    this.razaoSocial = '',
    this.cnpj = '',
    this.inscricaoEstadual = '',
    this.telefone = '',
    this.whatsapp = '',
    this.email = '',
    this.site = '',
    this.instagram = '',
    this.facebook = '',
    this.endereco = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.cidade = '',
    this.estado = '',
    this.cep = '',
    this.caminhoLogo,
    this.caminhoAssinaturaEmpresa,
    this.nomeAplicativo = 'Imperium Detailing',
    this.corPrincipal = 0xFFD6A84B,
    this.corSecundaria = 0xFF1A1A1A,
    this.tema = 'escuro',
    this.validadeOrcamentoDias = 15,
    this.rodapeDocumentos = '',
    this.termosOrcamento = '',
    this.termosOrdemServico = '',
    this.observacaoPadrao = '',
    this.mensagemAgradecimento = '',
    this.mensagemOrcamento = '',
    this.mensagemConfirmacao = '',
    this.mensagemEntrega = '',
    this.mensagemCobranca = '',
    this.atualizadoEm = '',
  });

  factory Configuracao.padrao() {
    return Configuracao(atualizadoEm: DateTime.now().toIso8601String());
  }

  factory Configuracao.fromMap(Map<String, Object?> mapa) {
    return Configuracao(
      id: _lerInteiro(mapa['id'], padrao: 1),
      nomeFantasia: _lerTexto(
        mapa['nome_fantasia'],
        padrao: 'Imperium Detailing',
      ),
      razaoSocial: _lerTexto(mapa['razao_social']),
      cnpj: _lerTexto(mapa['cnpj']),
      inscricaoEstadual: _lerTexto(mapa['inscricao_estadual']),
      telefone: _lerTexto(mapa['telefone']),
      whatsapp: _lerTexto(mapa['whatsapp']),
      email: _lerTexto(mapa['email']),
      site: _lerTexto(mapa['site']),
      instagram: _lerTexto(mapa['instagram']),
      facebook: _lerTexto(mapa['facebook']),
      endereco: _lerTexto(mapa['endereco']),
      numero: _lerTexto(mapa['numero']),
      complemento: _lerTexto(mapa['complemento']),
      bairro: _lerTexto(mapa['bairro']),
      cidade: _lerTexto(mapa['cidade']),
      estado: _lerTexto(mapa['estado']),
      cep: _lerTexto(mapa['cep']),
      caminhoLogo: _lerTextoOpcional(mapa['caminho_logo']),
      caminhoAssinaturaEmpresa: _lerTextoOpcional(
        mapa['caminho_assinatura_empresa'],
      ),
      nomeAplicativo: _lerTexto(
        mapa['nome_aplicativo'],
        padrao: 'Imperium Detailing',
      ),
      corPrincipal: _lerInteiro(mapa['cor_principal'], padrao: 0xFFD6A84B),
      corSecundaria: _lerInteiro(mapa['cor_secundaria'], padrao: 0xFF1A1A1A),
      tema: _lerTexto(mapa['tema'], padrao: 'escuro'),
      validadeOrcamentoDias: _lerInteiro(
        mapa['validade_orcamento_dias'],
        padrao: 15,
      ),
      rodapeDocumentos: _lerTexto(mapa['rodape_documentos']),
      termosOrcamento: _lerTexto(mapa['termos_orcamento']),
      termosOrdemServico: _lerTexto(mapa['termos_ordem_servico']),
      observacaoPadrao: _lerTexto(mapa['observacao_padrao']),
      mensagemAgradecimento: _lerTexto(mapa['mensagem_agradecimento']),
      mensagemOrcamento: _lerTexto(mapa['mensagem_orcamento']),
      mensagemConfirmacao: _lerTexto(mapa['mensagem_confirmacao']),
      mensagemEntrega: _lerTexto(mapa['mensagem_entrega']),
      mensagemCobranca: _lerTexto(mapa['mensagem_cobranca']),
      atualizadoEm: _lerTexto(mapa['atualizado_em']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'nome_fantasia': nomeFantasia.trim(),
      'razao_social': razaoSocial.trim(),
      'cnpj': cnpj.trim(),
      'inscricao_estadual': inscricaoEstadual.trim(),
      'telefone': telefone.trim(),
      'whatsapp': whatsapp.trim(),
      'email': email.trim(),
      'site': site.trim(),
      'instagram': instagram.trim(),
      'facebook': facebook.trim(),
      'endereco': endereco.trim(),
      'numero': numero.trim(),
      'complemento': complemento.trim(),
      'bairro': bairro.trim(),
      'cidade': cidade.trim(),
      'estado': estado.trim(),
      'cep': cep.trim(),
      'caminho_logo': caminhoLogo,
      'caminho_assinatura_empresa': caminhoAssinaturaEmpresa,
      'nome_aplicativo': nomeAplicativo.trim(),
      'cor_principal': corPrincipal,
      'cor_secundaria': corSecundaria,
      'tema': tema.trim(),
      'validade_orcamento_dias': validadeOrcamentoDias,
      'rodape_documentos': rodapeDocumentos.trim(),
      'termos_orcamento': termosOrcamento.trim(),
      'termos_ordem_servico': termosOrdemServico.trim(),
      'observacao_padrao': observacaoPadrao.trim(),
      'mensagem_agradecimento': mensagemAgradecimento.trim(),
      'mensagem_orcamento': mensagemOrcamento.trim(),
      'mensagem_confirmacao': mensagemConfirmacao.trim(),
      'mensagem_entrega': mensagemEntrega.trim(),
      'mensagem_cobranca': mensagemCobranca.trim(),
      'atualizado_em': atualizadoEm.isEmpty
          ? DateTime.now().toIso8601String()
          : atualizadoEm,
    };
  }

  Map<String, Object?> toMapParaSalvar() {
    final mapa = toMap();

    mapa['id'] = 1;
    mapa['atualizado_em'] = DateTime.now().toIso8601String();

    return mapa;
  }

  Configuracao copyWith({
    int? id,
    String? nomeFantasia,
    String? razaoSocial,
    String? cnpj,
    String? inscricaoEstadual,
    String? telefone,
    String? whatsapp,
    String? email,
    String? site,
    String? instagram,
    String? facebook,
    String? endereco,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? estado,
    String? cep,
    String? caminhoLogo,
    String? caminhoAssinaturaEmpresa,
    bool removerLogo = false,
    bool removerAssinaturaEmpresa = false,
    String? nomeAplicativo,
    int? corPrincipal,
    int? corSecundaria,
    String? tema,
    int? validadeOrcamentoDias,
    String? rodapeDocumentos,
    String? termosOrcamento,
    String? termosOrdemServico,
    String? observacaoPadrao,
    String? mensagemAgradecimento,
    String? mensagemOrcamento,
    String? mensagemConfirmacao,
    String? mensagemEntrega,
    String? mensagemCobranca,
    String? atualizadoEm,
  }) {
    return Configuracao(
      id: id ?? this.id,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      razaoSocial: razaoSocial ?? this.razaoSocial,
      cnpj: cnpj ?? this.cnpj,
      inscricaoEstadual: inscricaoEstadual ?? this.inscricaoEstadual,
      telefone: telefone ?? this.telefone,
      whatsapp: whatsapp ?? this.whatsapp,
      email: email ?? this.email,
      site: site ?? this.site,
      instagram: instagram ?? this.instagram,
      facebook: facebook ?? this.facebook,
      endereco: endereco ?? this.endereco,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      estado: estado ?? this.estado,
      cep: cep ?? this.cep,
      caminhoLogo: removerLogo ? null : caminhoLogo ?? this.caminhoLogo,
      caminhoAssinaturaEmpresa: removerAssinaturaEmpresa
          ? null
          : caminhoAssinaturaEmpresa ?? this.caminhoAssinaturaEmpresa,
      nomeAplicativo: nomeAplicativo ?? this.nomeAplicativo,
      corPrincipal: corPrincipal ?? this.corPrincipal,
      corSecundaria: corSecundaria ?? this.corSecundaria,
      tema: tema ?? this.tema,
      validadeOrcamentoDias:
          validadeOrcamentoDias ?? this.validadeOrcamentoDias,
      rodapeDocumentos: rodapeDocumentos ?? this.rodapeDocumentos,
      termosOrcamento: termosOrcamento ?? this.termosOrcamento,
      termosOrdemServico: termosOrdemServico ?? this.termosOrdemServico,
      observacaoPadrao: observacaoPadrao ?? this.observacaoPadrao,
      mensagemAgradecimento:
          mensagemAgradecimento ?? this.mensagemAgradecimento,
      mensagemOrcamento: mensagemOrcamento ?? this.mensagemOrcamento,
      mensagemConfirmacao: mensagemConfirmacao ?? this.mensagemConfirmacao,
      mensagemEntrega: mensagemEntrega ?? this.mensagemEntrega,
      mensagemCobranca: mensagemCobranca ?? this.mensagemCobranca,
      atualizadoEm: atualizadoEm ?? DateTime.now().toIso8601String(),
    );
  }

  String get enderecoCompleto {
    final partes = <String>[];

    if (endereco.trim().isNotEmpty) {
      partes.add(endereco.trim());
    }

    if (numero.trim().isNotEmpty) {
      partes.add(numero.trim());
    }

    if (complemento.trim().isNotEmpty) {
      partes.add(complemento.trim());
    }

    if (bairro.trim().isNotEmpty) {
      partes.add(bairro.trim());
    }

    final cidadeEstado = [
      cidade.trim(),
      estado.trim(),
    ].where((item) => item.isNotEmpty).join(' - ');

    if (cidadeEstado.isNotEmpty) {
      partes.add(cidadeEstado);
    }

    if (cep.trim().isNotEmpty) {
      partes.add('CEP: ${cep.trim()}');
    }

    return partes.join(', ');
  }

  String get telefonePrincipal {
    if (whatsapp.trim().isNotEmpty) {
      return whatsapp.trim();
    }

    return telefone.trim();
  }

  bool get possuiLogo {
    return caminhoLogo != null && caminhoLogo!.trim().isNotEmpty;
  }

  bool get possuiAssinaturaEmpresa {
    return caminhoAssinaturaEmpresa != null &&
        caminhoAssinaturaEmpresa!.trim().isNotEmpty;
  }

  bool get temaEscuro {
    return tema.toLowerCase().trim() == 'escuro';
  }

  static String _lerTexto(Object? valor, {String padrao = ''}) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return padrao;
    }

    return texto;
  }

  static String? _lerTextoOpcional(Object? valor) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    return texto;
  }

  static int _lerInteiro(Object? valor, {required int padrao}) {
    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor?.toString() ?? '') ?? padrao;
  }
}
