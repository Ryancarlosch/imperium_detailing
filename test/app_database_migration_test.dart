import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/database/app_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pastaTemporaria;
  late String caminhoBanco;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    pastaTemporaria = await Directory.systemTemp.createTemp(
      'imperium_database_migration_test_',
    );

    await databaseFactory.setDatabasesPath(pastaTemporaria.path);

    caminhoBanco = path.join(pastaTemporaria.path, 'imperium_detailing.db');
  });

  setUp(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDown(() async {
    await _removerBancoDeTeste(caminhoBanco);
  });

  tearDownAll(() async {
    if (await pastaTemporaria.exists()) {
      await pastaTemporaria.delete(recursive: true);
    }
  });

  group('AppDatabase - migrações com preservação de dados', () {
    test(
      'migra da versão 19 para 28 preservando cliente, OS e financeiro legado',
      () async {
        await _criarBancoLegado(
          caminhoBanco: caminhoBanco,
          versao: 19,
          cliente: const _ClienteLegado(
            id: 101,
            nome: 'Cliente legado versão 19',
            telefone: '11999999999',
            email: 'cliente19@teste.com',
            endereco: 'Rua do Teste, 19',
            observacoes: 'Registro criado antes do arquivamento.',
          ),
          ordem: const _OrdemServicoLegada(
            id: 201,
            clienteId: 101,
            numero: 'OS-LEGADA-019',
            status: 'Finalizada',
            dataAbertura: '2026-01-10T08:00:00.000',
            dataFinalizacao: '2026-01-10T17:30:00.000',
            funcionarioResponsavel: 'Ryan',
            observacoes: 'OS criada no banco versão 19.',
            valorTotal: 850.75,
            desconto: 50,
            formaPagamento: 'Pix',
            quilometragemEntrada: '84500',
            combustivelEntrada: 'Meio tanque',
            assinaturaCliente: 'assinatura_legada_v19',
            lancadoFinanceiro: 1,
          ),
        );

        final database = await AppDatabase.instance.database;

        expect(await database.getVersion(), AppDatabase.schemaVersion);
        expect(AppDatabase.schemaVersion, 30);

        final cliente = await database.query(
          'clientes',
          where: 'id = ?',
          whereArgs: [101],
          limit: 1,
        );

        expect(cliente, hasLength(1));
        expect(cliente.single['nome'], 'Cliente legado versão 19');
        expect(cliente.single['telefone'], '11999999999');
        expect(cliente.single['email'], 'cliente19@teste.com');
        expect(cliente.single['endereco'], 'Rua do Teste, 19');
        expect(
          cliente.single['observacoes'],
          'Registro criado antes do arquivamento.',
        );
        expect(cliente.single['ativo'], 1);
        expect(cliente.single['arquivado_em'], isNull);

        final ordem = await database.query(
          'ordens_servico',
          where: 'id = ?',
          whereArgs: [201],
          limit: 1,
        );

        expect(ordem, hasLength(1));
        expect(ordem.single['cliente_id'], 101);
        expect(ordem.single['numero'], 'OS-LEGADA-019');
        expect(ordem.single['status'], 'Finalizada');
        expect((ordem.single['valor_total'] as num).toDouble(), 850.75);
        expect((ordem.single['desconto'] as num).toDouble(), 50.0);
        expect(ordem.single['forma_pagamento'], 'Pix');
        expect(ordem.single['assinatura_cliente'], 'assinatura_legada_v19');
        expect(ordem.single['lancado_financeiro'], 1);

        expect(ordem.single['revisada_em'], isNull);
        expect(ordem.single['motivo_ultima_revisao'], '');
        expect(ordem.single['quantidade_revisoes'], 0);
        expect(ordem.single['assinatura_desatualizada'], 0);
        expect(ordem.single['status_pagamento'], 'Pago');
        expect((ordem.single['valor_recebido'] as num).toDouble(), 800.75);
        expect(ordem.single['vencimento_pagamento'], isNull);

        final pagamentos = await database.query(
          'ordem_servico_pagamentos',
          where: 'ordem_servico_id = ?',
          whereArgs: [201],
        );

        expect(pagamentos, hasLength(1));
        expect(pagamentos.single['status'], 'Pago');
        expect((pagamentos.single['valor'] as num).toDouble(), 800.75);
        expect(pagamentos.single['forma_pagamento'], 'Pix');

        final revisoes = await database.query(
          'ordem_servico_revisoes',
          where: 'ordem_servico_id = ?',
          whereArgs: [201],
        );

        expect(revisoes, isEmpty);

        final violacoes = await database.rawQuery('PRAGMA foreign_key_check');

        expect(violacoes, isEmpty);
      },
    );

    test(
      'migra da versão 20 para 28 preservando cliente arquivado, OS e pagamento',
      () async {
        const arquivadoEm = '2026-02-15T14:20:00.000';

        await _criarBancoLegado(
          caminhoBanco: caminhoBanco,
          versao: 20,
          cliente: const _ClienteLegado(
            id: 102,
            nome: 'Cliente arquivado versão 20',
            telefone: '11888888888',
            email: 'cliente20@teste.com',
            endereco: 'Avenida do Teste, 20',
            observacoes: 'Cliente já arquivado antes da versão 21.',
            ativo: 0,
            arquivadoEm: arquivadoEm,
          ),
          ordem: const _OrdemServicoLegada(
            id: 202,
            clienteId: 102,
            numero: 'OS-LEGADA-020',
            status: 'Finalizada',
            dataAbertura: '2026-02-12T09:00:00.000',
            dataFinalizacao: '2026-02-12T18:00:00.000',
            funcionarioResponsavel: 'Ryan',
            observacoes: 'OS vinculada a cliente arquivado.',
            valorTotal: 1200,
            desconto: 100,
            formaPagamento: 'Cartão de crédito',
            quilometragemEntrada: '42000',
            combustivelEntrada: '3/4',
            assinaturaCliente: 'assinatura_legada_v20',
            lancadoFinanceiro: 1,
          ),
        );

        final database = await AppDatabase.instance.database;

        expect(await database.getVersion(), 30);

        final cliente = await database.query(
          'clientes',
          where: 'id = ?',
          whereArgs: [102],
          limit: 1,
        );

        expect(cliente, hasLength(1));
        expect(cliente.single['nome'], 'Cliente arquivado versão 20');
        expect(cliente.single['ativo'], 0);
        expect(cliente.single['arquivado_em'], arquivadoEm);

        final ordem = await database.query(
          'ordens_servico',
          where: 'id = ?',
          whereArgs: [202],
          limit: 1,
        );

        expect(ordem, hasLength(1));
        expect(ordem.single['cliente_id'], 102);
        expect(ordem.single['numero'], 'OS-LEGADA-020');
        expect(ordem.single['status'], 'Finalizada');
        expect((ordem.single['valor_total'] as num).toDouble(), 1200.0);
        expect(ordem.single['assinatura_cliente'], 'assinatura_legada_v20');

        expect(ordem.single['revisada_em'], isNull);
        expect(ordem.single['motivo_ultima_revisao'], '');
        expect(ordem.single['quantidade_revisoes'], 0);
        expect(ordem.single['assinatura_desatualizada'], 0);
        expect(ordem.single['status_pagamento'], 'Pago');
        expect((ordem.single['valor_recebido'] as num).toDouble(), 1100.0);
        expect(ordem.single['vencimento_pagamento'], isNull);

        final pagamentos = await database.query(
          'ordem_servico_pagamentos',
          where: 'ordem_servico_id = ?',
          whereArgs: [202],
        );

        expect(pagamentos, hasLength(1));
        expect(pagamentos.single['status'], 'Pago');
        expect((pagamentos.single['valor'] as num).toDouble(), 1100.0);
        expect(pagamentos.single['forma_pagamento'], 'Cartão de crédito');

        final revisaoId = await database.insert('ordem_servico_revisoes', {
          'ordem_servico_id': 202,
          'numero_revisao': 1,
          'tipo': 'Teste de migração',
          'motivo': 'Confirmar que a tabela migrada aceita revisões.',
          'dados_anteriores_json': '{"status":"Finalizada"}',
          'dados_novos_json': '{"status":"Finalizada"}',
          'criado_em': '2026-02-16T10:00:00.000',
        });

        expect(revisaoId, greaterThan(0));

        final revisoes = await database.query(
          'ordem_servico_revisoes',
          where: 'ordem_servico_id = ?',
          whereArgs: [202],
        );

        expect(revisoes, hasLength(1));
        expect(revisoes.single['numero_revisao'], 1);
        expect(revisoes.single['tipo'], 'Teste de migração');

        final violacoes = await database.rawQuery('PRAGMA foreign_key_check');

        expect(violacoes, isEmpty);
      },
    );

    test(
      'migra da versão 21 vinculando movimento financeiro legado à OS',
      () async {
        await _criarBancoVersao21ComMovimentoLegado(caminhoBanco);

        final database = await AppDatabase.instance.database;

        expect(await database.getVersion(), 30);

        final ordem = await database.query(
          'ordens_servico',
          where: 'id = ?',
          whereArgs: [301],
          limit: 1,
        );
        expect(ordem, hasLength(1));
        expect(ordem.single['status_pagamento'], 'Pago');
        expect((ordem.single['valor_recebido'] as num).toDouble(), 600.0);

        final pagamentos = await database.query(
          'ordem_servico_pagamentos',
          where: 'ordem_servico_id = ?',
          whereArgs: [301],
        );
        expect(pagamentos, hasLength(1));

        final movimentos = await database.query(
          'movimentos_financeiros',
          where: 'id = ?',
          whereArgs: [401],
          limit: 1,
        );
        expect(movimentos, hasLength(1));
        expect(movimentos.single['ordem_servico_id'], 301);
        expect(movimentos.single['pagamento_id'], pagamentos.single['id']);

        final violacoes = await database.rawQuery('PRAGMA foreign_key_check');
        expect(violacoes, isEmpty);
      },
    );

    test(
      'migra da versão 22 para 28 preservando pagamentos e inicializando taxas',
      () async {
        await _criarBancoVersao22ComPagamento(caminhoBanco);

        final database = await AppDatabase.instance.database;

        expect(await database.getVersion(), 30);

        final ordem = await database.query(
          'ordens_servico',
          where: 'id = ?',
          whereArgs: [601],
          limit: 1,
        );

        expect(ordem, hasLength(1));
        expect((ordem.single['desconto_negociacao'] as num).toDouble(), 0);
        expect((ordem.single['acrescimo_negociacao'] as num).toDouble(), 0);
        expect((ordem.single['juros_parcelamento'] as num).toDouble(), 0);

        final pagamentos = await database.query(
          'ordem_servico_pagamentos',
          where: 'id = ?',
          whereArgs: [701],
          limit: 1,
        );

        expect(pagamentos, hasLength(1));
        expect((pagamentos.single['valor'] as num).toDouble(), 400);
        expect(pagamentos.single['taxa_percentual'], isNull);
        expect((pagamentos.single['taxa_operacao'] as num).toDouble(), 0);
        expect((pagamentos.single['valor_liquido'] as num).toDouble(), 400);

        final ajustes = await database.query(
          'ordem_servico_ajustes_financeiros',
          where: 'ordem_servico_id = ?',
          whereArgs: [601],
        );

        expect(ajustes, isEmpty);

        final violacoes = await database.rawQuery('PRAGMA foreign_key_check');
        expect(violacoes, isEmpty);
      },
    );
  });
}

