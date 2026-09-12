import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/domain/ordem_servico_valor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  test('SQL e Dart calculam exatamente o mesmo valor negociado', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );

    try {
      await database.execute('''
        CREATE TABLE ordens_servico (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          valor_total REAL,
          desconto REAL,
          desconto_negociacao REAL,
          acrescimo_negociacao REAL,
          juros_parcelamento REAL
        )
      ''');

      final casos = <Map<String, Object?>>[
        {
          'valor_total': 600.0,
          'desconto': 250.0,
          'desconto_negociacao': 0.0,
          'acrescimo_negociacao': 0.0,
          'juros_parcelamento': 0.0,
        },
        {
          'valor_total': 1000.0,
          'desconto': 100.0,
          'desconto_negociacao': 50.0,
          'acrescimo_negociacao': 25.0,
          'juros_parcelamento': 10.0,
        },
        {
          'valor_total': 100.0,
          'desconto': 150.0,
          'desconto_negociacao': 0.0,
          'acrescimo_negociacao': 100.0,
          'juros_parcelamento': 0.0,
        },
        {
          'valor_total': 100.0,
          'desconto': 0.0,
          'desconto_negociacao': 150.0,
          'acrescimo_negociacao': 0.0,
          'juros_parcelamento': 0.0,
        },
      ];

      for (final caso in casos) {
        final id = await database.insert('ordens_servico', caso);

        final resultado = await database.rawQuery(
          '''
          SELECT
            ${OrdemServicoValor.sqlValorNegociado(alias: 'os')} AS valor
          FROM ordens_servico os
          WHERE os.id = ?
          ''',
          [id],
        );

        final valorSql = (resultado.single['valor'] as num).toDouble();
        final valorDart = OrdemServicoValor.valorNegociadoDeMapa(caso);

        expect(valorSql, closeTo(valorDart, 0.000001));
      }
    } finally {
      await database.close();
    }
  });

  test('decomposicao da DRE preserva o liquido oficial da OS', () {
    const casos =
        <
          ({
            double total,
            double desconto,
            double descontoNegociacao,
            double acrescimo,
            double juros,
          })
        >[
          (
            total: 600,
            desconto: 250,
            descontoNegociacao: 0,
            acrescimo: 0,
            juros: 0,
          ),
          (
            total: 1000,
            desconto: 100,
            descontoNegociacao: 50,
            acrescimo: 25,
            juros: 10,
          ),
          (
            total: 100,
            desconto: 150,
            descontoNegociacao: 0,
            acrescimo: 100,
            juros: 0,
          ),
        ];

    for (final caso in casos) {
      final bruto = caso.total + caso.acrescimo + caso.juros;
      final liquido = OrdemServicoValor.valorNegociado(
        valorTotal: caso.total,
        desconto: caso.desconto,
        descontoNegociacao: caso.descontoNegociacao,
        acrescimoNegociacao: caso.acrescimo,
        jurosParcelamento: caso.juros,
      );
      final deducoesEfetivas = bruto - liquido;

      expect(bruto - deducoesEfetivas, closeTo(liquido, 0.000001));
      expect(deducoesEfetivas, greaterThanOrEqualTo(0));
    }
  });
}
