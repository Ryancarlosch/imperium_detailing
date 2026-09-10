import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/crm_campanha.dart';
import 'package:imperium_detailing/models/crm_lead.dart';
import 'package:imperium_detailing/repositories/crm_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pasta;
  late String caminho;
  late CrmRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pasta = await Directory.systemTemp.createTemp('imperium_crm_test_');
    await databaseFactory.setDatabasesPath(pasta.path);
    caminho = path.join(pasta.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminho);
    repository = CrmRepository();
  });

  tearDown(() async => _removerBanco(caminho));

  tearDownAll(() async {
    if (await pasta.exists()) await pasta.delete(recursive: true);
  });

  test(
    'pipeline registra lead, follow-up e histórico sem duplicar cliente',
    () async {
      final agora = DateTime(2026, 9, 9, 10);
      final leadId = await repository.salvarLead(
        CrmLead(
          nome: 'Cliente CRM',
          telefone: '(49) 99999-1234',
          email: 'crm@teste.com',
          origem: 'Instagram',
          servicoInteresse: 'Vitrificação',
          valorPotencial: 1200,
          proximoContato: DateTime(2026, 9, 8, 10).toIso8601String(),
          criadoEm: agora.toIso8601String(),
          atualizadoEm: agora.toIso8601String(),
        ),
      );

      await repository.adicionarInteracao(
        leadId: leadId,
        tipo: 'WhatsApp',
        descricao: 'Orçamento enviado ao cliente.',
        data: agora,
      );

      var resumo = await repository.carregarResumo(
        referencia: DateTime(2026, 9, 9, 12),
      );
      expect(resumo.totalAbertos, 1);
      expect(resumo.valorPipeline, 1200);
      expect(resumo.followUpsAtrasados, 1);
      expect(await repository.listarInteracoes(leadId), hasLength(1));

      final clienteId = await repository.converterEmCliente(leadId);
      final database = await AppDatabase.instance.database;
      final clientes = await database.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
      );
      expect(clientes, hasLength(1));

      // Repetir a conversão deve reutilizar o vínculo já existente.
      expect(await repository.converterEmCliente(leadId), clienteId);
      expect(
        (await database.query(
          'clientes',
          where: 'email = ?',
          whereArgs: ['crm@teste.com'],
        )),
        hasLength(1),
      );

      // Converter cadastro não significa venda ganha: a oportunidade continua aberta.
      resumo = await repository.carregarResumo(
        referencia: DateTime(2026, 9, 9, 12),
      );
      expect(resumo.totalAbertos, 1);

      await repository.atualizarEtapa(leadId, 'Ganho');
      resumo = await repository.carregarResumo(
        referencia: DateTime(2026, 9, 9, 12),
      );
      expect(resumo.totalAbertos, 0);
      expect(resumo.ganhosMes, 1);

      final perdidoId = await repository.salvarLead(
        CrmLead(
          nome: 'Lead perdido',
          etapa: 'Novo contato',
          criadoEm: agora.toIso8601String(),
          atualizadoEm: agora.toIso8601String(),
        ),
      );
      await repository.atualizarEtapa(
        perdidoId,
        'Perdido',
        motivoPerda: 'Fechou com concorrente',
      );
      resumo = await repository.carregarResumo(
        referencia: DateTime(2026, 9, 9, 12),
      );
      expect(resumo.perdidosMes, 1);
    },
  );

  test('benefício de aniversário gera cupom uma única vez no ano', () async {
    final database = await AppDatabase.instance.database;
    final clienteId = await database.insert('clientes', {
      'nome': 'Aniversariante',
      'telefone': '49999999999',
      'email': '',
      'endereco': '',
      'observacoes': '',
      'data_nascimento': '1990-09-15T00:00:00.000',
      'ativo': 1,
      'arquivado_em': null,
    });

    final agora = DateTime(2026, 9, 1).toIso8601String();
    await repository.salvarCampanha(
      CrmCampanha(
        nome: 'Niver 15%',
        tipo: 'Aniversário',
        beneficioTipo: 'Percentual',
        beneficioValor: 15,
        beneficioDescricao: '15% no mês do aniversário',
        valorMinimo: 200,
        diasValidade: 30,
        ativo: true,
        criadoEm: agora,
        atualizadoEm: agora,
      ),
    );

    expect(
      await repository.gerarBeneficiosAniversario(
        referencia: DateTime(2026, 9, 1),
      ),
      1,
    );
    expect(
      await repository.gerarBeneficiosAniversario(
        referencia: DateTime(2026, 9, 20),
      ),
      0,
    );

    final cupons = await repository.listarCupons(somenteAtivos: true);
    final cupom = cupons.singleWhere((row) => row['cliente_id'] == clienteId);
    expect(cupom['beneficio_tipo'], 'Percentual');
    expect((cupom['beneficio_valor'] as num).toDouble(), 15);
    expect(cupom['status'], 'Ativo');
  });

  test('reativação é idempotente e simulação protege preço mínimo', () async {
    final database = await AppDatabase.instance.database;
    final clienteId = await database.insert('clientes', {
      'nome': 'Cliente inativo comercialmente',
      'telefone': '',
      'email': '',
      'endereco': '',
      'observacoes': '',
      'data_nascimento': null,
      'ativo': 1,
      'arquivado_em': null,
    });
    final veiculoId = await database.insert('veiculos', {
      'cliente_id': clienteId,
      'placa': 'CRM1A23',
      'marca': 'Teste',
      'modelo': 'CRM',
      'ano': '2020',
      'cor': 'Preto',
      'observacoes': '',
    });
    await database.insert('ordens_servico', {
      'numero': 'OS-CRM-1',
      'cliente_id': clienteId,
      'veiculo_id': veiculoId,
      'data_abertura': '2025-01-01T10:00:00.000',
      'data_inicio': '2025-01-01T10:00:00.000',
      'data_finalizacao': '2025-01-02T10:00:00.000',
      'status': 'Finalizada',
      'valor_total': 500.0,
      'desconto': 0.0,
      'observacoes': '',
    });

    final agora = DateTime(2026, 9, 1).toIso8601String();
    final campanhaId = await repository.salvarCampanha(
      CrmCampanha(
        nome: 'Volte para o Imperium',
        tipo: 'Reativação',
        beneficioTipo: 'Valor',
        beneficioValor: 80,
        beneficioDescricao: 'R\$ 80 de benefício',
        valorMinimo: 300,
        diasSemRetorno: 180,
        diasValidade: 20,
        ativo: true,
        criadoEm: agora,
        atualizadoEm: agora,
      ),
    );

    expect(
      await repository.gerarBeneficiosReativacao(
        referencia: DateTime(2026, 9, 9),
      ),
      1,
    );
    expect(
      await repository.gerarBeneficiosReativacao(
        referencia: DateTime(2026, 9, 10),
      ),
      0,
    );

    final rows = await database.query(
      'crm_cupons',
      where: 'campanha_id = ? AND cliente_id = ?',
      whereArgs: [campanhaId, clienteId],
    );
    expect(rows, hasLength(1));
    final cupom = CrmCupom.fromMap(Map<String, dynamic>.from(rows.single));
    final simulacao = repository.simularBeneficio(
      cupom: cupom,
      valorBase: 350,
      precoMinimoSeguro: 300,
    );
    expect(simulacao['valor_final'], 270);
    expect(simulacao['abaixo_preco_minimo'], isTrue);
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