Future<void> _criarBancoVersao22ComPagamento(String caminhoBanco) async {
  final database = await databaseFactory.openDatabase(
    caminhoBanco,
    options: OpenDatabaseOptions(
      version: 22,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE clientes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            telefone TEXT,
            email TEXT,
            endereco TEXT,
            observacoes TEXT,
            ativo INTEGER NOT NULL DEFAULT 1,
            arquivado_em TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE ordens_servico (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cliente_id INTEGER NOT NULL,
            numero TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'Aberta',
            data_abertura TEXT NOT NULL,
            data_inicio TEXT,
            data_finalizacao TEXT,
            valor_total REAL NOT NULL DEFAULT 0,
            desconto REAL NOT NULL DEFAULT 0,
            forma_pagamento TEXT,
            lancado_financeiro INTEGER NOT NULL DEFAULT 0,
            status_pagamento TEXT NOT NULL DEFAULT 'Pendente',
            valor_recebido REAL NOT NULL DEFAULT 0,
            vencimento_pagamento TEXT,
            pagamento_atualizado_em TEXT,
            FOREIGN KEY (cliente_id)
              REFERENCES clientes (id)
              ON DELETE CASCADE
          )
        ''');

        await database.execute('''
          CREATE TABLE ordem_servico_pagamentos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ordem_servico_id INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'Pago',
            valor REAL NOT NULL DEFAULT 0,
            forma_pagamento TEXT NOT NULL DEFAULT '',
            data_pagamento TEXT,
            parcela_numero INTEGER,
            total_parcelas INTEGER,
            vencimento TEXT,
            comprovante_caminho TEXT,
            observacoes TEXT NOT NULL DEFAULT '',
            estornado_em TEXT,
            motivo_estorno TEXT NOT NULL DEFAULT '',
            criado_em TEXT NOT NULL,
            atualizado_em TEXT NOT NULL,
            FOREIGN KEY (ordem_servico_id)
              REFERENCES ordens_servico (id)
              ON DELETE CASCADE
          )
        ''');

        await database.insert('clientes', {
          'id': 501,
          'nome': 'Cliente versão 22',
        });

        await database.insert('ordens_servico', {
          'id': 601,
          'cliente_id': 501,
          'numero': 'OS-LEGADA-022',
          'status': 'Finalizada',
          'data_abertura': '2026-07-01',
          'data_finalizacao': '2026-07-01',
          'valor_total': 1000,
          'desconto': 100,
          'forma_pagamento': 'Cartão de crédito',
          'lancado_financeiro': 1,
          'status_pagamento': 'Parcialmente pago',
          'valor_recebido': 400,
          'pagamento_atualizado_em': '2026-07-01T18:00:00.000',
        });

        await database.insert('ordem_servico_pagamentos', {
          'id': 701,
          'ordem_servico_id': 601,
          'status': 'Pago',
          'valor': 400,
          'forma_pagamento': 'Cartão de crédito',
          'data_pagamento': '2026-07-01T18:00:00.000',
          'observacoes': 'Pagamento existente antes da versão 23.',
          'criado_em': '2026-07-01T18:00:00.000',
          'atualizado_em': '2026-07-01T18:00:00.000',
        });
      },
    ),
  );

  await database.close();
}

Future<void> _criarBancoVersao21ComMovimentoLegado(String caminhoBanco) async {
  final database = await databaseFactory.openDatabase(
    caminhoBanco,
    options: OpenDatabaseOptions(
      version: 21,
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE clientes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            telefone TEXT,
            email TEXT,
            endereco TEXT,
            observacoes TEXT,
            ativo INTEGER NOT NULL DEFAULT 1,
            arquivado_em TEXT
          )
        ''');

        await database.execute('''
          CREATE TABLE ordens_servico (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            orcamento_id INTEGER,
            agendamento_id INTEGER,
            cliente_id INTEGER NOT NULL,
            veiculo_id INTEGER,
            numero TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'Aberta',
            data_abertura TEXT NOT NULL,
            data_inicio TEXT,
            data_finalizacao TEXT,
            hora_entrada TEXT,
            hora_saida TEXT,
            funcionario_responsavel TEXT NOT NULL DEFAULT '',
            observacoes TEXT NOT NULL DEFAULT '',
            valor_total REAL NOT NULL DEFAULT 0,
            desconto REAL NOT NULL DEFAULT 0,
            forma_pagamento TEXT,
            quilometragem_entrada TEXT NOT NULL DEFAULT '',
            combustivel_entrada TEXT NOT NULL DEFAULT '',
            assinatura_cliente TEXT,
            lancado_financeiro INTEGER NOT NULL DEFAULT 0,
            revisada_em TEXT,
            motivo_ultima_revisao TEXT NOT NULL DEFAULT '',
            quantidade_revisoes INTEGER NOT NULL DEFAULT 0,
            assinatura_desatualizada INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (cliente_id) REFERENCES clientes (id) ON DELETE CASCADE
          )
        ''');

        await database.execute('''
          CREATE UNIQUE INDEX idx_ordens_servico_numero
          ON ordens_servico (numero)
        ''');

        await database.execute('''
          CREATE TABLE movimentos_financeiros (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tipo TEXT NOT NULL,
            descricao TEXT NOT NULL,
            valor REAL NOT NULL DEFAULT 0,
            forma_pagamento TEXT,
            data TEXT NOT NULL,
            cliente_id INTEGER,
            agendamento_id INTEGER
          )
        ''');

        await database.insert('clientes', {
          'id': 201,
          'nome': 'Cliente versão 21',
          'telefone': '11977777777',
        });

        await database.insert('ordens_servico', {
          'id': 301,
          'cliente_id': 201,
          'numero': 'OS-LEGADA-021',
          'status': 'Finalizada',
          'data_abertura': '2026-03-01T08:00:00.000',
          'data_finalizacao': '2026-03-01T17:00:00.000',
          'valor_total': 650,
          'desconto': 50,
          'forma_pagamento': 'Pix',
          'lancado_financeiro': 1,
        });

        await database.insert('movimentos_financeiros', {
          'id': 401,
          'tipo': 'entrada',
          'descricao': 'Ordem de Serviço finalizada: OS-LEGADA-021',
          'valor': 600,
          'forma_pagamento': 'Pix',
          'data': '2026-03-01T17:00:00.000',
          'cliente_id': 201,
        });
      },
    ),
  );

  await database.close();
}

