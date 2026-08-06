import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/models/cliente.dart';
import 'package:imperium_detailing/models/veiculo.dart';
import 'package:imperium_detailing/repositories/cliente_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late ClienteRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_cliente_repository_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);

    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);
    repository = ClienteRepository();
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('ClienteRepository - arquivamento e reativação', () {
    test('insere cliente novo como ativo', () async {
      final clienteId = await repository.inserirCliente(
        _novoCliente(nome: 'Cliente ativo'),
      );

      expect(clienteId, greaterThan(0));

      final clienteSalvo = await repository.buscarClientePorId(clienteId);
      final clientesAtivos = await repository.listarClientesAtivos();
      final clientesArquivados = await repository.listarClientesArquivados();

      expect(clienteSalvo, isNotNull);
      expect(clienteSalvo!.nome, 'Cliente ativo');
      expect(clienteSalvo.ativo, isTrue);
      expect(clienteSalvo.arquivadoEm, isNull);

      expect(clientesAtivos.map((cliente) => cliente.id), contains(clienteId));
      expect(
        clientesArquivados.map((cliente) => cliente.id),
        isNot(contains(clienteId)),
      );
    });

    test('arquiva sem excluir e preenche a data de arquivamento', () async {
      final clienteId = await repository.inserirCliente(
        _novoCliente(nome: 'Cliente para arquivar'),
      );

      final inicio = DateTime.now();
      final alterados = await repository.arquivarCliente(clienteId);
      final fim = DateTime.now();

      expect(alterados, 1);

      final clienteArquivado = await repository.buscarClientePorId(clienteId);

      expect(clienteArquivado, isNotNull);
      expect(clienteArquivado!.ativo, isFalse);
      expect(clienteArquivado.arquivadoEm, isNotNull);

      final dataArquivamento = DateTime.tryParse(clienteArquivado.arquivadoEm!);

      expect(dataArquivamento, isNotNull);
      expect(
        dataArquivamento!.isBefore(inicio.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        dataArquivamento.isAfter(fim.add(const Duration(seconds: 1))),
        isFalse,
      );

      final clientesAtivos = await repository.listarClientesAtivos();
      final clientesArquivados = await repository.listarClientesArquivados();
      final todosClientes = await repository.listarTodosClientes();

      expect(
        clientesAtivos.map((cliente) => cliente.id),
        isNot(contains(clienteId)),
      );
      expect(
        clientesArquivados.map((cliente) => cliente.id),
        contains(clienteId),
      );
      expect(todosClientes.map((cliente) => cliente.id), contains(clienteId));
    });

    test('reativa cliente e limpa a data de arquivamento', () async {
      final clienteId = await repository.inserirCliente(
        _novoCliente(nome: 'Cliente para reativar'),
      );

      expect(await repository.arquivarCliente(clienteId), 1);
      expect(await repository.reativarCliente(clienteId), 1);

      final clienteReativado = await repository.buscarClientePorId(clienteId);
      final clientesAtivos = await repository.listarClientesAtivos();
      final clientesArquivados = await repository.listarClientesArquivados();

      expect(clienteReativado, isNotNull);
      expect(clienteReativado!.ativo, isTrue);
      expect(clienteReativado.arquivadoEm, isNull);

      expect(clientesAtivos.map((cliente) => cliente.id), contains(clienteId));
      expect(
        clientesArquivados.map((cliente) => cliente.id),
        isNot(contains(clienteId)),
      );
    });

    test('arquivar preserva veículo e Ordem de Serviço vinculados', () async {
      final clienteId = await repository.inserirCliente(
        _novoCliente(nome: 'Cliente com histórico'),
      );

      final database = await AppDatabase.instance.database;

      final veiculo = Veiculo(
        clienteId: clienteId,
        marca: 'Volkswagen',
        modelo: 'Golf',
        placa: 'ABC1D23',
        cor: 'Preto',
        ano: '2020',
        observacoes: 'Veículo usado no teste.',
      );

      final dadosVeiculo = veiculo.toMap()..remove('id');
      final veiculoId = await database.insert('veiculos', dadosVeiculo);

      final ordemServicoId = await database.insert('ordens_servico', {
        'cliente_id': clienteId,
        'veiculo_id': veiculoId,
        'numero': 'OS-TESTE-ARQUIVAMENTO',
        'status': 'Finalizada',
        'data_abertura': '2026-08-06T08:00:00.000',
        'data_finalizacao': '2026-08-06T17:00:00.000',
        'funcionario_responsavel': 'Ryan',
        'observacoes': 'Histórico que não pode ser apagado.',
        'valor_total': 700,
        'desconto': 0,
        'forma_pagamento': 'Pix',
        'quilometragem_entrada': '50000',
        'combustivel_entrada': 'Meio tanque',
        'lancado_financeiro': 1,
      });

      expect(await repository.contarVeiculosDoCliente(clienteId), 1);
      expect(await repository.arquivarCliente(clienteId), 1);

      final clientes = await database.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [clienteId],
      );
      final veiculos = await database.query(
        'veiculos',
        where: 'id = ?',
        whereArgs: [veiculoId],
      );
      final ordens = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemServicoId],
      );

      expect(clientes, hasLength(1));
      expect(clientes.single['ativo'], 0);

      expect(veiculos, hasLength(1));
      expect(veiculos.single['cliente_id'], clienteId);
      expect(veiculos.single['placa'], 'ABC1D23');

      expect(ordens, hasLength(1));
      expect(ordens.single['cliente_id'], clienteId);
      expect(ordens.single['veiculo_id'], veiculoId);
      expect(ordens.single['numero'], 'OS-TESTE-ARQUIVAMENTO');

      expect(await repository.contarVeiculosDoCliente(clienteId), 1);

      final violacoes = await database.rawQuery('PRAGMA foreign_key_check');

      expect(violacoes, isEmpty);
    });

    test('excluirCliente também realiza arquivamento lógico', () async {
      final clienteId = await repository.inserirCliente(
        _novoCliente(nome: 'Cliente exclusão lógica'),
      );

      final alterados = await repository.excluirCliente(clienteId);
      final cliente = await repository.buscarClientePorId(clienteId);

      expect(alterados, 1);
      expect(cliente, isNotNull);
      expect(cliente!.ativo, isFalse);
      expect(cliente.arquivadoEm, isNotNull);

      final database = await AppDatabase.instance.database;
      final quantidade = await database.rawQuery(
        '''
        SELECT COUNT(*) AS total
        FROM clientes
        WHERE id = ?
        ''',
        [clienteId],
      );

      expect((quantidade.single['total'] as num).toInt(), 1);
    });
  });
}

Cliente _novoCliente({required String nome}) {
  return Cliente(
    nome: nome,
    telefone: '11999999999',
    email: 'cliente@teste.com',
    endereco: 'Rua dos Testes, 100',
    observacoes: 'Cliente criado por teste automatizado.',
  );
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
