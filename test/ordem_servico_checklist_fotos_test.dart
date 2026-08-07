import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:imperium_detailing/repositories/ordem_servico_checklist_repository.dart';
import 'package:imperium_detailing/repositories/ordem_servico_foto_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;
  late OrdemServicoChecklistRepository checklistRepository;
  late OrdemServicoFotoRepository fotoRepository;
  var sequencia = 0;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_checklist_fotos_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);

    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);
    checklistRepository = OrdemServicoChecklistRepository();
    fotoRepository = OrdemServicoFotoRepository();
    sequencia = 0;
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('Checklist auditado de OS finalizada', () {
    test('cria checklist padrão somente uma vez', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
      );

      final primeiraLista = await checklistRepository.listarChecklist(ordemId);
      final segundaLista = await checklistRepository.listarChecklist(ordemId);

      expect(primeiraLista, hasLength(27));
      expect(segundaLista, hasLength(27));
      expect(
        primeiraLista.map((item) => item['id']).toList(),
        segundaLista.map((item) => item['id']).toList(),
      );
      expect(
        primeiraLista.every(
          (item) =>
              (item['status'] as num).toInt() ==
                  OrdemServicoChecklistRepository.statusNaoVerificado &&
              (item['marcado'] as num).toInt() == 0,
        ),
        isTrue,
      );
    });

    test('corrige checklist, dados de entrada e registra revisão', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
        assinaturaCliente: 'assinaturas/cliente.png',
        quilometragem: '1000',
        combustivel: '1/2 tanque',
      );

      final itens = await checklistRepository.listarChecklist(ordemId);
      final primeiro = Map<String, dynamic>.from(itens.first);

      primeiro['status'] = OrdemServicoChecklistRepository.statusAvaria;
      primeiro['marcado'] = 1;
      primeiro['observacao'] = 'Risco profundo';
      primeiro['foto_avaria'] = '/tmp/avaria_teste.jpg';
      primeiro['avaria_localizacao'] = 'Porta dianteira esquerda';
      primeiro['avaria_data_registro'] = '2026-08-06T20:00:00.000';

      final novosItens = [
        primeiro,
        ...itens.skip(1).map(Map<String, dynamic>.from),
      ];

      final numeroRevisao = await checklistRepository
          .corrigirChecklistFinalizado(
            ordemServicoId: ordemId,
            motivo: 'Avaria identificada após conferência.',
            quilometragem: '1050',
            combustivel: '3/4 tanque',
            itens: novosItens,
          );

      expect(numeroRevisao, 1);

      final database = await AppDatabase.instance.database;
      final ordem = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
        limit: 1,
      );

      expect(ordem, hasLength(1));
      expect(ordem.single['status'], 'Finalizada');
      expect(ordem.single['quilometragem_entrada'], '1050');
      expect(ordem.single['combustivel_entrada'], '3/4 tanque');
      expect(ordem.single['quantidade_revisoes'], 1);
      expect(ordem.single['assinatura_desatualizada'], 1);
      expect(
        ordem.single['motivo_ultima_revisao'],
        'Avaria identificada após conferência.',
      );

      final itemSalvo = await checklistRepository.buscarItemPorId(
        (primeiro['id'] as num).toInt(),
      );

      expect(itemSalvo, isNotNull);
      expect(
        (itemSalvo!['status'] as num).toInt(),
        OrdemServicoChecklistRepository.statusAvaria,
      );
      expect(itemSalvo['marcado'], 1);
      expect(itemSalvo['observacao'], 'Risco profundo');
      expect(itemSalvo['foto_avaria'], '/tmp/avaria_teste.jpg');
      expect(itemSalvo['avaria_localizacao'], 'Porta dianteira esquerda');

      final revisoes = await database.query(
        'ordem_servico_revisoes',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );

      expect(revisoes, hasLength(1));
      expect(revisoes.single['numero_revisao'], 1);
      expect(revisoes.single['tipo'], 'Correcao de checklist');

      final anteriores =
          jsonDecode(revisoes.single['dados_anteriores_json'].toString())
              as Map<String, dynamic>;
      final novos =
          jsonDecode(revisoes.single['dados_novos_json'].toString())
              as Map<String, dynamic>;

      expect(anteriores['dados_entrada']['quilometragem'], '1000');
      expect(novos['dados_entrada']['quilometragem'], '1050');
      expect((novos['itens'] as List).first['observacao'], 'Risco profundo');
    });

    test('recusa checklist sem alteração e não cria revisão', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
        quilometragem: '2000',
        combustivel: 'Cheio',
      );

      final itens = await checklistRepository.listarChecklist(ordemId);

      await expectLater(
        checklistRepository.corrigirChecklistFinalizado(
          ordemServicoId: ordemId,
          motivo: 'Conferência sem mudanças.',
          quilometragem: '2000',
          combustivel: 'Cheio',
          itens: itens,
        ),
        throwsA(isA<StateError>()),
      );

      final database = await AppDatabase.instance.database;
      final revisoes = await database.query(
        'ordem_servico_revisoes',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );

      expect(revisoes, isEmpty);
    });

    test('motivo inválido faz rollback de checklist e quilometragem', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
        quilometragem: '3000',
        combustivel: '1/4 tanque',
      );

      final itens = await checklistRepository.listarChecklist(ordemId);
      final primeiro = Map<String, dynamic>.from(itens.first)
        ..['status'] = OrdemServicoChecklistRepository.statusOk
        ..['marcado'] = 1;

      await expectLater(
        checklistRepository.corrigirChecklistFinalizado(
          ordemServicoId: ordemId,
          motivo: 'abc',
          quilometragem: '9999',
          combustivel: 'Cheio',
          itens: [primeiro, ...itens.skip(1).map(Map<String, dynamic>.from)],
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
      final itemDepois = await checklistRepository.buscarItemPorId(
        (primeiro['id'] as num).toInt(),
      );
      final revisoes = await database.query(
        'ordem_servico_revisoes',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );

      expect(ordem.single['quilometragem_entrada'], '3000');
      expect(ordem.single['combustivel_entrada'], '1/4 tanque');
      expect(ordem.single['quantidade_revisoes'], 0);
      expect(itemDepois, isNotNull);
      expect(
        (itemDepois!['status'] as num).toInt(),
        OrdemServicoChecklistRepository.statusNaoVerificado,
      );
      expect(revisoes, isEmpty);
    });

    test('OS não finalizada rejeita correção e desfaz alterações', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Em andamento',
        quilometragem: '4000',
        combustivel: 'Reserva',
      );

      final itens = await checklistRepository.listarChecklist(ordemId);
      final primeiro = Map<String, dynamic>.from(itens.first)
        ..['status'] = OrdemServicoChecklistRepository.statusOk
        ..['marcado'] = 1;

      await expectLater(
        checklistRepository.corrigirChecklistFinalizado(
          ordemServicoId: ordemId,
          motivo: 'Tentativa em OS não finalizada.',
          quilometragem: '4500',
          combustivel: 'Cheio',
          itens: [primeiro, ...itens.skip(1).map(Map<String, dynamic>.from)],
        ),
        throwsA(isA<StateError>()),
      );

      final database = await AppDatabase.instance.database;
      final ordem = await database.query(
        'ordens_servico',
        where: 'id = ?',
        whereArgs: [ordemId],
        limit: 1,
      );
      final itemDepois = await checklistRepository.buscarItemPorId(
        (primeiro['id'] as num).toInt(),
      );

      expect(ordem.single['status'], 'Em andamento');
      expect(ordem.single['quilometragem_entrada'], '4000');
      expect(ordem.single['combustivel_entrada'], 'Reserva');
      expect(ordem.single['quantidade_revisoes'], 0);
      expect(
        (itemDepois!['status'] as num).toInt(),
        OrdemServicoChecklistRepository.statusNaoVerificado,
      );
    });
  });

  group('Fotos auditadas de OS finalizada', () {
    test('adiciona foto Antes e registra revisão auditada', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
        assinaturaCliente: 'assinaturas/foto.png',
      );

      final fotoId = await fotoRepository.inserirFotoComRevisao(
        ordemServicoId: ordemId,
        etapa: 'Antes',
        caminho: '/tmp/antes_01.jpg',
        motivo: 'Foto inicial adicionada ao registro.',
        descricao: 'Dianteira antes do serviço',
      );

      expect(fotoId, greaterThan(0));

      final fotos = await fotoRepository.listarFotos(ordemId, etapa: 'Antes');
      expect(fotos, hasLength(1));
      expect(fotos.single['id'], fotoId);
      expect(fotos.single['etapa'], 'Antes');
      expect(fotos.single['caminho'], '/tmp/antes_01.jpg');
      expect(fotos.single['descricao'], 'Dianteira antes do serviço');
      expect(fotos.single['ordem'], 0);

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
      );

      expect(ordem.single['quantidade_revisoes'], 1);
      expect(ordem.single['assinatura_desatualizada'], 1);
      expect(revisoes, hasLength(1));
      expect(revisoes.single['tipo'], 'Correcao de fotos');

      final novos =
          jsonDecode(revisoes.single['dados_novos_json'].toString())
              as Map<String, dynamic>;
      expect(novos['acao'], 'foto_adicionada');
      expect(novos['foto_id'], fotoId);
      expect(novos['etapa'], 'Antes');
      expect(novos['quantidade_fotos_etapa'], 1);
    });

    test('mantém ordenação independente entre Antes e Depois', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
      );

      final antes1 = await fotoRepository.inserirFotoComRevisao(
        ordemServicoId: ordemId,
        etapa: 'Antes',
        caminho: '/tmp/antes_a.jpg',
        motivo: 'Primeira foto de antes adicionada.',
      );
      final depois1 = await fotoRepository.inserirFotoComRevisao(
        ordemServicoId: ordemId,
        etapa: 'Depois',
        caminho: '/tmp/depois_a.jpg',
        motivo: 'Primeira foto de depois adicionada.',
      );
      final antes2 = await fotoRepository.inserirFotoComRevisao(
        ordemServicoId: ordemId,
        etapa: 'Antes',
        caminho: '/tmp/antes_b.jpg',
        motivo: 'Segunda foto de antes adicionada.',
      );

      final fotosAntes = await fotoRepository.listarFotos(
        ordemId,
        etapa: 'Antes',
      );
      final fotosDepois = await fotoRepository.listarFotos(
        ordemId,
        etapa: 'Depois',
      );

      expect(fotosAntes, hasLength(2));
      expect(fotosDepois, hasLength(1));
      expect(fotosAntes[0]['id'], antes2);
      expect(fotosAntes[0]['ordem'], 1);
      expect(fotosAntes[1]['id'], antes1);
      expect(fotosAntes[1]['ordem'], 0);
      expect(fotosDepois.single['id'], depois1);
      expect(fotosDepois.single['ordem'], 0);
    });

    test('motivo inválido desfaz a inclusão da foto', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
      );

      await expectLater(
        fotoRepository.inserirFotoComRevisao(
          ordemServicoId: ordemId,
          etapa: 'Depois',
          caminho: '/tmp/deveria_rollback.jpg',
          motivo: 'abc',
        ),
        throwsA(isA<ArgumentError>()),
      );

      final fotos = await fotoRepository.listarFotos(ordemId, etapa: 'Depois');
      final database = await AppDatabase.instance.database;
      final revisoes = await database.query(
        'ordem_servico_revisoes',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
      );

      expect(fotos, isEmpty);
      expect(revisoes, isEmpty);
    });

    test('OS não finalizada desfaz a inclusão da foto', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Em andamento',
      );

      await expectLater(
        fotoRepository.inserirFotoComRevisao(
          ordemServicoId: ordemId,
          etapa: 'Antes',
          caminho: '/tmp/nao_finalizada.jpg',
          motivo: 'Tentativa de correção com OS em andamento.',
        ),
        throwsA(isA<StateError>()),
      );

      expect(await fotoRepository.listarFotos(ordemId), isEmpty);
    });

    test('etapa inválida é recusada sem criar registro', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
      );

      await expectLater(
        fotoRepository.inserirFotoComRevisao(
          ordemServicoId: ordemId,
          etapa: 'Durante',
          caminho: '/tmp/durante.jpg',
          motivo: 'Etapa inválida usada no teste.',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await fotoRepository.listarFotos(ordemId), isEmpty);
    });

    test('exclui foto e registra nova revisão', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
      );

      final fotoId = await fotoRepository.inserirFotoComRevisao(
        ordemServicoId: ordemId,
        etapa: 'Depois',
        caminho: '/tmp/depois_excluir.jpg',
        motivo: 'Foto adicionada para posterior correção.',
        descricao: 'Foto que será removida',
      );

      await fotoRepository.excluirFotoComRevisao(
        fotoId: fotoId,
        motivo: 'Foto incorreta removida do atendimento.',
        excluirArquivo: false,
      );

      final fotos = await fotoRepository.listarFotos(ordemId, etapa: 'Depois');
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
        orderBy: 'numero_revisao ASC',
      );

      expect(fotos, isEmpty);
      expect(ordem.single['quantidade_revisoes'], 2);
      expect(revisoes, hasLength(2));
      expect(revisoes[1]['numero_revisao'], 2);

      final anteriores =
          jsonDecode(revisoes[1]['dados_anteriores_json'].toString())
              as Map<String, dynamic>;
      final novos =
          jsonDecode(revisoes[1]['dados_novos_json'].toString())
              as Map<String, dynamic>;

      expect(anteriores['acao'], 'excluir_foto');
      expect(anteriores['foto']['caminho'], '/tmp/depois_excluir.jpg');
      expect(novos['acao'], 'foto_excluida');
      expect(novos['foto_id'], fotoId);
    });

    test('motivo inválido desfaz a exclusão da foto', () async {
      final ordemId = await _criarOrdem(
        numero: _proximoNumero(() => ++sequencia),
        status: 'Finalizada',
      );

      final fotoId = await fotoRepository.inserirFotoComRevisao(
        ordemServicoId: ordemId,
        etapa: 'Antes',
        caminho: '/tmp/preservar.jpg',
        motivo: 'Foto adicionada antes do teste de rollback.',
      );

      await expectLater(
        fotoRepository.excluirFotoComRevisao(
          fotoId: fotoId,
          motivo: 'abc',
          excluirArquivo: false,
        ),
        throwsA(isA<ArgumentError>()),
      );

      final fotos = await fotoRepository.listarFotos(ordemId, etapa: 'Antes');
      final database = await AppDatabase.instance.database;
      final revisoes = await database.query(
        'ordem_servico_revisoes',
        where: 'ordem_servico_id = ?',
        whereArgs: [ordemId],
        orderBy: 'numero_revisao ASC',
      );

      expect(fotos, hasLength(1));
      expect(fotos.single['id'], fotoId);
      expect(revisoes, hasLength(1));
      expect(revisoes.single['numero_revisao'], 1);
    });
  });
}

