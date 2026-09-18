import 'migracao_final_gate_v2_service.dart';
import 'operacional_sync_service.dart';
import 'supabase_bootstrap.dart';

class MigracaoFinalModuloSpec {
  const MigracaoFinalModuloSpec({
    required this.chave,
    required this.titulo,
    required this.ordem,
  });

  final String chave;
  final String titulo;
  final int ordem;
}

class MigracaoFinalModuloEstado {
  const MigracaoFinalModuloEstado({
    required this.spec,
    required this.status,
    this.promovidoEm,
    this.rollbackEm,
    this.observacao = '',
  });

  final MigracaoFinalModuloSpec spec;
  final String status;
  final DateTime? promovidoEm;
  final DateTime? rollbackEm;
  final String observacao;

  bool get promovido => status == 'promovido';
}

class MigracaoFinalPromocaoService {
  MigracaoFinalPromocaoService._();

  static final MigracaoFinalPromocaoService instance =
      MigracaoFinalPromocaoService._();

  static const List<MigracaoFinalModuloSpec> modulos = [
    MigracaoFinalModuloSpec(
      chave: 'operacional',
      titulo: 'Clientes, Veículos e Agenda',
      ordem: 10,
    ),
    MigracaoFinalModuloSpec(
      chave: 'ordens_servico',
      titulo: 'Ordens de Serviço',
      ordem: 20,
    ),
    MigracaoFinalModuloSpec(
      chave: 'arquivos_os',
      titulo: 'Arquivos, checklist e assinatura da OS',
      ordem: 30,
    ),
    MigracaoFinalModuloSpec(
      chave: 'crm_orcamentos',
      titulo: 'CRM e Orçamentos',
      ordem: 40,
    ),
    MigracaoFinalModuloSpec(
      chave: 'estoque',
      titulo: 'Estoque',
      ordem: 50,
    ),
    MigracaoFinalModuloSpec(
      chave: 'financeiro',
      titulo: 'Financeiro',
      ordem: 60,
    ),
    MigracaoFinalModuloSpec(
      chave: 'precificacao',
      titulo: 'Precificação',
      ordem: 70,
    ),
    MigracaoFinalModuloSpec(
      chave: 'configuracoes',
      titulo: 'Configurações',
      ordem: 80,
    ),
    MigracaoFinalModuloSpec(
      chave: 'ponto',
      titulo: 'Ponto',
      ordem: 90,
    ),
  ];

  final OperacionalSyncService _operacional = OperacionalSyncService.instance;

  Future<List<MigracaoFinalModuloEstado>> listar() async {
    final client = SupabaseBootstrap.client;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Entre na conta Supabase para consultar a promoção.');
    }

    final empresaId = await _empresaId();

    final resposta = await client
        .from('imperium_migracao_modulos')
        .select()
        .eq('empresa_id', empresaId);

    final porModulo = <String, Map<String, dynamic>>{};
    for (final item in resposta) {
      final mapa = Map<String, dynamic>.from(item);
      final chave = (mapa['modulo'] ?? '').toString().trim();
      if (chave.isNotEmpty) {
        porModulo[chave] = mapa;
      }
    }

    return modulos.map((spec) {
      final mapa = porModulo[spec.chave];
      return MigracaoFinalModuloEstado(
        spec: spec,
        status: (mapa?['status'] ?? 'pendente').toString(),
        promovidoEm: DateTime.tryParse(
          (mapa?['promovido_em'] ?? '').toString(),
        ),
        rollbackEm: DateTime.tryParse(
          (mapa?['rollback_em'] ?? '').toString(),
        ),
        observacao: (mapa?['observacao'] ?? '').toString(),
      );
    }).toList(growable: false);
  }

  Future<MigracaoFinalModuloEstado> promoverProximo() async {
    final gate = await MigracaoFinalGateV2Service.instance.avaliar();
    if (!gate.prontoParaPromover) {
      throw StateError(
        'O Gate V2 ainda possui \${gate.bloqueios} bloqueio(s).',
      );
    }

    final estados = await listar();
    _validarSequencia(estados);

    final indice = estados.indexWhere((item) => !item.promovido);
    if (indice < 0) {
      throw StateError('Todos os módulos já foram promovidos.');
    }

    if (indice > 0 && !estados[indice - 1].promovido) {
      throw StateError('O módulo anterior ainda não foi promovido.');
    }

    final client = SupabaseBootstrap.client!;
    final userId = client.auth.currentUser!.id;
    final empresaId = gate.empresaId;
    final agora = DateTime.now().toUtc().toIso8601String();
    final spec = estados[indice].spec;

    await client.from('imperium_migracao_modulos').upsert({
      'empresa_id': empresaId,
      'modulo': spec.chave,
      'status': 'promovido',
      'promovido_em': agora,
      'rollback_em': null,
      'promovido_por': userId,
      'observacao': 'Gate V2 aprovado antes do cutover.',
      'atualizado_em': agora,
    }, onConflict: 'empresa_id,modulo');

    final atualizados = await listar();
    return atualizados.firstWhere((item) => item.spec.chave == spec.chave);
  }

  Future<MigracaoFinalModuloEstado> rollbackUltimo() async {
    final estados = await listar();
    _validarSequencia(estados);

    var indice = -1;
    for (var i = estados.length - 1; i >= 0; i--) {
      if (estados[i].promovido) {
        indice = i;
        break;
      }
    }

    if (indice < 0) {
      throw StateError('Nenhum módulo promovido para rollback.');
    }

    for (var i = indice + 1; i < estados.length; i++) {
      if (estados[i].promovido) {
        throw StateError(
          'Faça rollback dos módulos posteriores antes deste módulo.',
        );
      }
    }

    final client = SupabaseBootstrap.client!;
    final userId = client.auth.currentUser!.id;
    final empresaId = await _empresaId();
    final agora = DateTime.now().toUtc().toIso8601String();
    final spec = estados[indice].spec;

    final resposta = await client
        .from('imperium_migracao_modulos')
        .update({
          'status': 'rollback',
          'rollback_em': agora,
          'promovido_por': userId,
          'observacao': 'Rollback técnico do cutover Cloud.',
          'atualizado_em': agora,
        })
        .eq('empresa_id', empresaId)
        .eq('modulo', spec.chave)
        .select();

    if (resposta.isEmpty) {
      throw StateError('O estado remoto do módulo não foi encontrado.');
    }

    final atualizados = await listar();
    return atualizados.firstWhere((item) => item.spec.chave == spec.chave);
  }

  bool todosPromovidos(List<MigracaoFinalModuloEstado> estados) {
    return estados.isNotEmpty && estados.every((item) => item.promovido);
  }

  MigracaoFinalModuloEstado? proximo(
    List<MigracaoFinalModuloEstado> estados,
  ) {
    for (final item in estados) {
      if (!item.promovido) return item;
    }
    return null;
  }

  void _validarSequencia(List<MigracaoFinalModuloEstado> estados) {
    var encontrouNaoPromovido = false;

    for (final item in estados) {
      if (!item.promovido) {
        encontrouNaoPromovido = true;
        continue;
      }

      if (encontrouNaoPromovido) {
        throw StateError(
          'A sequência de promoção Cloud está inconsistente. '
          'Revise os estados antes de continuar.',
        );
      }
    }
  }

  Future<String> _empresaId() async {
    final empresaId = await _operacional.empresaAtualId();
    if (empresaId == null || empresaId.trim().isEmpty) {
      throw StateError('Nenhuma empresa ativa foi identificada.');
    }
    return empresaId.trim();
  }
}
