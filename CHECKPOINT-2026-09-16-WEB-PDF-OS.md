# Checkpoint Imperium — PDF da OS no Web

Data: 2026-09-16
Branch: `desenvolvimento`

## Estado fechado deste lote

Lote de PDF da Ordem de Serviço no navegador concluído e validado localmente.

### Implementado

- serviço Web dedicado para gerar PDF da OS sem depender de `dart:io`;
- leitura de fotos, avarias e assinatura por bytes a partir do Supabase Storage privado;
- geração do documento com `pdf`;
- download/compartilhamento no navegador com `printing`;
- botão de PDF integrado à tela Web de arquivos da OS;
- teste de contrato garantindo ausência de `dart:io`, uso de bytes e integração do botão.

### Commits principais

- `a83c892` — serviço de PDF Web da OS;
- `6d44e65` — integração do botão de PDF na tela Web;
- `9adf76f` — teste de contrato do PDF Web.

## Validação local confirmada em 2026-09-16

- `flutter test test/web_os_pdf_source_test.dart` — PASSOU;
- `flutter analyze` — PASSOU;
- `flutter build web --target lib/main_web_bootstrap.dart --release` — PASSOU;
- build final gerado em `build/web`.

## Avisos não bloqueantes observados

- WASM dry-run aponta incompatibilidades da dependência `image 4.3.0`;
- aviso de fonte Cupertino no build;
- nenhum desses avisos bloqueou o build Web atual.

## Regra de segurança preservada

Este lote não alterou:

- finalização transacional da OS;
- estoque/FIFO;
- financeiro;
- autenticação;
- licença;
- RLS;
- sincronização Android existente;
- gerador PDF mobile existente.

## Próximo foco

Retornar ao desenvolvimento Mobile a partir deste checkpoint, mantendo o Web estabilizado neste ponto.
