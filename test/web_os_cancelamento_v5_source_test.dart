import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancelamento Web usa RPC V5 com CAS e idempotencia', () {
    final source = File(
      'lib/services/web_os_cancelamento_v5_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20260917121925_os_cloud_v5_cancelamento_web_transacional.sql',
    ).readAsStringSync();

    expect(source, contains('class WebOsCancelamentoV5Service'));
    expect(source, contains("'imperium_os_cancelar_web_v5'"));
    expect(source, contains("ordem['atualizado_em']"));
    expect(source, contains('sha256'));
    expect(source, contains('web-cancelar-'));
    expect(source, contains("status == 'Finalizada'"));
    expect(source, contains("status != 'Aberta' && status != 'Em andamento'"));
    expect(source, isNot(contains("import 'dart:io'")));

    expect(migration.toLowerCase(), contains('security invoker'));
    expect(migration, contains('imperium_os_cancelamentos_web'));
    expect(migration, contains('imperium_estoque_liberar_reserva_os'));
    expect(migration, contains("status = 'Cancelado'"));
    expect(migration, contains("status = 'Cancelada'"));
    expect(migration, contains("v_os.status = 'Finalizada'"));
    expect(migration, contains('p_os_atualizado_em'));
    expect(migration, contains('idempotency_key'));
    expect(migration, contains('grant execute on function'));
    expect(migration, contains('to authenticated'));
    expect(migration, contains('from public, anon'));
  });
}