String _proximoNumero(int Function() incrementar) {
  final numero = incrementar();
  return 'OS-CHECK-FOTO-${numero.toString().padLeft(4, '0')}';
}

Future<int> _criarOrdem({
  required String numero,
  required String status,
  String? assinaturaCliente,
  String quilometragem = '',
  String combustivel = '',
}) async {
  final database = await AppDatabase.instance.database;

  final clienteId = await database.insert('clientes', {
    'nome': 'Cliente da $numero',
    'telefone': '11999999999',
    'email': 'cliente@teste.com',
    'endereco': 'Rua dos Testes, 100',
    'observacoes': 'Cliente criado por teste automatizado.',
  });

  return database.insert('ordens_servico', {
    'cliente_id': clienteId,
    'numero': numero,
    'status': status,
    'data_abertura': '2026-08-06',
    'data_inicio': status == 'Aberta' ? null : '2026-08-06',
    'data_finalizacao': status == 'Finalizada' ? '2026-08-06' : null,
    'hora_entrada': '08:00',
    'hora_saida': status == 'Finalizada' ? '17:00' : null,
    'funcionario_responsavel': 'Ryan',
    'observacoes': 'OS de teste.',
    'valor_total': 500,
    'desconto': 0,
    'forma_pagamento': 'Pix',
    'quilometragem_entrada': quilometragem,
    'combustivel_entrada': combustivel,
    'assinatura_cliente': assinaturaCliente,
    'lancado_financeiro': status == 'Finalizada' ? 1 : 0,
  });
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}
