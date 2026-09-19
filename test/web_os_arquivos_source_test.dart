import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Web gerencia arquivos da OS por bytes sem dart io na implementacao',
    () {
      final service = File(
        'lib/services/web_os_arquivos_service.dart',
      ).readAsStringSync();
      final page = File('lib/web/web_os_arquivos_page.dart').readAsStringSync();
      final ordens = File('lib/web/web_ordens_v3_page.dart').readAsStringSync();

      expect(service, contains("from('imperium_ordens_servico')"));
      expect(service, contains("from('imperium_ordem_servico_fotos')"));
      expect(service, contains("from('imperium_ordem_servico_checklist')"));
      expect(service, contains(".eq('empresa_id', empresaId)"));
      expect(service, contains(".eq('ordem_servico_id', id)"));
      expect(service, contains("_texto(row['excluido_em']).isEmpty"));
      expect(service, contains("storage.from(bucket).download(path)"));
      expect(service, contains("bucketPadrao = 'imperium-os-arquivos'"));
      expect(service, contains('Future<void> adicionarFoto'));
      expect(service, contains('Future<void> salvarChecklist'));
      expect(service, contains('Future<void> salvarAssinatura'));
      expect(service, contains('.uploadBinary('));
      expect(service, contains('FileOptions(upsert: true'));
      expect(service, contains("'origem_dispositivo': origem.dispositivoId"));
      expect(service, contains("'origem_local_id': origem.localId"));
      expect(service, contains(".eq('atualizado_em', esperado)"));
      expect(service, contains(".eq('atualizado_em', atualizadoEm.trim())"));
      expect(service, contains("status != 'Aberta'"));
      expect(service, contains("status != 'Em andamento'"));
      expect(service, contains("'tipo': 'foto'"));
      expect(service, contains("'tipo': 'avaria'"));
      expect(service, contains("'tipo': 'assinatura'"));
      expect(service, isNot(contains('createPublicUrl')));
      expect(service, isNot(contains("import 'dart:io'")));

      expect(page, contains('WebOsArquivosPage'));
      expect(page, contains('FutureBuilder<Uint8List>'));
      expect(page, contains('Image.memory'));
      expect(page, contains('InteractiveViewer'));
      expect(page, contains('FilePicker.platform.pickFiles'));
      expect(page, contains('SignatureController'));
      expect(page, contains('controller.toPngBytes()'));
      expect(page, contains('_service.adicionarFoto('));
      expect(page, contains('_service.salvarChecklist('));
      expect(page, contains('_service.salvarAssinatura('));
      expect(page, contains('sincronizada com o aplicativo'));
      expect(page, isNot(contains("import 'dart:io'")));

      expect(ordens, contains("import 'web_os_arquivos_page.dart';"));
      expect(ordens, contains('Future<void> _abrirArquivos'));
      expect(ordens, contains('WebOsArquivosPage('));
      expect(ordens, contains("tooltip: 'Fotos, avarias e assinatura'"));
      expect(ordens, contains('onPressed: () => _abrirArquivos(os)'));
      expect(
        ordens,
        contains("status != 'Aberta' && status != 'Em andamento'"),
      );
    },
  );
}
