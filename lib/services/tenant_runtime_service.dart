import 'package:flutter/foundation.dart';

/// Reinicia a árvore do aplicativo após troca física de banco/tenant.
class TenantRuntimeService {
  TenantRuntimeService._();

  static final TenantRuntimeService instance = TenantRuntimeService._();

  final ValueNotifier<int> revisao = ValueNotifier<int>(0);

  void reiniciarAplicacao() {
    revisao.value = revisao.value + 1;
  }
}
