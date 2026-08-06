import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/ordem_servico.dart';
import 'package:imperium_detailing/repositories/ordem_servico_repository.dart';
import 'package:imperium_detailing/repositories/ordem_servico_revisao_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late OrdemServicoRepository ordemRepository;
  late OrdemServicoRevisaoRepository revisaoRepository;
  var sequenciaNumero = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_ordem_revisao_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);

    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);

    ordemRepository = OrdemServicoRepository();
    revisaoRepository = OrdemServicoRevisaoRepository();
    sequenciaNumero = 0;
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('Correção administrativa de Ordem de Serviço', () {
    test('recusa motivo com menos de cinco caracteres', () async {
      final ordemId = await _criarOrdem(
        repository: ordemRepository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Finalizada',
      );

      await expectLater(
        ordemRepository.corrigirOrdemFinalizada(
          ordemServicoId: ordemId,
          motivo: 'abc',
          funcionarioResponsavel: 'Ryan',
          observacoes: 'Observação corrigida.',
          quilometragemEntrada: '1000',
          combustivelEntrada: 'Meio tanque',
          horaEntrada: '08:00',
          horaSaida: '17:00',
        ),
        throwsA(isA<ArgumentError>()),
      );

      await _esperarSemRevisoes(ordemId);
    });

    test('recusa correção quando a OS não está finalizada', () async {
      final ordemId = await _criarOrdem(
        repository: ordemRepository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Em andamento',
      );

      await expectLater(
        ordemRepository.corrigirOrdemFinalizada(
          ordemServicoId: ordemId,
          motivo: 'Correção de informações.',
          funcionarioResponsavel: 'Ryan corrigido',
          observacoes: 'Observação corrigida.',
          quilometragemEntrada: '1100',
          combustivelEntrada: 'Tanque cheio',
          horaEntrada: '08:10',
          horaSaida: '17:10',
        ),
        throwsA(isA<StateError>()),
      );

      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);

      expect(ordem, isNotNull);
      expect(ordem!.status, 'Em andamento');
      expect(ordem.quantidadeRevisoes, 0);
      expect(ordem.revisadaEm, isNull);

      await _esperarSemRevisoes(ordemId);
    });

    test('recusa revisão quando nenhum campo foi alterado', () async {
      final ordemId = await _criarOrdem(
        repository: ordemRepository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Finalizada',
      );

      await expectLater(
        ordemRepository.corrigirOrdemFinalizada(
          ordemServicoId: ordemId,
          motivo: 'Conferência sem mudanças.',
          funcionarioResponsavel: 'Ryan',
          observacoes: 'Observação original.',
          quilometragemEntrada: '1000',
          combustivelEntrada: 'Meio tanque',
          horaEntrada: '08:00',
          horaSaida: '17:00',
        ),
        throwsA(isA<StateError>()),
      );

      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);

      expect(ordem, isNotNull);
      expect(ordem!.quantidadeRevisoes, 0);
      expect(ordem.motivoUltimaRevisao, '');
      expect(ordem.revisadaEm, isNull);

      await _esperarSemRevisoes(ordemId);
    });

    test(
      'registra dados anteriores e novos e mantém a OS finalizada',
      () async {
        final ordemId = await _criarOrdem(
          repository: ordemRepository,
          numero: _proximoNumero(() => ++sequenciaNumero),
          status: 'Finalizada',
          assinaturaCliente: 'assinaturas/cliente_original.png',
        );

        final numeroRevisao = await ordemRepository.corrigirOrdemFinalizada(
          ordemServicoId: ordemId,
          motivo: 'Correção dos dados de entrada.',
          funcionarioResponsavel: 'Carlos',
          observacoes: 'Observação corrigida.',
          quilometragemEntrada: '1250',
          combustivelEntrada: 'Tanque cheio',
          horaEntrada: '08:15',
          horaSaida: '17:30',
        );

        expect(numeroRevisao, 1);

        final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);

        expect(ordem, isNotNull);
        expect(ordem!.status, 'Finalizada');
        expect(ordem.funcionarioResponsavel, 'Carlos');
        expect(ordem.observacoes, 'Observação corrigida.');
        expect(ordem.quilometragemEntrada, '1250');
        expect(ordem.combustivelEntrada, 'Tanque cheio');
        expect(ordem.horaEntrada, '08:15');
        expect(ordem.horaSaida, '17:30');
        expect(ordem.quantidadeRevisoes, 1);
        expect(ordem.motivoUltimaRevisao, 'Correção dos dados de entrada.');
        expect(ordem.revisadaEm, isNotNull);
        expect(DateTime.tryParse(ordem.revisadaEm!), isNotNull);
        expect(ordem.assinaturaDesatualizada, isTrue);
        expect(ordem.assinaturaCliente, 'assinaturas/cliente_original.png');

        final revisoes = await ordemRepository.listarRevisoesOrdemServico(
          ordemId,
        );

        expect(revisoes, hasLength(1));

        final revisao = revisoes.single;

        expect(revisao['numero_revisao'], 1);
        expect(revisao['tipo'], 'Correcao administrativa');
        expect(revisao['motivo'], 'Correção dos dados de entrada.');

        final anteriores =
            jsonDecode(revisao['dados_anteriores_json'].toString())
                as Map<String, dynamic>;

        final novos =
            jsonDecode(revisao['dados_novos_json'].toString())
                as Map<String, dynamic>;

        expect(anteriores['funcionario_responsavel'], 'Ryan');
        expect(anteriores['observacoes'], 'Observação original.');
        expect(anteriores['quilometragem_entrada'], '1000');
        expect(anteriores['combustivel_entrada'], 'Meio tanque');
        expect(anteriores['hora_entrada'], '08:00');
        expect(anteriores['hora_saida'], '17:00');

        expect(novos['funcionario_responsavel'], 'Carlos');
        expect(novos['observacoes'], 'Observação corrigida.');
        expect(novos['quilometragem_entrada'], '1250');
        expect(novos['combustivel_entrada'], 'Tanque cheio');
        expect(novos['hora_entrada'], '08:15');
        expect(novos['hora_saida'], '17:30');
      },
    );

    test('incrementa revisões sem repetir o número', () async {
      final ordemId = await _criarOrdem(
        repository: ordemRepository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Finalizada',
      );

      final primeira = await ordemRepository.corrigirOrdemFinalizada(
        ordemServicoId: ordemId,
        motivo: 'Primeira correção registrada.',
        funcionarioResponsavel: 'Carlos',
        observacoes: 'Primeira observação corrigida.',
        quilometragemEntrada: '1100',
        combustivelEntrada: 'Meio tanque',
        horaEntrada: '08:00',
        horaSaida: '17:00',
      );

      final segunda = await ordemRepository.corrigirOrdemFinalizada(
        ordemServicoId: ordemId,
        motivo: 'Segunda correção registrada.',
        funcionarioResponsavel: 'Carlos',
        observacoes: 'Segunda observação corrigida.',
        quilometragemEntrada: '1200',
        combustivelEntrada: 'Tanque cheio',
        horaEntrada: '08:10',
        horaSaida: '17:20',
      );

      expect(primeira, 1);
      expect(segunda, 2);

      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);
      final revisoes = await ordemRepository.listarRevisoesOrdemServico(
        ordemId,
      );

      expect(ordem, isNotNull);
      expect(ordem!.quantidadeRevisoes, 2);
      expect(ordem.motivoUltimaRevisao, 'Segunda correção registrada.');

      expect(revisoes, hasLength(2));
      expect(revisoes.map((revisao) => revisao['numero_revisao']).toList(), [
        2,
        1,
      ]);

      final database = await AppDatabase.instance.database;

      await expectLater(
        database.insert('ordem_servico_revisoes', {
          'ordem_servico_id': ordemId,
          'numero_revisao': 2,
          'tipo': 'Duplicada',
          'motivo': 'Esta revisão deve ser recusada.',
          'dados_anteriores_json': '{}',
          'dados_novos_json': '{}',
          'criado_em': DateTime.now().toIso8601String(),
        }),
        throwsA(anything),
      );

      final revisoesDepoisDaTentativa = await ordemRepository
          .listarRevisoesOrdemServico(ordemId);

      expect(revisoesDepoisDaTentativa, hasLength(2));
    });

    test('correção sem assinatura mantém assinatura atualizada', () async {
      final ordemId = await _criarOrdem(
        repository: ordemRepository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Finalizada',
      );

      await ordemRepository.corrigirOrdemFinalizada(
        ordemServicoId: ordemId,
        motivo: 'Correção sem assinatura anterior.',
        funcionarioResponsavel: 'Carlos',
        observacoes: 'Observação alterada.',
        quilometragemEntrada: '1300',
        combustivelEntrada: 'Reserva',
        horaEntrada: '08:20',
        horaSaida: '17:40',
      );

      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);

      expect(ordem, isNotNull);
      expect(ordem!.assinaturaCliente, isNull);
      expect(ordem.assinaturaDesatualizada, isFalse);
    });
  });

  group('OrdemServicoRevisaoRepository - fluxo compartilhado', () {
    test(
      'registra revisão auditada de checklist dentro da transação',
      () async {
        final ordemId = await _criarOrdem(
          repository: ordemRepository,
          numero: _proximoNumero(() => ++sequenciaNumero),
          status: 'Finalizada',
          assinaturaCliente: 'assinaturas/checklist.png',
        );

        final database = await AppDatabase.instance.database;

        final numero = await database.transaction(
          (transaction) => revisaoRepository.registrarComTransacao(
            transaction,
            ordemServicoId: ordemId,
            tipo: 'Correção de checklist',
            motivo: 'Avaria adicionada ao checklist.',
            dadosAnteriores: const {'status': 0, 'observacao': ''},
            dadosNovos: const {
              'status': 2,
              'observacao': 'Risco no para-choque.',
            },
          ),
        );

        expect(numero, 1);

        final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);
        final revisoes = await ordemRepository.listarRevisoesOrdemServico(
          ordemId,
        );

        expect(ordem, isNotNull);
        expect(ordem!.status, 'Finalizada');
        expect(ordem.quantidadeRevisoes, 1);
        expect(ordem.assinaturaDesatualizada, isTrue);
        expect(ordem.motivoUltimaRevisao, 'Avaria adicionada ao checklist.');

        expect(revisoes, hasLength(1));
        expect(revisoes.single['tipo'], 'Correção de checklist');
        expect(revisoes.single['numero_revisao'], 1);

        final anteriores =
            jsonDecode(revisoes.single['dados_anteriores_json'].toString())
                as Map<String, dynamic>;

        final novos =
            jsonDecode(revisoes.single['dados_novos_json'].toString())
                as Map<String, dynamic>;

        expect(anteriores['status'], 0);
        expect(novos['status'], 2);
        expect(novos['observacao'], 'Risco no para-choque.');
      },
    );

    test('recusa tipo vazio e mantém a transação sem revisão', () async {
      final ordemId = await _criarOrdem(
        repository: ordemRepository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Finalizada',
      );

      final database = await AppDatabase.instance.database;

      await expectLater(
        database.transaction(
          (transaction) => revisaoRepository.registrarComTransacao(
            transaction,
            ordemServicoId: ordemId,
            tipo: '   ',
            motivo: 'Motivo válido para o teste.',
            dadosAnteriores: const {'valor': 1},
            dadosNovos: const {'valor': 2},
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);

      expect(ordem, isNotNull);
      expect(ordem!.quantidadeRevisoes, 0);
      expect(ordem.revisadaEm, isNull);

      await _esperarSemRevisoes(ordemId);
    });

    test('recusa revisão compartilhada em OS não finalizada', () async {
      final ordemId = await _criarOrdem(
        repository: ordemRepository,
        numero: _proximoNumero(() => ++sequenciaNumero),
        status: 'Aberta',
      );

      final database = await AppDatabase.instance.database;

      await expectLater(
        database.transaction(
          (transaction) => revisaoRepository.registrarComTransacao(
            transaction,
            ordemServicoId: ordemId,
            tipo: 'Correção de fotos',
            motivo: 'Foto incorreta foi identificada.',
            dadosAnteriores: const {'foto': 'anterior.jpg'},
            dadosNovos: const {'foto': 'nova.jpg'},
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final ordem = await ordemRepository.buscarOrdemServicoPorId(ordemId);

      expect(ordem, isNotNull);
      expect(ordem!.status, 'Aberta');
      expect(ordem.quantidadeRevisoes, 0);

      await _esperarSemRevisoes(ordemId);
    });
  });
}

String _proximoNumero(int Function() incrementar) {
  final numero = incrementar();
  return 'OS-TESTE-${numero.toString().padLeft(4, '0')}';
}

Future<int> _criarOrdem({
  required OrdemServicoRepository repository,
  required String numero,
  required String status,
  String? assinaturaCliente,
}) async {
  final database = await AppDatabase.instance.database;

  final clienteId = await database.insert('clientes', {
    'nome': 'Cliente da $numero',
    'telefone': '11999999999',
    'email': 'cliente@teste.com',
    'endereco': 'Rua dos Testes, 100',
    'observacoes': 'Cliente criado para teste de revisão.',
  });

  return repository.inserirOrdemServico(
    OrdemServico(
      clienteId: clienteId,
      numero: numero,
      status: status,
      dataAbertura: '2026-08-06',
      dataInicio: '2026-08-06',
      dataFinalizacao: status == 'Finalizada' ? '2026-08-06' : null,
      horaEntrada: '08:00',
      horaSaida: '17:00',
      funcionarioResponsavel: 'Ryan',
      observacoes: 'Observação original.',
      valorTotal: 800,
      desconto: 50,
      formaPagamento: 'Pix',
      quilometragemEntrada: '1000',
      combustivelEntrada: 'Meio tanque',
      assinaturaCliente: assinaturaCliente,
      lancadoFinanceiro: status == 'Finalizada',
    ),
  );
}

Future<void> _esperarSemRevisoes(int ordemServicoId) async {
  final database = await AppDatabase.instance.database;

  final revisoes = await database.query(
    'ordem_servico_revisoes',
    where: 'ordem_servico_id = ?',
    whereArgs: [ordemServicoId],
  );

  expect(revisoes, isEmpty);
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
