import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/nota_fiscal_entrada.dart';
import '../repositories/nota_fiscal_entrada_repository.dart';
import 'nota_fiscal_dfe_backend_service.dart';

enum FiscalIntegridadeNivel { critico, atencao, informacao }

class FiscalIntegridadeItem {
  const FiscalIntegridadeItem({
    required this.nivel,
    required this.titulo,
    required this.detalhe,
    this.notaFiscalId,
  });

  final FiscalIntegridadeNivel nivel;
  final String titulo;
  final String detalhe;
  final int? notaFiscalId;
}

class FiscalIntegridadeResumo {
  const FiscalIntegridadeResumo({
    required this.totalNotas,
    required this.processadas,
    required this.pendentes,
    required this.erros,
    required this.autorizadas,
    required this.comEstoque,
    required this.comFinanceiro,
    required this.itensSemVinculo,
    required this.itens,
  });

  final int totalNotas;
  final int processadas;
  final int pendentes;
  final int erros;
  final int autorizadas;
  final int comEstoque;
  final int comFinanceiro;
  final int itensSemVinculo;
  final List<FiscalIntegridadeItem> itens;

  int get criticos => itens
      .where((item) => item.nivel == FiscalIntegridadeNivel.critico)
      .length;
  int get atencoes => itens
      .where((item) => item.nivel == FiscalIntegridadeNivel.atencao)
      .length;
}

class NotaFiscalIntegridadeService {
  NotaFiscalIntegridadeService({
    Future<Database> Function()? databaseProvider,
    NotaFiscalEntradaRepository? repository,
    NotaFiscalDfeBackendService? dfeBackend,
  }) : _databaseProvider =
           databaseProvider ?? (() => AppDatabase.instance.database),
       _repository = repository ?? NotaFiscalEntradaRepository(),
       _dfeBackend = dfeBackend ?? NotaFiscalDfeBackendService();

  final Future<Database> Function() _databaseProvider;
  final NotaFiscalEntradaRepository _repository;
  final NotaFiscalDfeBackendService _dfeBackend;

  Future<DfeBackendStatus> diagnosticarDfe() => _dfeBackend.diagnosticar();

  Future<FiscalIntegridadeResumo> diagnosticarLocal() async {
    final db = await _databaseProvider();
    final notas = await _repository.listar();
    final alertas = <FiscalIntegridadeItem>[];

    var processadas = 0;
    var pendentes = 0;
    var erros = 0;
    var autorizadas = 0;
    var comEstoque = 0;
    var comFinanceiro = 0;
    var itensSemVinculo = 0;

    for (final nota in notas) {
      if (nota.statusImportacao == 'processada') processadas++;
      if (nota.statusImportacao == 'pendente') pendentes++;
      if (nota.statusImportacao == 'erro') erros++;
      if (nota.situacaoFiscal == 'autorizada') autorizadas++;
      final id = nota.id;
      if (id == null) continue;

      final itens = await _repository.listarItensDaNota(id);
      if (nota.processada && itens.isEmpty) {
        alertas.add(
          FiscalIntegridadeItem(
            nivel: FiscalIntegridadeNivel.critico,
            titulo: 'Nota processada sem itens',
            detalhe: _identificacao(nota),
            notaFiscalId: id,
          ),
        );
      }

      if (nota.processada && nota.situacaoFiscal != 'autorizada') {
        alertas.add(
          FiscalIntegridadeItem(
            nivel: FiscalIntegridadeNivel.atencao,
            titulo: 'Situação fiscal exige revisão',
            detalhe:
                '${_identificacao(nota)} está ${nota.situacaoFiscal}. Estoque e financeiro ficam bloqueados até autorização.',
            notaFiscalId: id,
          ),
        );
      }

      final somaItens = itens.fold<double>(
        0,
        (soma, item) => soma + item.valorTotal,
      );
      final valorProdutos = nota.valorProdutos;
      if (nota.processada && valorProdutos != null && itens.isNotEmpty) {
        final tolerancia = math.max(0.05, valorProdutos.abs() * 0.0001);
        if ((somaItens - valorProdutos).abs() > tolerancia) {
          alertas.add(
            FiscalIntegridadeItem(
              nivel: FiscalIntegridadeNivel.critico,
              titulo: 'Soma dos itens diverge da nota',
              detalhe:
                  '${_identificacao(nota)}: itens R\$ ${somaItens.toStringAsFixed(2)} x produtos R\$ ${valorProdutos.toStringAsFixed(2)}.',
              notaFiscalId: id,
            ),
          );
        }
      }

      final semVinculo = itens
          .where((item) => item.estoqueItemId == null)
          .length;
      itensSemVinculo += semVinculo;
      if (nota.processada &&
          nota.situacaoFiscal == 'autorizada' &&
          semVinculo > 0) {
        alertas.add(
          FiscalIntegridadeItem(
            nivel: FiscalIntegridadeNivel.informacao,
            titulo: 'Itens ainda não vinculados ao estoque',
            detalhe:
                '${_identificacao(nota)} possui $semVinculo item(ns) sem vínculo.',
            notaFiscalId: id,
          ),
        );
      }

      if (nota.processada && nota.fornecedorId == null) {
        alertas.add(
          FiscalIntegridadeItem(
            nivel: FiscalIntegridadeNivel.informacao,
            titulo: 'Fornecedor ainda não vinculado',
            detalhe: _identificacao(nota),
            notaFiscalId: id,
          ),
        );
      }

      final estoque = await _resumoEstoque(db, id);
      if (estoque.movimentos > 0) comEstoque++;
      if (estoque.duplicados > 0) {
        alertas.add(
          FiscalIntegridadeItem(
            nivel: FiscalIntegridadeNivel.critico,
            titulo: 'Entrada de estoque duplicada',
            detalhe:
                '${_identificacao(nota)} possui ${estoque.duplicados} item(ns) com mais de uma entrada fiscal ativa.',
            notaFiscalId: id,
          ),
        );
      }

      final financeiro = await _resumoFinanceiro(db, id);
      if (financeiro.quantidade > 0) comFinanceiro++;
      if (financeiro.quantidade > 0 && nota.valorTotal != null) {
        final diferenca = (financeiro.valorAtivo - nota.valorTotal!).abs();
        if (diferenca > 0.02) {
          alertas.add(
            FiscalIntegridadeItem(
              nivel: FiscalIntegridadeNivel.critico,
              titulo: 'Financeiro não reconcilia com a nota',
              detalhe:
                  '${_identificacao(nota)}: lançamentos ativos R\$ ${financeiro.valorAtivo.toStringAsFixed(2)} x nota R\$ ${nota.valorTotal!.toStringAsFixed(2)}.',
              notaFiscalId: id,
            ),
          );
        }
      }

      if (nota.situacaoFiscal != 'autorizada' &&
          (estoque.movimentos > 0 || financeiro.quantidade > 0)) {
        alertas.add(
          FiscalIntegridadeItem(
            nivel: FiscalIntegridadeNivel.critico,
            titulo: 'Documento não autorizado possui integração ativa',
            detalhe:
                '${_identificacao(nota)} está ${nota.situacaoFiscal}, mas possui estoque e/ou financeiro vinculados. Use Corrigir / excluir nota.',
            notaFiscalId: id,
          ),
        );
      }

      if (nota.statusImportacao != 'processada' && nota.possuiFalhaImportacao) {
        alertas.add(
          FiscalIntegridadeItem(
            nivel: FiscalIntegridadeNivel.atencao,
            titulo: 'Importação pendente',
            detalhe: '${_identificacao(nota)}: ${nota.ultimoErroMensagem}',
            notaFiscalId: id,
          ),
        );
      }
    }

    return FiscalIntegridadeResumo(
      totalNotas: notas.length,
      processadas: processadas,
      pendentes: pendentes,
      erros: erros,
      autorizadas: autorizadas,
      comEstoque: comEstoque,
      comFinanceiro: comFinanceiro,
      itensSemVinculo: itensSemVinculo,
      itens: alertas,
    );
  }

