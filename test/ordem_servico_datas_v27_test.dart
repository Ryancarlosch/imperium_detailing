import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/ordem_servico.dart';
import 'package:imperium_detailing/repositories/ordem_servico_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late OrdemServicoRepository repository;
  var sequencia = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_os_datas_v27_test_',
    );
    await databaseFactory.setDatabasesPath(pastaTemporaria.path);
    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminhoBanco);
    repository = OrdemServicoRepository();
    sequencia = 0;
  });

  tearDown(() async {
    await _removerBanco(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('OS v27 - datas reais de entrada e saída', () {
    test('inicia OS com data e hora de entrada informadas', () async {
      final database = await AppDatabase.instance.database;
      final clienteId = await database.insert('clientes', {
        'nome': 'Cliente início ${_numero(++sequencia)}',
        'telefone': '11999999999',
        'email': 'inicio@teste.com',
        'endereco': 'Rua Teste, 200',
        'observacoes': '',
      });
      final ordemId = await repository.inserirOrdemServico(
        OrdemServico(
          clienteId: clienteId,
          numero: _numero(++sequencia),
          status: 'Aberta',
          dataAbertura: '2026-08-07',
          valorTotal: 500,
        ),
      );

      await repository.iniciarOrdemServico(
        ordemId,
        dataHoraEntrada: DateTime(2026, 8, 6, 7, 35),
      );

      final ordem = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
        limit: 1,
      );

      expect(ordem.single['status'], 'Em andamento');
      expect(ordem.single['data_inicio'], '2026-08-06');
      expect(ordem.single['hora_entrada'], '07:35');
    });

    test('finaliza usando entrada, saída e pagamento informados', () async {
      final ordemId = await _criarOrdem(
        repository: repository,
        numero: _numero(++sequencia),
      );

      final entrada = DateTime(2026, 8, 7, 8, 15);
      final saida = DateTime(2026, 8, 8, 17, 40);
      final pagamento = DateTime(2026, 8, 8, 17, 45);

      await repository.finalizarOrdemServico(
        ordemServicoId: ordemId,
        formaPagamento: 'Pix',
        dataHoraEntrada: entrada,
        dataHoraSaida: saida,
        dataHoraPagamento: pagamento,
      );

      final database = await AppDatabase.instance.database;
      final ordem = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
        limit: 1,
      );
      final pagamentos = await database.query(
        'ordem_servico_pagamentos',
        where: 'ordem_servico_id = ? AND status = ?',
        whereArgs: [ordemId, 'Pago'],
      );
      final movimentos = await database.query(
        'movimentos_financeiros',
        where: 'ordem_servico_id = ? AND pagamento_id IS NOT NULL',
        whereArgs: [ordemId],
      );

      expect(ordem.single['status'], 'Finalizada');
      expect(ordem.single['data_inicio'], '2026-08-07');
      expect(ordem.single['hora_entrada'], '08:15');
      expect(ordem.single['data_finalizacao'], '2026-08-08');
      expect(ordem.single['hora_saida'], '17:40');

      expect(pagamentos, hasLength(1));
      expect(
        DateTime.parse(pagamentos.single['data_pagamento'].toString()),
        pagamento,
      );

      expect(movimentos, isNotEmpty);
      expect(DateTime.parse(movimentos.first['data'].toString()), pagamento);
    });

    test('recusa saída anterior à entrada sem finalizar a OS', () async {
      final ordemId = await _criarOrdem(
        repository: repository,
        numero: _numero(++sequencia),
      );

      await expectLater(
        repository.finalizarOrdemServico(
          ordemServicoId: ordemId,
          formaPagamento: 'Pix',
          dataHoraEntrada: DateTime(2026, 8, 8, 18),
          dataHoraSaida: DateTime(2026, 8, 8, 10),
        ),
        throwsA(isA<ArgumentError>()),
      );

      final database = await AppDatabase.instance.database;
      final ordem = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
        limit: 1,
      );
      final pagamentos = await database.query(
        'ordem_servico_pagamentos',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );

      expect(ordem.single['status'], 'Em andamento');
      expect(pagamentos, isEmpty);
    });

    test('corrige datas de OS finalizada e registra auditoria', () async {
      final ordemId = await _criarOrdem(
        repository: repository,
        numero: _numero(++sequencia),
      );

      await repository.finalizarOrdemServico(
        ordemServicoId: ordemId,
        valorPagamento: 0,
        dataHoraEntrada: DateTime(2026, 8, 7, 9),
        dataHoraSaida: DateTime(2026, 8, 7, 18),
      );

      final revisao = await repository.corrigirOrdemFinalizada(
        ordemServicoId: ordemId,
        motivo: 'Corrigir horários reais do atendimento',
        funcionarioResponsavel: 'Ryan',
        observacoes: 'Datas ajustadas após fechamento do dia.',
        quilometragemEntrada: '50000',
        combustivelEntrada: 'Meio tanque',
        dataInicio: '06/08/2026',
        dataFinalizacao: '08/08/2026',
        horaEntrada: '08:30',
        horaSaida: '17:20',
      );

      final database = await AppDatabase.instance.database;
      final ordem = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
        limit: 1,
      );
      final revisoes = await database.query(
        'ordem_servico_revisoes',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'numero_revisao DESC',
        limit: 1,
      );

      expect(revisao, 1);
      expect(ordem.single['data_inicio'], '2026-08-06');
      expect(ordem.single['hora_entrada'], '08:30');
      expect(ordem.single['data_finalizacao'], '2026-08-08');
      expect(ordem.single['hora_saida'], '17:20');

      expect(revisoes, hasLength(1));
      final anteriores =
          jsonDecode(revisoes.single['dados_anteriores_json'].toString())
              as Map<String, dynamic>;
      final novos =
          jsonDecode(revisoes.single['dados_novos_json'].toString())
              as Map<String, dynamic>;

      expect(anteriores['data_inicio'], '2026-08-07');
      expect(anteriores['data_finalizacao'], '2026-08-07');
      expect(novos['data_inicio'], '2026-08-06');
      expect(novos['data_finalizacao'], '2026-08-08');
    });
  });
}

String _numero(int sequencia) {
  return 'OS-DATAS-${sequencia.toString().padLeft(4, '0')}';
}

Future<int> _criarOrdem({
  required OrdemServicoRepository repository,
  required String numero,
}) async {
  final database = await AppDatabase.instance.database;
  final clienteId = await database.insert('clientes', {
    'nome': 'Cliente $numero',
    'telefone': '11999999999',
    'email': 'cliente@teste.com',
    'endereco': 'Rua Teste, 100',
    'observacoes': '',
  });

  return repository.inserirOrdemServico(
    OrdemServico(
      clienteId: clienteId,
      numero: numero,
      status: 'Em andamento',
      dataAbertura: '2026-08-07',
      dataInicio: '2026-08-07',
      horaEntrada: '09:00',
      funcionarioResponsavel: 'Ryan',
      observacoes: 'Teste de datas da OS.',
      valorTotal: 1000,
      desconto: 0,
      quilometragemEntrada: '50000',
      combustivelEntrada: 'Meio tanque',
    ),
  );
}

Future<void> _removerBanco(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
