import '../database/app_database.dart';
import 'supabase_bootstrap.dart';
import 'web_origem_service.dart';

class WebConfiguracaoEmpresaService {
  WebConfiguracaoEmpresaService._();

  static final WebConfiguracaoEmpresaService instance =
      WebConfiguracaoEmpresaService._();

  Future<String> _empresaId() async {
    final empresa = (await AppDatabase.instance.empresaAtivaId)?.trim() ?? '';
    if (empresa.isEmpty) {
      throw StateError('Selecione uma empresa antes de abrir Configurações.');
    }
    return empresa;
  }

  Future<Map<String, dynamic>> carregar() async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final raw = await client
        .from('imperium_configuracoes_empresa')
        .select()
        .eq('empresa_id', empresaId)
        .maybeSingle();

    if (raw == null) {
      return <String, dynamic>{
        'empresa_id': empresaId,
        'nome_fantasia': '',
        'razao_social': '',
        'cnpj': '',
        'inscricao_estadual': '',
        'telefone': '',
        'whatsapp': '',
        'email': '',
        'site': '',
        'instagram': '',
        'facebook': '',
        'endereco': '',
        'numero': '',
        'complemento': '',
        'bairro': '',
        'cidade': '',
        'estado': '',
        'cep': '',
        'nome_aplicativo': 'Imperium Detailing',
        'cor_principal': 0xFFD6A84B,
        'cor_secundaria': 0xFF1A1A1A,
        'tema': 'escuro',
        'validade_orcamento_dias': 15,
        'rodape_documentos': '',
        'termos_orcamento': '',
        'termos_ordem_servico': '',
        'observacao_padrao': '',
        'mensagem_agradecimento': '',
        'mensagem_orcamento': '',
        'mensagem_confirmacao': '',
        'mensagem_entrega': '',
        'mensagem_cobranca': '',
      };
    }

    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> salvar({
    required Map<String, dynamic> atual,
    required Map<String, dynamic> valores,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) throw StateError('Supabase não está disponível.');

    final empresaId = await _empresaId();
    final agora = DateTime.now().toUtc().toIso8601String();
    final dispositivoId = await WebOrigemService.instance.dispositivoId();

    final payload = <String, dynamic>{
      'nome_fantasia': _texto(valores['nome_fantasia']),
      'razao_social': _texto(valores['razao_social']),
      'cnpj': _texto(valores['cnpj']),
      'inscricao_estadual': _texto(valores['inscricao_estadual']),
      'telefone': _texto(valores['telefone']),
      'whatsapp': _texto(valores['whatsapp']),
      'email': _texto(valores['email']),
      'site': _texto(valores['site']),
      'instagram': _texto(valores['instagram']),
      'facebook': _texto(valores['facebook']),
      'endereco': _texto(valores['endereco']),
      'numero': _texto(valores['numero']),
      'complemento': _texto(valores['complemento']),
      'bairro': _texto(valores['bairro']),
      'cidade': _texto(valores['cidade']),
      'estado': _texto(valores['estado']),
      'cep': _texto(valores['cep']),
      'nome_aplicativo': _textoOu(
        valores['nome_aplicativo'],
        'Imperium Detailing',
      ),
      'cor_principal': _inteiro(
        valores['cor_principal'],
        padrao: 0xFFD6A84B,
      ),
      'cor_secundaria': _inteiro(
        valores['cor_secundaria'],
        padrao: 0xFF1A1A1A,
      ),
      'tema': _tema(valores['tema']),
      'validade_orcamento_dias': _inteiro(
        valores['validade_orcamento_dias'],
        padrao: 15,
      ).clamp(1, 365),
      'rodape_documentos': _texto(valores['rodape_documentos']),
      'termos_orcamento': _texto(valores['termos_orcamento']),
      'termos_ordem_servico': _texto(valores['termos_ordem_servico']),
      'observacao_padrao': _texto(valores['observacao_padrao']),
      'mensagem_agradecimento': _texto(valores['mensagem_agradecimento']),
      'mensagem_orcamento': _texto(valores['mensagem_orcamento']),
      'mensagem_confirmacao': _texto(valores['mensagem_confirmacao']),
      'mensagem_entrega': _texto(valores['mensagem_entrega']),
      'mensagem_cobranca': _texto(valores['mensagem_cobranca']),
      'origem_dispositivo': dispositivoId,
      'origem_atualizado_em': agora,
    };

    final versao = _texto(atual['atualizado_em']);
    if (versao.isEmpty) {
      final resposta = await client
          .from('imperium_configuracoes_empresa')
          .upsert(<String, dynamic>{
            'empresa_id': empresaId,
            ...payload,
          }, onConflict: 'empresa_id')
          .select()
          .single();
      return Map<String, dynamic>.from(resposta);
    }

    final rows = await client
        .from('imperium_configuracoes_empresa')
        .update(payload)
        .eq('empresa_id', empresaId)
        .eq('atualizado_em', versao)
        .select();

    if ((rows as List).isEmpty) {
      throw StateError(
        'As configurações foram alteradas em outro dispositivo. Atualize a '
        'página antes de salvar novamente.',
      );
    }

    return Map<String, dynamic>.from(rows.first as Map);
  }

  static String _texto(dynamic valor) => (valor ?? '').toString().trim();

  static String _textoOu(dynamic valor, String padrao) {
    final texto = _texto(valor);
    return texto.isEmpty ? padrao : texto;
  }

  static String _tema(dynamic valor) {
    final tema = _texto(valor).toLowerCase();
    return tema == 'claro' ? 'claro' : 'escuro';
  }

  static int _inteiro(dynamic valor, {int padrao = 0}) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? padrao;
  }
}