Future<void> _criarBancoLegado({
  required String caminhoBanco,
  required int versao,
  required _ClienteLegado cliente,
  required _OrdemServicoLegada ordem,
}) async {
  if (versao != 19 && versao != 20) {
    throw ArgumentError.value(
      versao,
      'versao',
      'O teste suporta somente as versões legadas 19 e 20.',
    );
  }

  final database = await databaseFactory.openDatabase(
    caminhoBanco,
    options: OpenDatabaseOptions(
      version: versao,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, _) async {
        await _criarEstruturaLegada(database, possuiArquivamento: versao >= 20);

        await database.insert(
          'clientes',
          cliente.toMap(possuiArquivamento: versao >= 20),
        );

        await database.insert('ordens_servico', ordem.toMap());
      },
    ),
  );

  await database.close();
}

Future<void> _criarEstruturaLegada(
  Database database, {
  required bool possuiArquivamento,
}) async {
  if (possuiArquivamento) {
    await database.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        telefone TEXT,
        email TEXT,
        endereco TEXT,
        observacoes TEXT,
        ativo INTEGER NOT NULL DEFAULT 1,
        arquivado_em TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_clientes_ativo_nome
      ON clientes (ativo, nome COLLATE NOCASE)
    ''');
  } else {
    await database.execute('''
      CREATE TABLE clientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        telefone TEXT,
        email TEXT,
        endereco TEXT,
        observacoes TEXT
      )
    ''');
  }

  await database.execute('''
    CREATE TABLE ordens_servico (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      orcamento_id INTEGER,
      agendamento_id INTEGER,
      cliente_id INTEGER NOT NULL,
      veiculo_id INTEGER,
      numero TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'Aberta',
      data_abertura TEXT NOT NULL,
      data_inicio TEXT,
      data_finalizacao TEXT,
      hora_entrada TEXT,
      hora_saida TEXT,
      funcionario_responsavel TEXT NOT NULL DEFAULT '',
      observacoes TEXT NOT NULL DEFAULT '',
      valor_total REAL NOT NULL DEFAULT 0,
      desconto REAL NOT NULL DEFAULT 0,
      forma_pagamento TEXT,
      quilometragem_entrada TEXT NOT NULL DEFAULT '',
      combustivel_entrada TEXT NOT NULL DEFAULT '',
      assinatura_cliente TEXT,
      lancado_financeiro INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (cliente_id)
        REFERENCES clientes (id)
        ON DELETE CASCADE
    )
  ''');

  await database.execute('''
    CREATE UNIQUE INDEX idx_ordens_servico_numero
    ON ordens_servico (numero)
  ''');
}

Future<void> _removerBancoDeTeste(String caminhoBanco) async {
  await AppDatabase.instance.fecharBanco();

  if (await databaseFactory.databaseExists(caminhoBanco)) {
    await databaseFactory.deleteDatabase(caminhoBanco);
  }
}

class _ClienteLegado {
  const _ClienteLegado({
    required this.id,
    required this.nome,
    required this.telefone,
    required this.email,
    required this.endereco,
    required this.observacoes,
    this.ativo,
    this.arquivadoEm,
  });

  final int id;
  final String nome;
  final String telefone;
  final String email;
  final String endereco;
  final String observacoes;
  final int? ativo;
  final String? arquivadoEm;

  Map<String, Object?> toMap({required bool possuiArquivamento}) {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'email': email,
      'endereco': endereco,
      'observacoes': observacoes,
      if (possuiArquivamento) 'ativo': ativo ?? 1,
      if (possuiArquivamento) 'arquivado_em': arquivadoEm,
    };
  }
}

class _OrdemServicoLegada {
  const _OrdemServicoLegada({
    required this.id,
    required this.clienteId,
    required this.numero,
    required this.status,
    required this.dataAbertura,
    required this.dataFinalizacao,
    required this.funcionarioResponsavel,
    required this.observacoes,
    required this.valorTotal,
    required this.desconto,
    required this.formaPagamento,
    required this.quilometragemEntrada,
    required this.combustivelEntrada,
    required this.assinaturaCliente,
    required this.lancadoFinanceiro,
  });

  final int id;
  final int clienteId;
  final String numero;
  final String status;
  final String dataAbertura;
  final String dataFinalizacao;
  final String funcionarioResponsavel;
  final String observacoes;
  final double valorTotal;
  final double desconto;
  final String formaPagamento;
  final String quilometragemEntrada;
  final String combustivelEntrada;
  final String assinaturaCliente;
  final int lancadoFinanceiro;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'numero': numero,
      'status': status,
      'data_abertura': dataAbertura,
      'data_finalizacao': dataFinalizacao,
      'funcionario_responsavel': funcionarioResponsavel,
      'observacoes': observacoes,
      'valor_total': valorTotal,
      'desconto': desconto,
      'forma_pagamento': formaPagamento,
      'quilometragem_entrada': quilometragemEntrada,
      'combustivel_entrada': combustivelEntrada,
      'assinatura_cliente': assinaturaCliente,
      'lancado_financeiro': lancadoFinanceiro,
    };
  }
}
