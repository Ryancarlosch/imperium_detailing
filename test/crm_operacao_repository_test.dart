import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/crm_operacao_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pasta;
  late String caminho;
  late CrmOperacaoRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pasta = await Directory.systemTemp.createTemp('imperium_crm_operacao_');
    await databaseFactory.setDatabasesPath(pasta.path);
    caminho = path.join(pasta.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminho);
    repository = CrmOperacaoRepository();
  });

  tearDown(() async => _removerBanco(caminho));

  tearDownAll(() async {
    if (await pasta.exists()) await pasta.delete(recursive: true);
  });

  test(
    'sincroniza ações comerciais sem duplicar e preserva histórico',
    () async {
      final db = await AppDatabase.instance.database;
      final clienteId = await db.insert('clientes', {
        'nome': 'Cliente Relacionamento',
        'telefone': '49999999999',
        'email': 'cliente@teste.com',
        'endereco': '',
        'observacoes': '',
        'ativo': 1,
        'arquivado_em': null,
        'data_nascimento': null,
      });

      final agora = DateTime(2026, 9, 10, 10);
      final leadId = await db.insert('crm_leads', {
        'nome': 'Lead Relacionamento',
        'telefone': '49988887777',
        'email': '',
        'cliente_id': null,
        'veiculo_id': null,
        'origem': 'WhatsApp',
        'servico_interesse': 'Vitrificação',
        'veiculo_interesse': '',
        'valor_potencial': 1200.0,
        'etapa': 'Aguardando cliente',
        'responsavel': '',
        'proximo_contato': DateTime(2026, 9, 9).toIso8601String(),
        'observacoes': '',
        'motivo_perda': '',
        'agendamento_id': null,
        'criado_em': DateTime(2026, 9, 8).toIso8601String(),
        'atualizado_em': DateTime(2026, 9, 8).toIso8601String(),
        'convertido_em': null,
      });

      final orcamentoId = await db.insert('orcamentos', {
        'cliente_id': clienteId,
        'veiculo_id': null,
        'servico': 'Polimento',
        'descricao': '',
        'valor': 700.0,
        'data_emissao': DateTime(2026, 9, 6).toIso8601String(),
        'validade': DateTime(2026, 9, 20).toIso8601String(),
        'status': 'Pendente',
        'observacoes': '',
        'desconto': 0.0,
      });

      await db.insert('ordens_servico', {
        'numero': 'OS-CRM-V3-1',
        'cliente_id': clienteId,
        'veiculo_id': null,
        'status': 'Finalizada',
        'data_abertura': DateTime(2026, 9, 7).toIso8601String(),
        'data_inicio': DateTime(2026, 9, 8).toIso8601String(),
        'data_finalizacao': DateTime(2026, 9, 9).toIso8601String(),
        'observacoes': '',
        'valor_total': 500.0,
        'desconto': 0.0,
      });

      final campanhaId = await db.insert('crm_campanhas', {
        'nome': 'Volte V3',
        'tipo': 'Manual',
        'beneficio_tipo': 'Valor',
        'beneficio_valor': 50.0,
        'beneficio_descricao': 'R\$ 50 de benefício',
        'valor_minimo': 200.0,
        'dias_validade': 30,
        'dias_sem_retorno': 180,
        'ativo': 1,
        'criado_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
      });
      await db.insert('crm_cupons', {
        'codigo': 'CRM-V3-001',
        'campanha_id': campanhaId,
        'cliente_id': clienteId,
        'lead_id': null,
        'beneficio_tipo': 'Valor',
        'beneficio_valor': 50.0,
        'beneficio_descricao': 'R\$ 50 de benefício',
        'valor_minimo': 200.0,
        'validade_inicio': '2026-09-10',
        'validade_fim': '2026-09-30',
        'status': 'Ativo',
        'usado_em': null,
        'ordem_servico_id': null,
        'chave_geracao': 'crm-v3-test-1',
        'criado_em': agora.toIso8601String(),
      });

      expect(await repository.sincronizarAcoes(referencia: agora), 4);
      expect(await repository.sincronizarAcoes(referencia: agora), 0);

      final acoes = await repository.listarAcoes();
      expect(acoes, hasLength(4));
      expect(acoes.map((item) => item.tipo).toSet(), {
        'Follow-up lead',
        'Follow-up orçamento',
        'Pós-venda',
        'Benefício/cupom',
      });

      final followup = acoes.singleWhere((item) => item.leadId == leadId);
      await repository.concluirAcao(
        followup.id,
        proximoContato: DateTime(2026, 9, 15),
        observacoes: 'Cliente pediu novo contato.',
      );
      expect(
        (await repository.listarAcoes(status: 'Concluida')).single.id,
        followup.id,
      );

      final lead = await db.query(
        'crm_leads',
        columns: ['proximo_contato'],
        where: 'id = ?',
        whereArgs: [leadId],
        limit: 1,
      );
      expect(
        DateTime.parse(lead.single['proximo_contato']!.toString()).day,
        15,
      );

      expect(await repository.sincronizarAcoes(referencia: agora), 1);
      final pendentes = await repository.listarAcoes();
      expect(
        pendentes.where((item) => item.tipo == 'Follow-up lead'),
        hasLength(1),
      );

      final leadDoOrcamento = await repository.criarOuAtualizarLeadDoOrcamento(
        orcamentoId,
      );
      expect(leadDoOrcamento, greaterThan(0));
      expect(
        await repository.criarOuAtualizarLeadDoOrcamento(orcamentoId),
        leadDoOrcamento,
      );
      final leadsCliente = await db.query(
        'crm_leads',
        where: "cliente_id = ? AND etapa NOT IN ('Ganho', 'Perdido')",
        whereArgs: [clienteId],
      );
      expect(leadsCliente, hasLength(1));
    },
  );

  test('desempenho consolida funil, orçamentos e ações concluídas', () async {
    final db = await AppDatabase.instance.database;
    final agora = DateTime(2026, 9, 10, 10);

    for (final item in [
      ('Instagram', 'Ganho', 1000.0, ''),
      ('Instagram', 'Perdido', 800.0, 'Preço'),
      ('Google', 'Novo contato', 500.0, ''),
    ]) {
      await db.insert('crm_leads', {
        'nome': 'Lead ${item.$1} ${item.$2}',
        'telefone': '',
        'email': '',
        'cliente_id': null,
        'veiculo_id': null,
        'origem': item.$1,
        'servico_interesse': '',
        'veiculo_interesse': '',
        'valor_potencial': item.$3,
        'etapa': item.$2,
        'responsavel': '',
        'proximo_contato': null,
        'observacoes': '',
        'motivo_perda': item.$4,
        'agendamento_id': null,
        'criado_em': agora.toIso8601String(),
        'atualizado_em': agora.toIso8601String(),
        'convertido_em': null,
      });
    }

    final clienteId = await db.insert('clientes', {
      'nome': 'Cliente Orçamento',
      'telefone': '',
      'email': '',
      'endereco': '',
      'observacoes': '',
      'ativo': 1,
      'arquivado_em': null,
      'data_nascimento': null,
    });
    await db.insert('orcamentos', {
      'cliente_id': clienteId,
      'veiculo_id': null,
      'servico': 'Teste',
      'descricao': '',
      'valor': 400.0,
      'data_emissao': agora.toIso8601String(),
      'validade': DateTime(2026, 9, 30).toIso8601String(),
      'status': 'Aprovado',
      'observacoes': '',
      'desconto': 0.0,
    });
    await db.insert('orcamentos', {
      'cliente_id': clienteId,
      'veiculo_id': null,
      'servico': 'Teste 2',
      'descricao': '',
      'valor': 600.0,
      'data_emissao': agora.toIso8601String(),
      'validade': DateTime(2026, 9, 30).toIso8601String(),
      'status': 'Pendente',
      'observacoes': '',
      'desconto': 0.0,
    });

    await repository.garantirEstrutura();
    await db.insert(CrmOperacaoRepository.tabelaAcoes, {
      'chave': 'teste-concluida',
      'tipo': 'Pós-venda',
      'entidade_tipo': 'ordem_servico',
      'entidade_id': 999,
      'cliente_id': clienteId,
      'lead_id': null,
      'titulo': 'Teste',
      'nome_contato': 'Cliente',
      'telefone': '',
      'mensagem_sugerida': '',
      'vencimento': '2026-09-10',
      'prioridade': 'Normal',
      'status': 'Concluida',
      'concluida_em': agora.toIso8601String(),
      'adiada_para': null,
      'observacoes': '',
      'criado_em': agora.toIso8601String(),
      'atualizado_em': agora.toIso8601String(),
    });

    final resumo = await repository.carregarDesempenho(
      inicio: DateTime(2026, 9, 1),
      fim: DateTime(2026, 9, 30),
    );

    expect(resumo.leadsCriados, 3);
    expect(resumo.ganhos, 1);
    expect(resumo.perdidos, 1);
    expect(resumo.abertos, 1);
    expect(resumo.valorPotencial, 2300.0);
    expect(resumo.valorGanho, 1000.0);
    expect(resumo.orcamentosCriados, 2);
    expect(resumo.orcamentosAprovados, 1);
    expect(resumo.valorOrcamentos, 1000.0);
    expect(resumo.valorOrcamentosAprovados, 400.0);
    expect(resumo.acoesConcluidas, 1);
    expect(resumo.origens.first.origem, 'Instagram');
    expect(resumo.motivosPerda.single.motivo, 'Preço');
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
