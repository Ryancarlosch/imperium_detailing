import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/nota_fiscal_entrada.dart';
import '../models/nota_fiscal_entrada_item.dart';
import '../models/nota_fiscal_importacao_tentativa.dart';

class NotaFiscalEntradaRepository {
  NotaFiscalEntradaRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => AppDatabase.instance.database);

  final Future<Database> Function() _databaseProvider;

  static const _origensPreliminares = {'qrCode', 'codigoBarras', 'chaveManual'};
  static const _canaisTentativa = {
    'xml',
    'qr_direto',
    'portal_assistido',
    'dfe',
    'manual',
  };
  static const _resultadosTentativa = {'sucesso', 'pendente', 'erro'};
  static const _statusImportacaoValidos = {'pendente', 'processada', 'erro'};

  Future<NotaFiscalEntrada?> buscarPorId(int id) async {
    final database = await _databaseProvider();
    return _buscarPorIdExecutor(database, id);
  }

  Future<NotaFiscalEntrada?> buscarPorChave(String chaveAcesso) async {
    final database = await _databaseProvider();
    return _buscarPorChaveExecutor(database, chaveAcesso.trim());
  }

  Future<List<NotaFiscalEntradaItem>> listarItensDaNota(
    int notaFiscalId,
  ) async {
    final database = await _databaseProvider();
    return _listarItensExecutor(database, notaFiscalId);
  }

  Future<List<NotaFiscalEntrada>> listar({
    String? statusImportacao,
    int? modelo,
    String? busca,
  }) async {
    final database = await _databaseProvider();
    final filtros = <String>[];
    final argumentos = <Object?>[];

    final status = statusImportacao?.trim();
    if (status != null && status.isNotEmpty) {
      filtros.add('status_importacao = ?');
      argumentos.add(status);
    }
    if (modelo != null) {
      filtros.add('modelo = ?');
      argumentos.add(modelo);
    }
    final termo = busca?.trim() ?? '';
    if (termo.isNotEmpty) {
      filtros.add('''
        (
          chave_acesso LIKE ?
          OR COALESCE(emitente_nome, '') LIKE ?
          OR COALESCE(emitente_cnpj_cpf, '') LIKE ?
          OR CAST(COALESCE(numero, '') AS TEXT) LIKE ?
        )
      ''');
      final padrao = '%$termo%';
      argumentos.addAll([padrao, padrao, padrao, padrao]);
    }

    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: filtros.isEmpty ? null : filtros.join(' AND '),
      whereArgs: argumentos.isEmpty ? null : argumentos,
      orderBy: 'COALESCE(data_emissao, importada_em) DESC, id DESC',
    );

    return resultado
        .map(
          (item) => NotaFiscalEntrada.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<NotaFiscalImportacaoTentativa>> listarTentativas({
    int? notaFiscalId,
    String? chaveAcesso,
    int limite = 50,
  }) async {
    final database = await _databaseProvider();
    final filtros = <String>[];
    final argumentos = <Object?>[];
    if (notaFiscalId != null) {
      filtros.add('nota_fiscal_id = ?');
      argumentos.add(notaFiscalId);
    }
    final chave = chaveAcesso?.trim() ?? '';
    if (chave.isNotEmpty) {
      filtros.add('chave_acesso = ?');
      argumentos.add(chave);
    }

    final rows = await database.query(
      'nota_fiscal_importacao_tentativas',
      where: filtros.isEmpty ? null : filtros.join(' AND '),
      whereArgs: argumentos.isEmpty ? null : argumentos,
      orderBy: 'criado_em DESC, id DESC',
      limit: limite.clamp(1, 500),
    );
    return rows
        .map(
          (row) => NotaFiscalImportacaoTentativa.fromMap(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  Future<void> vincularFornecedor(int notaFiscalId, int fornecedorId) async {
    final database = await _databaseProvider();
    await database.update(
      'notas_fiscais_entrada',
      {'fornecedor_id': fornecedorId},
      where: 'id = ?',
      whereArgs: [notaFiscalId],
    );
  }

  Future<void> vincularItemEstoque(int itemFiscalId, int estoqueItemId) async {
    final database = await _databaseProvider();
    await database.update(
      'notas_fiscais_entrada_itens',
      {'estoque_item_id': estoqueItemId},
      where: 'id = ?',
      whereArgs: [itemFiscalId],
    );
  }

  Future<NotaFiscalEntrada> atualizarIdentificacaoPreliminar({
    required String chaveAcesso,
    required int modelo,
    required int numero,
    required int serie,
    required String emitenteCnpjCpf,
  }) async {
    final database = await _databaseProvider();
    await database.update(
      'notas_fiscais_entrada',
      {
        'modelo': modelo,
        'numero': numero,
        'serie': serie,
        'emitente_cnpj_cpf': emitenteCnpjCpf,
      },
      where: 'chave_acesso = ? AND status_importacao != ?',
      whereArgs: [chaveAcesso.trim(), 'processada'],
    );
    final atualizada = await buscarPorChave(chaveAcesso.trim());
    if (atualizada == null) {
      throw StateError('Nota preliminar não encontrada após identificação.');
    }
    return atualizada;
  }

  Future<NotaFiscalEntrada> registrarPreliminar({
    required String chaveAcesso,
    required String origemImportacao,
    required String importadaEm,
    String? consultaUrl,
  }) async {
    final chave = chaveAcesso.trim();
    if (chave.length != 44) {
      throw ArgumentError('A chave de acesso deve ter 44 caracteres.');
    }
    if (!_origensPreliminares.contains(origemImportacao)) {
      throw ArgumentError('Origem inválida para nota preliminar.');
    }

    final url = _textoNulo(consultaUrl);
    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      final existente = await _buscarPorChaveExecutor(transaction, chave);
      if (existente != null) {
        if (url != null &&
            (existente.consultaUrl ?? '').trim().isEmpty &&
            await _colunaExisteExecutor(
              transaction,
              'notas_fiscais_entrada',
              'consulta_url',
            )) {
          await transaction.update(
            'notas_fiscais_entrada',
            {'consulta_url': url},
            where: 'id = ?',
            whereArgs: [existente.id],
          );
          return (await _buscarPorIdExecutor(transaction, existente.id!))!;
        }
        return existente;
      }

      final dados = <String, Object?>{
        'chave_acesso': chave,
        'situacao_fiscal': 'desconhecida',
        'status_importacao': 'pendente',
        'origem_importacao': origemImportacao,
        'importada_em': importadaEm,
      };
      if (url != null &&
          await _colunaExisteExecutor(
            transaction,
            'notas_fiscais_entrada',
            'consulta_url',
          )) {
        dados['consulta_url'] = url;
      }
      final id = await transaction.insert('notas_fiscais_entrada', dados);

      final criado = await _buscarPorIdExecutor(transaction, id);
      if (criado == null) {
        throw StateError('Nota preliminar não encontrada após inserção.');
      }
      return criado;
    });
  }

  Future<NotaFiscalEntrada?> registrarTentativa({
    required String chaveAcesso,
    required int? modelo,
    required String canal,
    required String resultado,
    String codigo = '',
    String mensagem = '',
    String? url,
    String? statusImportacao,
    DateTime? momento,
  }) async {
    final chave = chaveAcesso.trim();
    if (chave.length != 44) {
      throw ArgumentError('Chave fiscal inválida para registrar tentativa.');
    }
    if (!_canaisTentativa.contains(canal)) {
      throw ArgumentError('Canal fiscal inválido: $canal.');
    }
    if (!_resultadosTentativa.contains(resultado)) {
      throw ArgumentError('Resultado fiscal inválido: $resultado.');
    }
    if (statusImportacao != null &&
        !_statusImportacaoValidos.contains(statusImportacao)) {
      throw ArgumentError('Status de importação inválido: $statusImportacao.');
    }

    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      final nota = await _buscarPorChaveExecutor(transaction, chave);
      final agora = (momento ?? DateTime.now()).toIso8601String();
      await transaction.insert('nota_fiscal_importacao_tentativas', {
        'nota_fiscal_id': nota?.id,
        'chave_acesso': chave,
        'modelo': modelo,
        'canal': canal,
        'resultado': resultado,
        'codigo': codigo.trim(),
        'mensagem': mensagem.trim(),
        'url': _textoNulo(url),
        'criado_em': agora,
      });

      if (nota == null) return null;

      final dados = <String, Object?>{
        'tentativas_importacao': nota.tentativasImportacao + 1,
        'ultima_tentativa_em': agora,
        'ultimo_erro_codigo': resultado == 'sucesso' ? '' : codigo.trim(),
        'ultimo_erro_mensagem': resultado == 'sucesso' ? '' : mensagem.trim(),
      };
      if (statusImportacao != null) {
        dados['status_importacao'] = statusImportacao;
      }
      final urlLimpa = _textoNulo(url);
      if (urlLimpa != null && (nota.consultaUrl ?? '').trim().isEmpty) {
        dados['consulta_url'] = urlLimpa;
      }

      await transaction.update(
        'notas_fiscais_entrada',
        dados,
        where: 'id = ?',
        whereArgs: [nota.id],
      );
      return _buscarPorIdExecutor(transaction, nota.id!);
    });
  }

  Future<NotaFiscalEntrada> salvarNotaCompleta({
    required NotaFiscalEntrada nota,
    required List<NotaFiscalEntradaItem> itens,
    bool removerItensAusentes = false,
  }) async {
    _validarNotaCompleta(nota);
    _validarItens(itens);

    final database = await _databaseProvider();
    return database.transaction((transaction) async {
      final existente = await _buscarPorChaveExecutor(
        transaction,
        nota.chaveAcesso.trim(),
      );

      final int notaId;
      if (existente == null) {
        notaId = await transaction.insert(
          'notas_fiscais_entrada',
          await _filtrarColunasExistentes(
            transaction,
            'notas_fiscais_entrada',
            _dadosNotaCompleta(nota),
          ),
        );
      } else {
        notaId = existente.id!;
        final integrada = await _possuiIntegracoes(transaction, notaId);
        if (integrada) {
          final atuais = await _listarItensExecutor(transaction, notaId);
          _validarReimportacaoIntegrada(
            existente: existente,
            nova: nota,
            atuais: atuais,
            novos: itens,
          );
          await transaction.update(
            'notas_fiscais_entrada',
            await _filtrarColunasExistentes(
              transaction,
              'notas_fiscais_entrada',
              _dadosReimportacaoIntegrada(existente, nota),
            ),
            where: 'id = ?',
            whereArgs: [notaId],
          );
        } else {
          await transaction.update(
            'notas_fiscais_entrada',
            await _filtrarColunasExistentes(
              transaction,
              'notas_fiscais_entrada',
              _dadosFiscaisAtualizados(existente, nota),
            ),
            where: 'id = ?',
            whereArgs: [notaId],
          );
          await _salvarItens(
            transaction,
            notaId: notaId,
            itens: itens,
            removerItensAusentes: removerItensAusentes,
          );
        }
      }

      if (existente == null) {
        await _salvarItens(
          transaction,
          notaId: notaId,
          itens: itens,
          removerItensAusentes: removerItensAusentes,
        );
      }

      final salva = await _buscarPorIdExecutor(transaction, notaId);
      if (salva == null) {
        throw StateError('Nota não encontrada após processamento.');
      }
      return salva;
    });
  }

  Future<void> excluirNota(int id) async {
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      if (await _possuiIntegracoes(transaction, id)) {
        throw StateError(
          'A nota possui integração com estoque ou financeiro. '
          'Use "Corrigir / excluir nota" para desfazer as integrações com segurança.',
        );
      }
      await transaction.delete(
        'notas_fiscais_entrada',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> _salvarItens(
    DatabaseExecutor transaction, {
    required int notaId,
    required List<NotaFiscalEntradaItem> itens,
    required bool removerItensAusentes,
  }) async {
    final numerosRecebidos = <int>{};
    for (final item in itens) {
      if (!numerosRecebidos.add(item.numeroItem)) {
        throw ArgumentError(
          'Não é permitido repetir numeroItem na mesma nota.',
        );
      }

      final dados = item.toMap(incluirId: false)..['nota_fiscal_id'] = notaId;
      final atual = await transaction.query(
        'notas_fiscais_entrada_itens',
        where: 'nota_fiscal_id = ? AND numero_item = ?',
        whereArgs: [notaId, item.numeroItem],
        limit: 1,
      );

      if (atual.isEmpty) {
        await transaction.insert('notas_fiscais_entrada_itens', dados);
      } else {
        // Preserva vínculo de estoque já confirmado manualmente quando a fonte
        // fiscal nova não informa esse vínculo local.
        if (dados['estoque_item_id'] == null &&
            atual.first['estoque_item_id'] != null) {
          dados['estoque_item_id'] = atual.first['estoque_item_id'];
        }
        await transaction.update(
          'notas_fiscais_entrada_itens',
          dados,
          where: 'id = ?',
          whereArgs: [atual.first['id']],
        );
      }
    }

    if (!removerItensAusentes) return;
    final atuais = await transaction.query(
      'notas_fiscais_entrada_itens',
      columns: ['id', 'numero_item'],
      where: 'nota_fiscal_id = ?',
      whereArgs: [notaId],
    );
    for (final atual in atuais) {
      if (!numerosRecebidos.contains(_int(atual['numero_item']))) {
        await transaction.delete(
          'notas_fiscais_entrada_itens',
          where: 'id = ?',
          whereArgs: [atual['id']],
        );
      }
    }
  }

  Future<bool> _possuiIntegracoes(
    DatabaseExecutor database,
    int notaFiscalId,
  ) async {
    if (await _tabelaExisteExecutor(database, 'movimentacoes_estoque')) {
      final estoque =
          Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT COUNT(*)
              FROM movimentacoes_estoque
              WHERE nota_fiscal_id = ?
                AND origem = 'Nota fiscal de entrada'
              ''',
              [notaFiscalId],
            ),
          ) ??
          0;
      if (estoque > 0) return true;
    }

    if (!await _tabelaExisteExecutor(database, 'movimentos_financeiros')) {
      return false;
    }
    final financeiro =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*)
            FROM movimentos_financeiros
            WHERE nota_fiscal_id = ?
              AND origem = 'Nota fiscal de entrada'
              AND status != 'Cancelado'
            ''',
            [notaFiscalId],
          ),
        ) ??
        0;
    return financeiro > 0;
  }

  Future<bool> _colunaExisteExecutor(
    DatabaseExecutor database,
    String tabela,
    String coluna,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($tabela)');
    return rows.any((row) => row['name']?.toString() == coluna);
  }

  Future<Map<String, dynamic>> _filtrarColunasExistentes(
    DatabaseExecutor database,
    String tabela,
    Map<String, dynamic> dados,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($tabela)');
    final colunas = rows.map((row) => row['name']?.toString()).toSet();
    return Map<String, dynamic>.fromEntries(
      dados.entries.where((entry) => colunas.contains(entry.key)),
    );
  }

  Future<bool> _tabelaExisteExecutor(
    DatabaseExecutor database,
    String tabela,
  ) async {
    final rows = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tabela],
    );
    return rows.isNotEmpty;
  }

  void _validarReimportacaoIntegrada({
    required NotaFiscalEntrada existente,
    required NotaFiscalEntrada nova,
    required List<NotaFiscalEntradaItem> atuais,
    required List<NotaFiscalEntradaItem> novos,
  }) {
    bool diferente(double? a, double? b) {
      if (a == null || b == null) return a != b;
      return (a - b).abs() > 0.01;
    }

    if ((existente.modelo != null && existente.modelo != nova.modelo) ||
        diferente(existente.valorTotal, nova.valorTotal) ||
        (existente.numero != null && existente.numero != nova.numero) ||
        (existente.serie != null && existente.serie != nova.serie)) {
      throw StateError(
        'A nova fonte fiscal diverge de uma nota que já possui estoque/financeiro. '
        'Use a tela de correção para desfazer as integrações antes de substituir os dados.',
      );
    }

    final porNumero = {for (final item in atuais) item.numeroItem: item};
    if (porNumero.length != novos.length) {
      throw StateError(
        'A quantidade de itens mudou em uma nota já integrada. '
        'Desfaça as integrações antes de reimportar.',
      );
    }
    for (final novo in novos) {
      final atual = porNumero[novo.numeroItem];
      if (atual == null ||
          (atual.quantidade - novo.quantidade).abs() > 0.000001 ||
          (atual.valorTotal - novo.valorTotal).abs() > 0.01) {
        throw StateError(
          'Os itens da nova fonte divergem de uma nota já integrada. '
          'Desfaça as integrações antes de reimportar.',
        );
      }
    }
  }

  Future<List<NotaFiscalEntradaItem>> _listarItensExecutor(
    DatabaseExecutor database,
    int notaFiscalId,
  ) async {
    final resultado = await database.query(
      'notas_fiscais_entrada_itens',
      where: 'nota_fiscal_id = ?',
      whereArgs: [notaFiscalId],
      orderBy: 'numero_item ASC',
    );
    return resultado
        .map(
          (item) =>
              NotaFiscalEntradaItem.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<NotaFiscalEntrada?> _buscarPorChaveExecutor(
    DatabaseExecutor database,
    String chave,
  ) async {
    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: 'chave_acesso = ?',
      whereArgs: [chave],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return NotaFiscalEntrada.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Future<NotaFiscalEntrada?> _buscarPorIdExecutor(
    DatabaseExecutor database,
    int id,
  ) async {
    final resultado = await database.query(
      'notas_fiscais_entrada',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (resultado.isEmpty) return null;
    return NotaFiscalEntrada.fromMap(
      Map<String, dynamic>.from(resultado.first),
    );
  }

  Map<String, dynamic> _dadosNotaCompleta(NotaFiscalEntrada nota) {
    return nota.toMap(incluirId: false)
      ..['chave_acesso'] = nota.chaveAcesso.trim()
      ..['status_importacao'] = 'processada'
      ..['ultimo_erro_codigo'] = ''
      ..['ultimo_erro_mensagem'] = '';
  }

  Map<String, dynamic> _dadosFiscaisAtualizados(
    NotaFiscalEntrada existente,
    NotaFiscalEntrada nova,
  ) {
    return <String, dynamic>{
      'modelo': nova.modelo,
      'numero': nova.numero,
      'serie': nova.serie,
      'data_emissao': nova.dataEmissao,
      'fornecedor_id': existente.fornecedorId ?? nova.fornecedorId,
      'emitente_cnpj_cpf': nova.emitenteCnpjCpf,
      'emitente_nome': nova.emitenteNome,
      'valor_produtos': nova.valorProdutos,
      'valor_frete': nova.valorFrete,
      'valor_seguro': nova.valorSeguro,
      'valor_desconto': nova.valorDesconto,
      'valor_outras_despesas': nova.valorOutrasDespesas,
      'valor_ipi': nova.valorIpi,
      'valor_icms_st': nova.valorIcmsSt,
      'valor_total': nova.valorTotal,
      'situacao_fiscal': nova.situacaoFiscal,
      'status_importacao': 'processada',
      'origem_importacao': existente.origemImportacao,
      'xml_original': nova.xmlOriginal ?? existente.xmlOriginal,
      'xml_hash': nova.xmlHash ?? existente.xmlHash,
      'consulta_url': existente.consultaUrl ?? nova.consultaUrl,
      'ultimo_erro_codigo': '',
      'ultimo_erro_mensagem': '',
      'importada_em': existente.importadaEm,
      'observacoes': existente.observacoes,
    };
  }

  Map<String, dynamic> _dadosReimportacaoIntegrada(
    NotaFiscalEntrada existente,
    NotaFiscalEntrada nova,
  ) {
    return <String, dynamic>{
      'situacao_fiscal': nova.situacaoFiscal,
      'status_importacao': 'processada',
      'xml_original': nova.xmlOriginal ?? existente.xmlOriginal,
      'xml_hash': nova.xmlHash ?? existente.xmlHash,
      'consulta_url': existente.consultaUrl ?? nova.consultaUrl,
      'ultimo_erro_codigo': '',
      'ultimo_erro_mensagem': '',
    };
  }

  void _validarNotaCompleta(NotaFiscalEntrada nota) {
    if (nota.chaveAcesso.trim().length != 44) {
      throw ArgumentError('A chave de acesso deve ter 44 caracteres.');
    }
    if (nota.modelo != 55 && nota.modelo != 65) {
      throw ArgumentError('Modelo fiscal deve ser 55 ou 65.');
    }
    if (nota.numero == null || nota.serie == null) {
      throw ArgumentError('Número e série são obrigatórios.');
    }
    if ((nota.dataEmissao ?? '').trim().isEmpty) {
      throw ArgumentError('Data de emissão é obrigatória.');
    }
    if ((nota.emitenteNome ?? '').trim().isEmpty ||
        (nota.emitenteCnpjCpf ?? '').trim().isEmpty) {
      throw ArgumentError('Nome e CNPJ/CPF do emitente são obrigatórios.');
    }
    if (nota.valorTotal == null || !nota.valorTotal!.isFinite) {
      throw ArgumentError('Valor total é obrigatório e deve ser válido.');
    }
  }

  void _validarItens(List<NotaFiscalEntradaItem> itens) {
    if (itens.isEmpty) {
      throw ArgumentError('A nota fiscal precisa possuir ao menos um item.');
    }
    for (final item in itens) {
      if (item.numeroItem <= 0 || item.descricao.trim().isEmpty) {
        throw ArgumentError('Item fiscal inválido.');
      }
      if (!item.quantidade.isFinite || item.quantidade <= 0) {
        throw ArgumentError(
          'Quantidade fiscal inválida no item ${item.numeroItem}.',
        );
      }
      if (!item.valorUnitario.isFinite || item.valorUnitario < 0) {
        throw ArgumentError(
          'Valor unitário inválido no item ${item.numeroItem}.',
        );
      }
      if (!item.valorTotal.isFinite || item.valorTotal < 0) {
        throw ArgumentError('Valor total inválido no item ${item.numeroItem}.');
      }
    }
  }

  static int _int(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  static String? _textoNulo(String? valor) {
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? null : texto;
  }
}
