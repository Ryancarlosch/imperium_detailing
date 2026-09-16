# Checkpoint Imperium — Arquivos da OS no Web

Data: 2026-09-16
Branch: `desenvolvimento`

## Objetivo deste lote

Levar para o Web a leitura dos arquivos de Ordem de Serviço que já são sincronizados pelo Android, reutilizando a infraestrutura existente do Supabase Storage e sem criar um banco ou fluxo paralelo.

## Implementado

### Serviço Web de arquivos da OS

Arquivo: `lib/services/web_os_arquivos_service.dart`

- usa a empresa ativa da sessão;
- consulta a OS por `empresa_id`;
- consulta `imperium_ordem_servico_fotos`;
- consulta `imperium_ordem_servico_checklist` para fotos de avaria;
- lê a assinatura já vinculada em `imperium_ordens_servico`;
- respeita soft delete (`excluido_em`);
- reutiliza o bucket privado `imperium-os-arquivos`;
- baixa conteúdo com `Supabase Storage` como bytes (`Uint8List`);
- não depende de `dart:io`.

### Visualizador Web

Arquivo: `lib/web/web_os_arquivos_page.dart`

- mostra totais de fotos, avarias e existência de assinatura;
- lista os arquivos sincronizados;
- abre a imagem diretamente de bytes;
- permite zoom com `InteractiveViewer`;
- possui atualização manual;
- mantém o Storage privado; não cria URL pública.

### Teste de contrato

Arquivo: `test/web_os_arquivos_source_test.dart`

Protege:

- tabelas remotas corretas;
- bucket correto;
- download por bytes;
- fotos, avarias e assinatura;
- ausência de `dart:io` na implementação Web.

## Commits do lote

- `9dc37d5` — `feat(web): adiciona leitura dos arquivos da OS`
- `47814ee` — `feat(web): adiciona visualizador de arquivos da OS`
- `c9926cb` — `test(web): protege visualizacao dos arquivos da OS`
- `f01e3bd` — `style: aplica dart format` (GitHub Actions)

## Estado de validação

- primeira execução de `Web Preview Build` parou somente no gate de formatação;
- o workflow de autoformatação corrigiu os dois arquivos apontados;
- este checkpoint cria um push humano sobre o código formatado para disparar novamente a validação completa;
- ainda falta ligar a tela ao botão da lista de Ordens de Serviço; essa integração será feita somente após `analyze`, teste e build do núcleo deste lote passarem.

## Regra de segurança preservada

Nenhuma alteração deste lote mexe em:

- finalização transacional da OS;
- baixa de estoque;
- financeiro;
- autenticação;
- licença;
- RLS;
- sincronização Android existente.

O Web apenas lê arquivos já sincronizados e autorizados pelas políticas existentes da empresa.

## Próximo passo exato

1. confirmar `Flutter Quality` e `Web Preview Build` verdes para este lote;
2. integrar `WebOsArquivosPage` à lista `WebOrdensV3Page`;
3. adicionar teste do botão/rota;
4. validar novamente;
5. atualizar roadmap técnico da etapa.
