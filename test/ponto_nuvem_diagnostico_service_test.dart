import 'package:flutter_test/flutter_test.dart';
import 'package:imperium_detailing/services/ponto_nuvem_diagnostico_service.dart';

void main() {
  group('PontoNuvemDiagnosticoService.avaliar', () {
    test('considera saudável somente backend completo da mesma empresa', () {
      final resultado = PontoNuvemDiagnosticoService.avaliar(
        remoto: const {
          'backend_version': 6,
          'empresa_id': 'empresa-a',
          'rpc_batida_online': true,
          'rpc_batida_offline': true,
          'tabela_idempotencia': true,
          'realtime_ponto_registros': true,
          'sync_estado_disponivel': true,
          'migracao_concluida': true,
        },
        empresaEsperadaId: 'empresa-a',
        empresaAtualId: 'empresa-a',
      );

      expect(resultado['saudavel'], isTrue);
      expect(resultado['empresa_confere'], isTrue);
    });

    test('bloqueia diagnóstico de outra empresa', () {
      final resultado = PontoNuvemDiagnosticoService.avaliar(
        remoto: const {
          'backend_version': 6,
          'empresa_id': 'empresa-b',
          'rpc_batida_online': true,
          'rpc_batida_offline': true,
          'tabela_idempotencia': true,
          'realtime_ponto_registros': true,
          'sync_estado_disponivel': true,
          'migracao_concluida': true,
        },
        empresaEsperadaId: 'empresa-a',
        empresaAtualId: 'empresa-a',
      );

      expect(resultado['saudavel'], isFalse);
      expect(resultado['empresa_confere'], isFalse);
    });

    test('backend antigo não pode ser marcado como saudável', () {
      final resultado = PontoNuvemDiagnosticoService.avaliar(
        remoto: const {
          'backend_version': 5,
          'empresa_id': 'empresa-a',
          'rpc_batida_online': true,
          'rpc_batida_offline': true,
          'tabela_idempotencia': true,
          'realtime_ponto_registros': true,
          'sync_estado_disponivel': true,
          'migracao_concluida': true,
        },
        empresaEsperadaId: 'empresa-a',
        empresaAtualId: 'empresa-a',
      );

      expect(resultado['saudavel'], isFalse);
      expect(resultado['backend_atualizado'], isFalse);
    });
  });
}
