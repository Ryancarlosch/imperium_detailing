import '../database/app_database.dart';
import '../repositories/configuracao_repository.dart';
import '../repositories/saude_sistema_repository.dart';
import 'configuracao_arquivos_cloud_service.dart';
import 'configuracao_cloud_service.dart';
import 'crm_orcamentos_cloud_v2_service.dart';
import 'estoque_cloud_conflito_service.dart';
import 'financeiro_cloud_v2_service.dart';
import 'migracao_final_auditoria_service.dart';
import 'operacional_cloud_v2_service.dart';
import 'operacional_sync_service.dart';
import 'os_arquivos_cloud_v2_service.dart';
import 'os_cloud_v3_service.dart';
import 'precificacao_cloud_v2_service.dart';
import 'sync_motor_service.dart';

class MigracaoFinalGateItem {
  const MigracaoFinalGateItem({
    required this.chave,
    required this.titulo,
    required this.detalhe,
    required this.ok,
  });

  final String chave;
  final String titulo;
  final String detalhe;
  final bool ok;
}

class MigracaoFinalGateV2Resultado {
  const MigracaoFinalGateV2Resultado({
    required this.empresaId,
    required this.itens,
    required this.auditoria,
    required this.conflitosPorModulo,
  });

  final String empresaId;
  final List<MigracaoFinalGateItem> itens;
  final MigracaoFinalAuditoriaResultado auditoria;
  final Map<String, int> conflitosPorModulo;

  int get bloqueios => itens.where((item) => !item.ok).length;

  int get conflitosTotal =>
      conflitosPorModulo.values.fold<int>(0, (total, valor) => total + valor);

  bool get prontoParaPromover => bloqueios == 0 && auditoria.tudoConfere;
}

/// Gate técnico V2 antes da promoção SQLite -> Cloud.
///
/// Não escreve em nenhuma tabela de negócio. Ele consolida a saúde local,
/// estado do motor de sync, filas, conflitos, Storage, backup e a auditoria
/// SQLite x Cloud V1.
class MigracaoFinalGateV2Service {
  MigracaoFinalGateV2Service._();

  static final MigracaoFinalGateV2Service instance =
      MigracaoFinalGateV2Service._();

  final AppDatabase _appDatabase = AppDatabase.instance;
  final OperacionalSyncService _operacional = OperacionalSyncService.instance;
  final ConfiguracaoRepository _configuracao = ConfiguracaoRepository();
  final SaudeSistemaRepository _saude = SaudeSistemaRepository();

