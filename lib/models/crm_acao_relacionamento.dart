class CrmAcaoRelacionamento {
  const CrmAcaoRelacionamento({
    required this.id,
    required this.chave,
    required this.tipo,
    required this.entidadeTipo,
    required this.entidadeId,
    this.clienteId,
    this.leadId,
    required this.titulo,
    required this.nomeContato,
    required this.telefone,
    required this.mensagemSugerida,
    required this.vencimento,
    required this.prioridade,
    required this.status,
    this.concluidaEm,
    this.adiadaPara,
    required this.observacoes,
    required this.criadoEm,
    required this.atualizadoEm,
  });

  final int id;
  final String chave;
  final String tipo;
  final String entidadeTipo;
  final int entidadeId;
  final int? clienteId;
  final int? leadId;
  final String titulo;
  final String nomeContato;
  final String telefone;
  final String mensagemSugerida;
  final String vencimento;
  final String prioridade;
  final String status;
  final String? concluidaEm;
  final String? adiadaPara;
  final String observacoes;
  final String criadoEm;
  final String atualizadoEm;

  bool get pendente => status == 'Pendente';

  DateTime? get vencimentoData => DateTime.tryParse(vencimento);

  bool atrasadaEm(DateTime referencia) {
    final data = vencimentoData;
    if (!pendente || data == null) {
      return false;
    }
    final diaAcao = DateTime(data.year, data.month, data.day);
    final diaRef = DateTime(referencia.year, referencia.month, referencia.day);
    return diaAcao.isBefore(diaRef);
  }

  bool venceEm(DateTime referencia) {
    final data = vencimentoData;
    if (!pendente || data == null) {
      return false;
    }
    return data.year == referencia.year &&
        data.month == referencia.month &&
        data.day == referencia.day;
  }

  factory CrmAcaoRelacionamento.fromMap(Map<String, dynamic> map) {
    return CrmAcaoRelacionamento(
      id: _int(map['id']),
      chave: (map['chave'] ?? '').toString(),
      tipo: (map['tipo'] ?? '').toString(),
      entidadeTipo: (map['entidade_tipo'] ?? '').toString(),
      entidadeId: _int(map['entidade_id']),
      clienteId: _intNulo(map['cliente_id']),
      leadId: _intNulo(map['lead_id']),
      titulo: (map['titulo'] ?? '').toString(),
      nomeContato: (map['nome_contato'] ?? '').toString(),
      telefone: (map['telefone'] ?? '').toString(),
      mensagemSugerida: (map['mensagem_sugerida'] ?? '').toString(),
      vencimento: (map['vencimento'] ?? '').toString(),
      prioridade: (map['prioridade'] ?? 'Normal').toString(),
      status: (map['status'] ?? 'Pendente').toString(),
      concluidaEm: _textoNulo(map['concluida_em']),
      adiadaPara: _textoNulo(map['adiada_para']),
      observacoes: (map['observacoes'] ?? '').toString(),
      criadoEm: (map['criado_em'] ?? '').toString(),
      atualizadoEm: (map['atualizado_em'] ?? '').toString(),
    );
  }

  static int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static int? _intNulo(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }

  static String? _textoNulo(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