  Future<_EstoqueResumo> _resumoEstoque(Database db, int notaId) async {
    if (!await _tabelaExiste(db, 'movimentacoes_estoque')) {
      return const _EstoqueResumo(0, 0);
    }
    final movimentos =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*)
            FROM movimentacoes_estoque
            WHERE nota_fiscal_id = ?
              AND nota_fiscal_item_id IS NOT NULL
              AND tipo = 'ENTRADA'
              AND origem = 'Nota fiscal de entrada'
            ''',
            [notaId],
          ),
        ) ??
        0;
    final duplicados =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*) FROM (
              SELECT nota_fiscal_item_id
              FROM movimentacoes_estoque
              WHERE nota_fiscal_id = ?
                AND nota_fiscal_item_id IS NOT NULL
                AND tipo = 'ENTRADA'
                AND origem = 'Nota fiscal de entrada'
              GROUP BY nota_fiscal_item_id
              HAVING COUNT(*) > 1
            )
            ''',
            [notaId],
          ),
        ) ??
        0;
    return _EstoqueResumo(movimentos, duplicados);
  }

  Future<_FinanceiroResumo> _resumoFinanceiro(Database db, int notaId) async {
    if (!await _tabelaExiste(db, 'movimentos_financeiros')) {
      return const _FinanceiroResumo(0, 0);
    }
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS quantidade, COALESCE(SUM(valor), 0) AS valor
      FROM movimentos_financeiros
      WHERE nota_fiscal_id = ?
        AND origem = 'Nota fiscal de entrada'
        AND status != 'Cancelado'
      ''',
      [notaId],
    );
    return _FinanceiroResumo(
      _int(rows.first['quantidade']),
      _double(rows.first['valor']),
    );
  }

  Future<bool> _tabelaExiste(Database db, String tabela) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tabela],
    );
    return rows.isNotEmpty;
  }

  static String _identificacao(NotaFiscalEntrada nota) =>
      '${nota.modelo == 65 ? 'NFC-e' : 'NF-e'} ${nota.numero ?? '-'} · ${nota.emitenteNome ?? nota.emitenteCnpjCpf ?? 'emitente não informado'}';

  static int _int(dynamic valor) =>
      valor is num ? valor.toInt() : int.tryParse(valor?.toString() ?? '') ?? 0;
  static double _double(dynamic valor) => valor is num
      ? valor.toDouble()
      : double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

class _EstoqueResumo {
  const _EstoqueResumo(this.movimentos, this.duplicados);
  final int movimentos;
  final int duplicados;
}

class _FinanceiroResumo {
  const _FinanceiroResumo(this.quantidade, this.valorAtivo);
  final int quantidade;
  final double valorAtivo;
}
