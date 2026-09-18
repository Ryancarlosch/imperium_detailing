import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'acesso do funcionario usa realtime seguro sem expor tabelas sensiveis',
    () {
      final migration = File(
        'supabase/migrations/20260918023902_funcionario_acesso_realtime_seguro_v1.sql',
      ).readAsStringSync();
      final realtime = File(
        'lib/services/funcionario_acesso_realtime_service.dart',
      ).readAsStringSync();
      final inicio = File(
        'lib/screens/usuario_inicio_page.dart',
      ).readAsStringSync();

      expect(
        migration,
        contains('public.imperium_funcionario_realtime_sinais'),
      );
      expect(migration, contains('auth_user_id = (select auth.uid())'));
      expect(migration, contains('alter publication supabase_realtime'));
      expect(migration, contains('trg_imperium_funcionario_realtime_sinal'));
      expect(migration, contains('permissoes,'));
      expect(migration, contains('ativo,'));
      expect(migration, contains('auth_user_id,'));
      expect(migration, contains('permitir_novo_dispositivo,'));
      expect(migration, isNot(contains('update of ultimo_acesso_em')));
      expect(
        migration,
        isNot(
          contains('grant select on table public.imperium_funcionario_acessos'),
        ),
      );
      expect(
        migration,
        isNot(
          contains(
            'grant select on table public.imperium_funcionario_dispositivos',
          ),
        ),
      );

      expect(
        realtime,
        contains("table: 'imperium_funcionario_realtime_sinais'"),
      );
      expect(realtime, contains("column: 'auth_user_id'"));
      expect(realtime, contains('value: userId'));
      expect(realtime, contains('bool _pendente = false;'));
      expect(realtime, contains('do {'));
      expect(realtime, contains('} while (_pendente);'));
      expect(realtime, contains('await client.removeChannel(channel);'));

      expect(
        inicio,
        contains(
          "import '../services/funcionario_acesso_realtime_service.dart';",
        ),
      );
      expect(inicio, contains('unawaited(_iniciarRealtimeAcesso())'));
      expect(
        inicio,
        contains('onAtualizar: () => _sincronizar(silencioso: true)'),
      );
      expect(inicio, contains('_sincronizacaoPendente = true;'));
      expect(inicio, contains('final repetir = _sincronizacaoPendente;'));
      expect(inicio, contains('await _acessoRealtime.cancelar();'));
      expect(inicio, contains('await _acesso.sairSupabase();'));

      // Mantém polling, resume e refresh manual como fallback.
      expect(inicio, contains("Timer.periodic(const Duration(seconds: 90)"));
      expect(inicio, contains('state == AppLifecycleState.resumed'));
    },
  );
}
