import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/colaborador_custo.dart';
import 'package:imperium_detailing/repositories/custos_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pasta;
  late String caminho;
  late CustosRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pasta = await Directory.systemTemp.createTemp('imperium_func_v32_test_');
    await databaseFactory.setDatabasesPath(pasta.path);
    caminho = path.join(pasta.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBanco(caminho);
    repository = CustosRepository();
  });

  tearDown(() async => _removerBanco(caminho));

  tearDownAll(() async {
    if (await pasta.exists()) {
      await pasta.delete(recursive: true);
    }
  });

  test('somente funcionário ativo compõe mão de obra e custo hora', () async {
    final agora = DateTime(2026, 9, 10, 9);

    final primeiro = await repository.salvarColaborador(
      ColaboradorCusto(
        nome: 'Funcionário A',
        remuneracaoMensal: 2200,
        horasProdutivasMes: 220,
        criadoEm: agora.toIso8601String(),
        atualizadoEm: agora.toIso8601String(),
      ),
    );
    final segundo = await repository.salvarColaborador(
      ColaboradorCusto(
        nome: 'Funcionário B',
        remuneracaoMensal: 2200,
        horasProdutivasMes: 220,
        criadoEm: agora.toIso8601String(),
        atualizadoEm: agora.toIso8601String(),
      ),
    );

    var resumo = await repository.obterResumoEstruturaCustos();
    expect(resumo['custo_mao_obra_mensal'], 4400);
    expect(resumo['custo_mao_obra_hora'], 20);

    await repository.definirAtivoColaborador(
      segundo,
      false,
      motivo: 'Desligamento para teste',
    );

    resumo = await repository.obterResumoEstruturaCustos();
    expect(resumo['custo_mao_obra_mensal'], 2200);
    expect(resumo['custo_mao_obra_hora'], 10);

    final ativos = await repository.listarColaboradores();
    final todos = await repository.listarColaboradores(incluirInativos: true);
    expect(ativos.map((item) => item.id), contains(primeiro));
    expect(ativos.map((item) => item.id), isNot(contains(segundo)));
    expect(todos, hasLength(2));

    final historico = await repository.listarHistoricoColaborador(segundo);
    expect(historico.first['tipo'], 'Inativação');
    expect(historico.first['motivo'], 'Desligamento para teste');

    expect(
      await repository.colaboradorAtivoNoPeriodo(
        colaboradorId: segundo,
        inicio: DateTime(2026, 9, 1),
        fim: DateTime(2026, 9, 30, 23, 59, 59),
      ),
      isTrue,
    );
    expect(
      await repository.colaboradorAtivoNoPeriodo(
        colaboradorId: segundo,
        inicio: DateTime(2026, 10, 1),
        fim: DateTime(2026, 10, 31, 23, 59, 59),
      ),
      isFalse,
    );

    await repository.definirAtivoColaborador(segundo, true);
    resumo = await repository.obterResumoEstruturaCustos();
    expect(resumo['custo_mao_obra_mensal'], 4400);
  });

  test('reajuste altera salário atual e preserva histórico', () async {
    final agora = DateTime(2026, 9, 10, 9);
    final id = await repository.salvarColaborador(
      ColaboradorCusto(
        nome: 'Funcionário reajuste',
        funcao: 'Detailer',
        remuneracaoMensal: 2200,
        encargosMensais: 300,
        outrosCustosMensais: 100,
        horasProdutivasMes: 220,
        criadoEm: agora.toIso8601String(),
        atualizadoEm: agora.toIso8601String(),
      ),
    );

    await repository.registrarReajusteRemuneracao(
      colaboradorId: id,
      novaRemuneracao: 2600,
      vigencia: DateTime(2026, 9, 10),
      motivo: 'Promoção',
    );

    final todos = await repository.listarColaboradores(incluirInativos: true);
    final colaborador = todos.singleWhere((item) => item.id == id);
    expect(colaborador.remuneracaoMensal, 2600);
    expect(colaborador.encargosMensais, 300);
    expect(colaborador.outrosCustosMensais, 100);

    final historico = await repository.listarHistoricoColaborador(id);
    final reajuste = historico.firstWhere(
      (item) => item['tipo'] == 'Reajuste salarial',
    );
    expect((reajuste['remuneracao_anterior'] as num).toDouble(), 2200);
    expect((reajuste['remuneracao_nova'] as num).toDouble(), 2600);
    expect(reajuste['motivo'], 'Promoção');
  });

  test(
    'migração 31 para 32 preserva funcionário e cria histórico-base',
    () async {
      final database = await AppDatabase.instance.database;
      final id = await database.insert('financeiro_colaboradores_custo', {
        'nome': 'Legado v31',
        'funcao': 'Auxiliar',
        'remuneracao_mensal': 1900,
        'encargos_mensais': 250,
        'outros_custos_mensais': 50,
        'horas_produtivas_mes': 220,
        'observacoes': '',
        'ativo': 1,
        'criado_em': '2026-01-10T08:00:00.000',
        'atualizado_em': '2026-01-10T08:00:00.000',
      });

      await database.execute('DROP TABLE financeiro_colaboradores_historico');
      await database.setVersion(31);
      await AppDatabase.instance.fecharBanco();

      final migrado = await AppDatabase.instance.database;
      expect(await migrado.getVersion(), 32);

      final colaboradores = await migrado.query(
        'financeiro_colaboradores_custo',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(colaboradores, hasLength(1));
      expect(colaboradores.single['nome'], 'Legado v31');

      final historico = await migrado.query(
        'financeiro_colaboradores_historico',
        where: 'colaborador_id = ?',
        whereArgs: [id],
      );
      expect(historico, hasLength(1));
      expect(historico.single['tipo'], 'Cadastro');
      expect((historico.single['remuneracao_nova'] as num).toDouble(), 1900);
    },
  );

  test('funcionário inativo ainda pode receber pagamento pendente', () async {
    final agora = DateTime(2026, 9, 10, 9);
    final id = await repository.salvarColaborador(
      ColaboradorCusto(
        nome: 'Funcionário desligado',
        remuneracaoMensal: 1800,
        horasProdutivasMes: 220,
        criadoEm: agora.toIso8601String(),
        atualizadoEm: agora.toIso8601String(),
      ),
    );
    await repository.definirAtivoColaborador(id, false);

    final database = await AppDatabase.instance.database;
    final contas = await database.query(
      'financeiro_contas',
      columns: ['id'],
      where: 'ativo = 1',
      limit: 1,
    );
    expect(contas, isNotEmpty);

    final pagamentoId = await repository.registrarPagamentoColaborador(
      colaboradorId: id,
      valor: 500,
      contaId: (contas.first['id'] as num).toInt(),
      dataPagamento: DateTime(2026, 9, 10),
      formaPagamento: 'Pix',
      observacoes: 'Acerto pendente após inativação',
    );
    expect(pagamentoId, greaterThan(0));

    final pagamentos = await repository.listarPagamentosColaboradores(
      inicio: DateTime(2026, 9, 1),
      fim: DateTime(2026, 9, 30),
    );
    expect(
      pagamentos.where((item) => item['colaborador_id'] == id),
      hasLength(1),
    );
  });
}

Future<void> _removerBanco(String caminho) async {
  await AppDatabase.instance.fecharBanco();
  if (await databaseFactory.databaseExists(caminho)) {
    await databaseFactory.deleteDatabase(caminho);
  }
}
