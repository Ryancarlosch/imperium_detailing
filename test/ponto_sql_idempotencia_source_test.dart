import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SQL mestre contém a RPC offline idempotente do Ponto', () {
    final arquivo = File('imperium_supabase_ponto_operacoes.sql');

    expect(
      arquivo.existsSync(),
      isTrue,
      reason: 'O SQL mestre do Ponto precisa permanecer versionado.',
    );

    final sql = arquivo.readAsStringSync();

    expect(
      sql,
      contains('create table if not exists public.ponto_batidas_idempotencia'),
    );
    expect(
      sql,
      contains(
        'create or replace function public.ponto_registrar_batida_offline',
      ),
    );
    expect(
      sql,
      contains('A chave de idempotência já foi usada com outro conteúdo.'),
    );
    expect(sql, contains('-- Proteção multiaparelho V5:'));
    expect(sql, contains("'repetida', true"));
  });
}