  Future<MigracaoFinalGateV2Resultado> avaliar() async {
    final empresaId = await _operacional.empresaAtualId();
    if (empresaId == null || empresaId.trim().isEmpty) {
      throw StateError('Nenhuma empresa ativa foi identificada.');
    }

    final empresaLocal = await _appDatabase.empresaAtivaId;
    if (empresaLocal == null || empresaLocal.trim() != empresaId.trim()) {
      throw StateError(
        'O SQLite ativo não corresponde à empresa selecionada na nuvem.',
      );
    }

    final auditoria = await MigracaoFinalAuditoriaService.instance.auditar();
    final saude = await _saude.diagnosticarLocal();
    final motor = await SyncMotorService.instance.diagnosticar(empresaId);
    final configuracao = await _configuracao.obterConfiguracao();

    final conflitos = <String, int>{
      'Operacional':
          (await OperacionalCloudV2Service.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'Ordens de Serviço':
          (await OsCloudV3Service.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'Arquivos da OS':
          (await OsArquivosCloudV2Service.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'CRM/Orçamentos':
          (await CrmOrcamentosCloudV2Service.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'Estoque':
          (await EstoqueCloudConflitoService.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'Financeiro':
          (await FinanceiroCloudV2Service.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'Precificação':
          (await PrecificacaoCloudV2Service.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'Configurações':
          (await ConfiguracaoCloudService.instance.listarConflitosPendentes(
            empresaId: empresaId,
          )).length,
      'Arquivos de configuração':
          (await ConfiguracaoArquivosCloudService.instance
                  .listarConflitosPendentes(empresaId: empresaId))
              .length,
    };

    final conflitosTotal = conflitos.values.fold<int>(
      0,
      (total, valor) => total + valor,
    );

    final osArquivos = await OsArquivosCloudV2Service.instance.diagnosticar(
      empresaId,
    );
    final configArquivos = await ConfiguracaoArquivosCloudService.instance
        .diagnosticar(empresaId);

    final motorErros = _int(motor['modulos_erro']);
    final motorAguardando = _int(motor['modulos_aguardando']);
    final motorBloqueados = _int(motor['modulos_bloqueados']);
    final motorStatus = (motor['ultimo_ciclo_status'] ?? '').toString().trim();

    final backupEm = DateTime.tryParse(
      configuracao.ultimoBackupEm?.trim() ?? '',
    );
    final ultimoSyncEm = DateTime.tryParse(saude.ultimoSyncEm?.trim() ?? '');
    final backupRegistrado =
        configuracao.possuiUltimoBackup &&
        configuracao.ultimoBackupTamanhoBytes > 0 &&
        backupEm != null;
    final backupDepoisDoSync =
        backupRegistrado &&
        (ultimoSyncEm == null || !backupEm.isBefore(ultimoSyncEm));

    final coberturaPendente = saude.coberturaSync.fold<int>(
      0,
      (total, item) => total + item.pendentes,
    );

    final osStorageConflitos =
        _int(osArquivos['conflitos_pendentes']) +
        _int(osArquivos['assinaturas_em_conflito']);
    final osStorageErros =
        _int(osArquivos['fotos_com_erro']) +
        _int(osArquivos['checklist_com_erro']) +
        _int(osArquivos['assinaturas_com_erro']);
    final configStorageConflitos = _int(configArquivos['conflitos_pendentes']);

    final itens = <MigracaoFinalGateItem>[
      MigracaoFinalGateItem(
        chave: 'tenant',
        titulo: 'Empresa local isolada',
        detalhe: 'SQLite ativo e empresa Cloud usam o mesmo tenant.',
        ok:
            empresaLocal.trim() == empresaId.trim() &&
            saude.tenantsMapeados <= 1,
      ),
      MigracaoFinalGateItem(
        chave: 'sqlite',
        titulo: 'SQLite íntegro',
        detalhe:
            'Schema ${saude.versaoSchema}; '
            '${saude.violacoesForeignKey} violação(ões) de foreign key; '
            '${saude.criticos} alerta(s) crítico(s).',
        ok:
            saude.sqliteIntegro &&
            saude.versaoSchema == AppDatabase.schemaVersion &&
            saude.violacoesForeignKey == 0 &&
            saude.criticos == 0,
      ),
      MigracaoFinalGateItem(
        chave: 'backup',
        titulo: 'Backup obrigatório atualizado',
        detalhe: backupEm == null
            ? 'Nenhum backup válido foi registrado.'
            : 'Último backup: ${backupEm.toLocal().toIso8601String()}.',
        ok: backupDepoisDoSync,
      ),
      MigracaoFinalGateItem(
        chave: 'motor_sync',
        titulo: 'Motor de sincronização concluído',
        detalhe:
            'Último ciclo: ${motorStatus.isEmpty ? 'não identificado' : motorStatus}; '
            '$motorErros erro(s), $motorAguardando aguardando, '
            '$motorBloqueados bloqueado(s).',
        ok:
            motorStatus == 'Sucesso' &&
            motorErros == 0 &&
            motorAguardando == 0 &&
            motorBloqueados == 0,
      ),
      MigracaoFinalGateItem(
        chave: 'cobertura_sync',
        titulo: 'Cobertura operacional completa',
        detalhe: '$coberturaPendente registro(s) local(is) sem mapeamento.',
        ok: coberturaPendente == 0,
      ),
      MigracaoFinalGateItem(
        chave: 'filas',
        titulo: 'Filas pendentes zeradas',
        detalhe:
            '${saude.exclusoesSyncPendentes} exclusão(ões) aguardando sync; '
            '${saude.pontoPendentes} batida(s) de Ponto pendente(s).',
        ok: saude.exclusoesSyncPendentes == 0 && saude.pontoPendentes == 0,
      ),
      MigracaoFinalGateItem(
        chave: 'conflitos',
        titulo: 'Conflitos zerados',
        detalhe: '$conflitosTotal conflito(s) pendente(s) entre os módulos.',
        ok: conflitosTotal == 0,
      ),
      MigracaoFinalGateItem(
        chave: 'storage',
        titulo: 'Storage sem conflito',
        detalhe:
            'Arquivos OS: $osStorageConflitos conflito(s), '
            '$osStorageErros erro(s); '
            'Configurações: $configStorageConflitos conflito(s).',
        ok:
            osStorageConflitos == 0 &&
            osStorageErros == 0 &&
            configStorageConflitos == 0,
      ),
      MigracaoFinalGateItem(
        chave: 'auditoria_cloud',
        titulo: 'SQLite e Cloud equivalentes',
        detalhe:
            '${auditoria.divergencias} divergência(s) nas contagens/totais V1.',
        ok: auditoria.tudoConfere,
      ),
    ];

    return MigracaoFinalGateV2Resultado(
      empresaId: empresaId,
      itens: itens,
      auditoria: auditoria,
      conflitosPorModulo: conflitos,
    );
  }

  int _int(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse((valor ?? '').toString()) ?? 0;
  }
}
