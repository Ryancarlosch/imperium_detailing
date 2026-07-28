import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _abrirBanco();
    return _database!;
  }

  Future<Database> _abrirBanco() async {
    final pastaBanco = await getDatabasesPath();

    final caminho = join(
      pastaBanco,
      'imperium_detailing.db',
    );

    return openDatabase(
      caminho,
      version: 5,
      onConfigure: (database) async {
        await database.execute(
          'PRAGMA foreign_keys = ON',
        );
      },
      onCreate: (database, version) async {
        await _criarTabelas(database);
      },
      onUpgrade: (
        database,
        versaoAntiga,
        versaoNova,
      ) async {
        if (versaoAntiga < 2) {
          await _criarTabelaVeiculos(database);
        }

        if (versaoAntiga < 3) {
          await _criarTabelaAgendamentos(database);
        }

        if (versaoAntiga < 4) {
          await _criarTabelaFotos(database);
        }

        if (versaoAntiga < 5) {
          await _criarTabelaMovimentosFinanceiros(
            database,
          );
        }
      },
    );
  }

  Future<void> _criarTabelas(
    Database database,
  ) async {
    await _criarTabelaClientes(database);
    await _criarTabelaVeiculos(database);
    await _criarTabelaAgendamentos(database);
    await _criarTabelaFotos(database);
    await _criarTabelaMovimentosFinanceiros(
      database,
    );
  }

  Future<void> _criarTabelaClientes(
    Database database,
  ) async {
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

  Future<void> _criarTabelaVeiculos(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE veiculos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id INTEGER NOT NULL,
        marca TEXT NOT NULL,
        modelo TEXT NOT NULL,
        placa TEXT,
        cor TEXT,
        ano TEXT,
        observacoes TEXT,
        FOREIGN KEY (cliente_id)
          REFERENCES clientes (id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _criarTabelaAgendamentos(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE agendamentos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id INTEGER NOT NULL,
        veiculo_id INTEGER NOT NULL,
        servico TEXT NOT NULL,
        data TEXT NOT NULL,
        hora TEXT NOT NULL,
        valor REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Agendado',
        observacoes TEXT,
        FOREIGN KEY (cliente_id)
          REFERENCES clientes (id)
          ON DELETE CASCADE,
        FOREIGN KEY (veiculo_id)
          REFERENCES veiculos (id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _criarTabelaFotos(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE fotos_servico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id INTEGER NOT NULL,
        veiculo_id INTEGER NOT NULL,
        caminho_antes TEXT NOT NULL,
        caminho_depois TEXT NOT NULL,
        descricao TEXT,
        data TEXT NOT NULL,
        FOREIGN KEY (cliente_id)
          REFERENCES clientes (id)
          ON DELETE CASCADE,
        FOREIGN KEY (veiculo_id)
          REFERENCES veiculos (id)
          ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _criarTabelaMovimentosFinanceiros(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE movimentos_financeiros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT NOT NULL,
        descricao TEXT NOT NULL,
        valor REAL NOT NULL DEFAULT 0,
        forma_pagamento TEXT,
        data TEXT NOT NULL,
        cliente_id INTEGER,
        agendamento_id INTEGER,
        FOREIGN KEY (cliente_id)
          REFERENCES clientes (id)
          ON DELETE SET NULL,
        FOREIGN KEY (agendamento_id)
          REFERENCES agendamentos (id)
          ON DELETE SET NULL
      )
    ''');
  }
}
