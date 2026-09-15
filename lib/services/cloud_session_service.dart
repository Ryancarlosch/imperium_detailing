import 'dart:math';

import '../database/app_database.dart';
import '../repositories/usuario_repository.dart';
import 'empresa_cloud_service.dart';
import 'imperium_auth_service.dart';
import 'supabase_bootstrap.dart';

class SelecaoEmpresaNecessaria implements Exception {
  SelecaoEmpresaNecessaria(this.empresas);

  final List<Map<String, dynamic>> empresas;

  @override
  String toString() => 'Selecione a empresa que deseja abrir.';
}

class CloudSessionService {
  CloudSessionService._();

  static final CloudSessionService instance = CloudSessionService._();

  final EmpresaCloudService _empresaService = EmpresaCloudService.instance;
  final UsuarioRepository _usuarios = UsuarioRepository();

  Future<List<Map<String, dynamic>>> listarEmpresasDoUsuario() async {
    final client = SupabaseBootstrap.client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) {
      return const [];
    }

    try {
      await client.rpc('imperium_resgatar_convite');
    } catch (_) {
      // Sem convite pendente ou RPC indisponível: segue com vínculos existentes.
    }

    return _empresaService.listarEmpresasVinculadas();
  }

  Future<Map<String, dynamic>> prepararSessao({String? empresaId}) async {
    final client = SupabaseBootstrap.client;
    final user = client?.auth.currentUser;

    if (client == null || user == null) {
      throw StateError('Entre com e-mail e senha para continuar.');
    }

    final empresas = await listarEmpresasDoUsuario();
    if (empresas.isEmpty) {
      throw StateError(
        'Sua conta está autenticada, mas ainda não possui uma empresa ativa vinculada ao Imperium.',
      );
    }

    final selecionada = await _resolverEmpresa(empresas, empresaId: empresaId);
    final id = (selecionada['empresa_id'] ?? '').toString().trim();
    final papel = (selecionada['papel'] ?? '').toString().trim().toLowerCase();

    if (id.isEmpty) {
      throw StateError('Empresa inválida.');
    }

    if (papel == 'funcionario') {
      throw StateError(
        'O acesso por e-mail e senha é exclusivo da empresa. '
        'Funcionários são cadastrados e gerenciados pelo administrador dentro do Imperium.',
      );
    }

    if (papel != 'admin' && papel != 'proprietario') {
      throw StateError('Seu perfil de acesso não é reconhecido pelo Imperium.');
    }

    await _empresaService.trocarEmpresa(id);
    await _usuarios.garantirEstrutura();
    final usuarios = await _usuarios.listarUsuarios(incluirInativos: false);

    Map<String, dynamic>? administrador;
    for (final usuario in usuarios) {
      if ((usuario['perfil'] ?? '').toString() ==
          UsuarioRepository.perfilAdministrador) {
        administrador = usuario;
        break;
      }
    }

    if (administrador == null) {
      throw StateError('Administrador local não encontrado para esta empresa.');
    }

    final usuarioId = _int(administrador['id']);
    final login = (administrador['login'] ?? 'admin').toString().trim();

    if (usuarioId <= 0 || login.isEmpty) {
      throw StateError('Administrador local inválido.');
    }

    final pin = _pinCompatibilidade();
    await _usuarios.definirPin(usuarioId: usuarioId, pin: pin);

    return _usuarios.autenticar(login: login, pin: pin, manterConectado: true);
  }

  Future<Map<String, dynamic>> _resolverEmpresa(
    List<Map<String, dynamic>> empresas, {
    String? empresaId,
  }) async {
    final solicitado = empresaId?.trim() ?? '';

    if (solicitado.isNotEmpty) {
      for (final empresa in empresas) {
        if ((empresa['empresa_id'] ?? '').toString() == solicitado) {
          return empresa;
        }
      }
      throw StateError('Sua conta não possui acesso ativo a esta empresa.');
    }

    final atual = (await AppDatabase.instance.empresaAtivaId ?? '').trim();
    if (atual.isNotEmpty) {
      for (final empresa in empresas) {
        if ((empresa['empresa_id'] ?? '').toString() == atual) {
          return empresa;
        }
      }
    }

    if (empresas.length == 1) {
      return empresas.first;
    }

    throw SelecaoEmpresaNecessaria(
      empresas.map((item) => Map<String, dynamic>.from(item)).toList(),
    );
  }

  Future<void> sair() async {
    try {
      await _usuarios.sair();
    } finally {
      await ImperiumAuthService.instance.sair();
    }
  }

  String _pinCompatibilidade() {
    final random = Random.secure();
    return (10000000 + random.nextInt(90000000)).toString();
  }

  int _int(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
