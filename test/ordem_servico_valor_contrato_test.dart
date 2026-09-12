import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/domain/ordem_servico_valor.dart';
import 'package:imperium_detailing/models/ordem_servico.dart';

void main() {
  test('contrato calcula os valores oficiais da OS', () {
    expect(
      OrdemServicoValor.valorNegociado(valorTotal: 600, desconto: 250),
      350,
    );

    expect(
      OrdemServicoValor.valorNegociado(
        valorTotal: 1000,
        desconto: 100,
        descontoNegociacao: 50,
        acrescimoNegociacao: 25,
        jurosParcelamento: 10,
      ),
      885,
    );

    expect(
      OrdemServicoValor.valorNegociado(
        valorTotal: 100,
        desconto: 150,
        acrescimoNegociacao: 100,
      ),
      100,
    );

    expect(
      OrdemServicoValor.valorNegociado(
        valorTotal: 100,
        descontoNegociacao: 150,
      ),
      0,
    );
  });

  test('model OrdemServico usa o mesmo contrato', () {
    const ordem = OrdemServico(
      clienteId: 1,
      numero: 'OS-CONTRATO',
      status: 'Finalizada',
      dataAbertura: '2026-09-11',
      valorTotal: 1000,
      desconto: 100,
      descontoNegociacao: 50,
      acrescimoNegociacao: 25,
      jurosParcelamento: 10,
    );

    expect(ordem.valorFinal, 900);
    expect(ordem.valorNegociado, 885);
  });

  test('expressao SQL oficial contem todos os componentes', () {
    final sql = OrdemServicoValor.sqlValorNegociado(alias: 'os');

    expect(sql, contains('os.valor_total'));
    expect(sql, contains('os.desconto'));
    expect(sql, contains('os.desconto_negociacao'));
    expect(sql, contains('os.acrescimo_negociacao'));
    expect(sql, contains('os.juros_parcelamento'));
  });

  test('alias SQL invalido e rejeitado', () {
    expect(
      () => OrdemServicoValor.sqlValorNegociado(
        alias: 'os; DROP TABLE ordens_servico',
      ),
      throwsArgumentError,
    );
  });
}
